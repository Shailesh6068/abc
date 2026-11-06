-- ==============================================================================
-- RACEZONE MIGRATION: FIX NEARBY DEVICE & COMPETITOR DISCOVERY
-- Resolves presence registration, profile/preference sync, and PostGIS matching
-- ==============================================================================

-- 1. Ensure update_player_presence creates/heals missing profile & preferences
CREATE OR REPLACE FUNCTION public.update_player_presence(
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_sport sport_type DEFAULT 'running',
    p_is_available BOOLEAN DEFAULT true
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_latitude < -90 OR p_latitude > 90 OR p_longitude < -180 OR p_longitude > 180 THEN
        RAISE EXCEPTION 'Invalid coordinates provided';
    END IF;

    -- Ensure profile exists and account is active so user appears in discovery
    INSERT INTO public.profiles (id, display_name, account_status)
    VALUES (
        v_user_id,
        'Racer_' || SUBSTRING(v_user_id::text, 1, 6),
        'active'
    ) ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    -- Ensure player_preferences exists with discovery_enabled = true
    INSERT INTO public.player_preferences (user_id, discovery_enabled)
    VALUES (v_user_id, true)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.player_presence (
        user_id,
        location,
        selected_sport,
        is_available,
        last_seen_at,
        location_updated_at
    )
    VALUES (
        v_user_id,
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
        COALESCE(p_sport, 'running'::sport_type),
        p_is_available,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        location = EXCLUDED.location,
        selected_sport = EXCLUDED.selected_sport,
        is_available = EXCLUDED.is_available,
        last_seen_at = NOW(),
        location_updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Resilient get_nearby_players PostGIS function
CREATE OR REPLACE FUNCTION public.get_nearby_players(
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_radius_m INTEGER DEFAULT 1000,
    p_sport sport_type DEFAULT NULL,
    p_limit INTEGER DEFAULT 30
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    approx_distance_m INTEGER,
    sport sport_type,
    is_available BOOLEAN,
    rating INTEGER
) AS $$
DECLARE
    v_origin GEOGRAPHY;
    v_max_radius INTEGER := 50000; -- Support up to 50km for cycling, motorbike and regional matchmaking
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Validate radius bound
    p_radius_m := LEAST(GREATEST(p_radius_m, 50), v_max_radius);
    v_origin := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

    -- Clean stale records older than 30 minutes
    DELETE FROM public.player_presence
    WHERE last_seen_at < (NOW() - INTERVAL '30 minutes');

    RETURN QUERY
    SELECT 
        p.id AS user_id,
        COALESCE(p.display_name, 'Racer_' || SUBSTRING(p.id::text, 1, 6)) AS display_name,
        p.avatar_url,
        -- Round distance to nearest 25 meters (minimum 10m to prevent 0m display when adjacent)
        GREATEST(10, (ROUND(ST_Distance(pr.location, v_origin) / 25.0) * 25)::INTEGER) AS approx_distance_m,
        pr.selected_sport AS sport,
        COALESCE(pr.is_available, true) AS is_available,
        COALESCE(le.rating, 1200) AS rating
    FROM public.player_presence pr
    JOIN public.profiles p ON p.id = pr.user_id
    LEFT JOIN public.player_preferences pref ON pref.user_id = pr.user_id
    LEFT JOIN public.leaderboard_entries le ON le.user_id = pr.user_id AND le.sport = pr.selected_sport
    WHERE pr.user_id <> auth.uid()
      AND COALESCE(pr.is_available, true) = true
      AND COALESCE(pref.discovery_enabled, true) = true
      AND COALESCE(p.account_status, 'active') = 'active'
      AND (p_sport IS NULL OR pr.selected_sport = p_sport)
      AND ST_DWithin(pr.location, v_origin, p_radius_m)
      AND pr.last_seen_at >= (NOW() - INTERVAL '30 minutes')
    ORDER BY ST_Distance(pr.location, v_origin) ASC
    LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_players(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, sport_type, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_player_presence(DOUBLE PRECISION, DOUBLE PRECISION, sport_type, BOOLEAN) TO authenticated;
