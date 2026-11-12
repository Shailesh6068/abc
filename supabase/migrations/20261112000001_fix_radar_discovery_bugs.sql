-- ============================================================
-- FIX: Radar nearby discovery bugs
-- 1. Force discovery_enabled=true for all active users (the main bug)
-- 2. update_player_presence always sets discovery_enabled=true
-- 3. get_nearby_players uses COALESCE so missing prefs = visible
-- ============================================================

-- Fix 1: Enable discovery for all existing users who have it disabled
-- (shadowhh had discovery_enabled=false which blocked them from radar)
UPDATE public.player_preferences
SET discovery_enabled = true
WHERE discovery_enabled = false OR discovery_enabled IS NULL;

-- Fix 2: Ensure ALL presence users have player_preferences with discovery on
INSERT INTO public.player_preferences (user_id, discovery_enabled)
SELECT pr.user_id, true
FROM public.player_presence pr
WHERE NOT EXISTS (
  SELECT 1 FROM public.player_preferences pp WHERE pp.user_id = pr.user_id
)
ON CONFLICT (user_id) DO UPDATE SET discovery_enabled = true;

-- Fix 3: Update update_player_presence to always ensure discovery_enabled=true 
-- (it currently does ON CONFLICT DO NOTHING - doesn't fix existing false values)
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
    -- Use DO UPDATE to fix existing false values (not DO NOTHING)
    INSERT INTO public.player_preferences (user_id, discovery_enabled)
    VALUES (v_user_id, true)
    ON CONFLICT (user_id) DO UPDATE SET discovery_enabled = true
    WHERE public.player_preferences.discovery_enabled = false 
       OR public.player_preferences.discovery_enabled IS NULL;

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

-- Fix 4: get_nearby_players - extend stale window, use COALESCE for missing prefs
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
    v_max_radius INTEGER := 50000;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Validate radius bound
    p_radius_m := LEAST(GREATEST(p_radius_m, 50), v_max_radius);
    v_origin := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

    -- Clean stale records older than 60 minutes (was 30, give more time for reconnect)
    DELETE FROM public.player_presence
    WHERE last_seen_at < (NOW() - INTERVAL '60 minutes');

    RETURN QUERY
    SELECT 
        p.id AS user_id,
        COALESCE(p.display_name, 'Racer_' || SUBSTRING(p.id::text, 1, 6)) AS display_name,
        p.avatar_url,
        -- Round to nearest 25 meters, minimum 10m
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
      AND COALESCE(pref.discovery_enabled, true) = true  -- COALESCE so missing pref = visible
      AND COALESCE(p.account_status, 'active') = 'active'
      AND (p_sport IS NULL OR pr.selected_sport = p_sport)
      AND ST_DWithin(pr.location, v_origin, p_radius_m)
      AND pr.last_seen_at >= (NOW() - INTERVAL '60 minutes')
    ORDER BY ST_Distance(pr.location, v_origin) ASC
    LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_players(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, sport_type, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_player_presence(DOUBLE PRECISION, DOUBLE PRECISION, sport_type, BOOLEAN) TO authenticated;

