-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: FUNCTIONS, PROCEDURES AND RPC
-- Server-authoritative logic for matchmaking, race lifecycle, GPS anti-cheat,
-- result finalization, and audit ledger.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CLEANUP STALE PRESENCE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_stale_presence()
RETURNS void AS $$
BEGIN
    DELETE FROM public.player_presence
    WHERE last_seen_at < (NOW() - INTERVAL '15 minutes');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 2. UPDATE PLAYER PRESENCE (Heartbeat & Location)
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 3. NEARBY MATCHMAKING (Section 9: ST_DWithin with Privacy Fuzzing)
-- Never returns raw coordinates; fuzzes distance to prevent triangulation
-- ------------------------------------------------------------------------------
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

    -- Clean stale records (30 minutes)
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

-- ------------------------------------------------------------------------------
-- 4. CREATE RACE SECURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_race_secure(
    p_sport sport_type,
    p_mode race_mode_type,
    p_visibility race_visibility_type DEFAULT 'public',
    p_participant_limit INTEGER DEFAULT 4,
    p_route_id UUID DEFAULT NULL,
    p_configuration JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
    v_creator_id UUID := auth.uid();
    v_race_id UUID;
BEGIN
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_participant_limit < 2 OR p_participant_limit > 20 THEN
        RAISE EXCEPTION 'Participant limit must be between 2 and 20';
    END IF;

    -- Insert race in WAITING status
    INSERT INTO public.races (
        creator_id,
        sport,
        mode,
        visibility,
        status,
        participant_limit,
        route_id,
        configuration
    )
    VALUES (
        v_creator_id,
        p_sport,
        p_mode,
        p_visibility,
        'WAITING',
        p_participant_limit,
        p_route_id,
        p_configuration
    )
    RETURNING id INTO v_race_id;

    -- Automatically enroll creator as ready
    INSERT INTO public.race_participants (
        race_id,
        user_id,
        status,
        joined_at,
        ready_at
    )
    VALUES (
        v_race_id,
        v_creator_id,
        'ready',
        NOW(),
        NOW()
    );

    -- Log audit event
    INSERT INTO public.audit_events (
        actor_id,
        event_type,
        entity_type,
        entity_id,
        sanitized_metadata
    )
    VALUES (
        v_creator_id,
        'RACE_CREATED',
        'races',
        v_race_id::text,
        jsonb_build_object('sport', p_sport, 'mode', p_mode, 'visibility', p_visibility)
    );

    RETURN v_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 5. JOIN RACE SECURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_race_secure(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_current_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status <> 'WAITING' THEN
        RAISE EXCEPTION 'Cannot join race; status is %', v_race.status;
    END IF;

    SELECT COUNT(*) INTO v_current_count 
    FROM public.race_participants 
    WHERE race_id = p_race_id;

    IF v_current_count >= v_race.participant_limit THEN
        RAISE EXCEPTION 'Race lobby is full';
    END IF;

    INSERT INTO public.race_participants (race_id, user_id, status, joined_at)
    VALUES (p_race_id, v_user_id, 'joined', NOW())
    ON CONFLICT (race_id, user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 6. SET PARTICIPANT READINESS & CHECK AUTO-START
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_participant_ready(
    p_race_id UUID,
    p_is_ready BOOLEAN
)
RETURNS TEXT AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_total_participants INTEGER;
    v_ready_participants INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK') THEN
        RAISE EXCEPTION 'Cannot change readiness in status %', v_race.status;
    END IF;

    UPDATE public.race_participants
    SET status = CASE WHEN p_is_ready THEN 'ready'::participant_status_type ELSE 'joined'::participant_status_type END,
        ready_at = CASE WHEN p_is_ready THEN NOW() ELSE NULL END
    WHERE race_id = p_race_id AND user_id = v_user_id;

    -- Check if all participants are ready
    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'ready')
    INTO v_total_participants, v_ready_participants
    FROM public.race_participants
    WHERE race_id = p_race_id;

    IF v_total_participants >= 2 AND v_total_participants = v_ready_participants THEN
        UPDATE public.races
        SET status = 'COUNTDOWN',
            scheduled_start_at = NOW() + INTERVAL '10 seconds'
        WHERE id = p_race_id;
        RETURN 'COUNTDOWN_STARTED';
    END IF;

    RETURN 'READY_UPDATED';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 7. TRANSITION RACE STATE (Strict State Machine)
-- Allowed: WAITING -> READY_CHECK -> COUNTDOWN -> IN_PROGRESS -> FINISHING -> COMPLETED
-- Or CANCELLED / ABORTED
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_race_state(
    p_race_id UUID,
    p_new_status race_status_type
)
RETURNS race_status_type AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_is_admin BOOLEAN;
BEGIN
    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    v_is_admin := public.has_admin_role('super_admin', 'operations_admin');

    -- Authorization check
    IF NOT v_is_admin AND v_race.creator_id <> v_user_id THEN
        RAISE EXCEPTION 'Only creator or authorized administrator can transition race state';
    END IF;

    -- Valid state transitions validation
    IF p_new_status = 'CANCELLED' THEN
        IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
            RAISE EXCEPTION 'Race cannot be cancelled once in progress';
        END IF;
    ELSIF p_new_status = 'ABORTED' THEN
        IF v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN
            RAISE EXCEPTION 'Only active races can be aborted';
        END IF;
    ELSIF p_new_status = 'READY_CHECK' THEN
        IF v_race.status <> 'WAITING' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'COUNTDOWN' THEN
        IF v_race.status NOT IN ('WAITING', 'READY_CHECK') THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'IN_PROGRESS' THEN
        IF v_race.status <> 'COUNTDOWN' THEN RAISE EXCEPTION 'Race must go through countdown before starting'; END IF;
        UPDATE public.races SET actual_start_at = NOW() WHERE id = p_race_id;
        UPDATE public.race_participants SET status = 'racing' WHERE race_id = p_race_id AND status = 'ready';
    ELSIF p_new_status = 'FINISHING' THEN
        IF v_race.status <> 'IN_PROGRESS' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'COMPLETED' THEN
        IF v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.races SET completed_at = NOW() WHERE id = p_race_id;
    END IF;

    UPDATE public.races
    SET status = p_new_status
    WHERE id = p_race_id;

    RETURN p_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 8. SUBMIT GPS BATCH WITH ANTI-CHEAT VALIDATION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_gps_batch(
    p_race_id UUID,
    p_samples JSONB -- Array of {sequence_no, latitude, longitude, accuracy_m, altitude_m, recorded_at}
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_sample RECORD;
    v_last_sample RECORD;
    v_accepted INTEGER := 0;
    v_rejected INTEGER := 0;
    v_max_speed_mps DOUBLE PRECISION;
    v_speed_calculated DOUBLE PRECISION;
    v_delta_meters DOUBLE PRECISION;
    v_delta_seconds DOUBLE PRECISION;
    v_flagged_reason TEXT := NULL;
    v_total_valid_dist NUMERIC := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id;
    IF NOT FOUND OR v_race.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'Race is not active';
    END IF;

    -- Sport specific physical max speeds (with margin for GPS jitter)
    -- Running: 12.5 m/s (~45 km/h, Usain Bolt peak is ~44.7 km/h)
    -- Cycling: 30 m/s (~108 km/h, sprint/descent)
    -- Motorbike: 100 m/s (~360 km/h, closed circuit)
    IF v_race.sport = 'running' THEN
        v_max_speed_mps := 12.5;
    ELSIF v_race.sport = 'cycling' THEN
        v_max_speed_mps := 30.0;
    ELSE
        v_max_speed_mps := 100.0;
    END IF;

    -- Fetch the participant's most recent valid sample
    SELECT * INTO v_last_sample 
    FROM public.gps_samples 
    WHERE race_id = p_race_id AND user_id = v_user_id 
    ORDER BY sequence_no DESC LIMIT 1;

    -- Iterate through submitted samples
    FOR v_sample IN 
        SELECT 
            (s->>'sequence_no')::INTEGER AS sequence_no,
            (s->>'latitude')::DOUBLE PRECISION AS latitude,
            (s->>'longitude')::DOUBLE PRECISION AS longitude,
            (s->>'accuracy_m')::DOUBLE PRECISION AS accuracy_m,
            (s->>'altitude_m')::DOUBLE PRECISION AS altitude_m,
            (s->>'recorded_at')::TIMESTAMPTZ AS recorded_at
        FROM jsonb_array_elements(p_samples) AS s
        ORDER BY (s->>'sequence_no')::INTEGER ASC
    LOOP
        -- Sanity & bounds check
        IF v_sample.latitude < -90 OR v_sample.latitude > 90 OR 
           v_sample.longitude < -180 OR v_sample.longitude > 180 OR
           v_sample.accuracy_m > 50.0 -- Reject noisy samples > 50m accuracy
        THEN
            v_rejected := v_rejected + 1;
            CONTINUE;
        END IF;

        -- Ensure sequence increment
        IF v_last_sample.sequence_no IS NOT NULL AND v_sample.sequence_no <= v_last_sample.sequence_no THEN
            -- Duplicate or out-of-order sample
            v_rejected := v_rejected + 1;
            CONTINUE;
        END IF;

        -- Velocity jump calculation
        IF v_last_sample.latitude IS NOT NULL THEN
            v_delta_meters := ST_Distance(
                ST_SetSRID(ST_MakePoint(v_sample.longitude, v_sample.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint(v_last_sample.longitude, v_last_sample.latitude), 4326)::geography
            );
            v_delta_seconds := EXTRACT(EPOCH FROM (v_sample.recorded_at - v_last_sample.recorded_at));

            IF v_delta_seconds > 0.05 THEN
                v_speed_calculated := v_delta_meters / v_delta_seconds;
                IF v_speed_calculated > v_max_speed_mps THEN
                    -- Flag implausible teleportation / spoofing
                    v_flagged_reason := 'IMPLAUSIBLE_SPEED_JUMP';
                    v_rejected := v_rejected + 1;
                    CONTINUE;
                END IF;
                v_total_valid_dist := v_total_valid_dist + v_delta_meters;
            END IF;
        END IF;

        -- Insert valid sample
        INSERT INTO public.gps_samples (
            race_id,
            user_id,
            sequence_no,
            latitude,
            longitude,
            accuracy_m,
            altitude_m,
            speed_mps,
            recorded_at,
            received_at
        )
        VALUES (
            p_race_id,
            v_user_id,
            v_sample.sequence_no,
            v_sample.latitude,
            v_sample.longitude,
            v_sample.accuracy_m,
            v_sample.altitude_m,
            COALESCE(v_speed_calculated, 0),
            v_sample.recorded_at,
            NOW()
        )
        ON CONFLICT (race_id, user_id, sequence_no) DO NOTHING;

        v_accepted := v_accepted + 1;
        v_last_sample := v_sample;
    END LOOP;

    -- Update participant's validated distance
    IF v_total_valid_dist > 0 THEN
        UPDATE public.race_participants
        SET validated_distance_m = COALESCE(validated_distance_m, 0) + v_total_valid_dist
        WHERE race_id = p_race_id AND user_id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'accepted', v_accepted,
        'rejected', v_rejected,
        'flagged_reason', v_flagged_reason
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 9. FINALIZE RACE RESULTS (Idempotent Server Finalization)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalize_race_results(p_race_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_race RECORD;
    v_part RECORD;
    v_rank INTEGER := 1;
    v_existing_results_count INTEGER;
    v_xp_gain INTEGER;
    v_rating_delta INTEGER;
    v_elapsed BIGINT;
BEGIN
    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    -- Idempotency check: if already finalized, return existing results
    SELECT COUNT(*) INTO v_existing_results_count FROM public.race_results WHERE race_id = p_race_id;
    IF v_existing_results_count > 0 THEN
        RETURN jsonb_build_object('status', 'ALREADY_FINALIZED', 'results_count', v_existing_results_count);
    END IF;

    -- Transition race to COMPLETED
    UPDATE public.races 
    SET status = 'COMPLETED', completed_at = NOW() 
    WHERE id = p_race_id;

    -- Process rankings based on race mode
    -- Time Trial: highest verified distance wins
    -- Distance Race: fastest finish time or highest distance
    FOR v_part IN
        SELECT 
            rp.user_id,
            rp.validated_distance_m,
            rp.finish_time_ms,
            rp.status AS part_status
        FROM public.race_participants rp
        WHERE rp.race_id = p_race_id
        ORDER BY 
            CASE WHEN v_race.mode = 'time_trial' THEN rp.validated_distance_m END DESC NULLS LAST,
            CASE WHEN v_race.mode <> 'time_trial' THEN COALESCE(rp.finish_time_ms, 999999999) END ASC,
            rp.joined_at ASC
    LOOP
        v_elapsed := COALESCE(v_part.finish_time_ms, 
            EXTRACT(EPOCH FROM (NOW() - COALESCE(v_race.actual_start_at, v_race.created_at))) * 1000)::BIGINT;

        -- Insert official verified result
        INSERT INTO public.race_results (
            race_id,
            user_id,
            rank,
            verified_distance_m,
            elapsed_ms,
            validation_status,
            validation_summary,
            finalized_at
        )
        VALUES (
            p_race_id,
            v_part.user_id,
            v_rank,
            COALESCE(v_part.validated_distance_m, 0),
            v_elapsed,
            'valid',
            jsonb_build_object('rank', v_rank, 'mode', v_race.mode, 'sport', v_race.sport),
            NOW()
        );

        -- Calculate XP & Rating awards
        -- 1st: 100 XP, +25 Rating
        -- 2nd: 60 XP, +10 Rating
        -- 3rd: 40 XP, +5 Rating
        -- Others: 20 XP, 0 Rating
        IF v_rank = 1 THEN
            v_xp_gain := 100;
            v_rating_delta := 25;
        ELSIF v_rank = 2 THEN
            v_xp_gain := 60;
            v_rating_delta := 10;
        ELSIF v_rank = 3 THEN
            v_xp_gain := 40;
            v_rating_delta := 5;
        ELSE
            v_xp_gain := 20;
            v_rating_delta := 0;
        END IF;

        -- Update Leaderboard entries
        INSERT INTO public.leaderboard_entries (
            user_id,
            sport,
            rating,
            xp,
            races_completed,
            wins
        )
        VALUES (
            v_part.user_id,
            v_race.sport,
            1200 + v_rating_delta,
            v_xp_gain,
            1,
            CASE WHEN v_rank = 1 THEN 1 ELSE 0 END
        )
        ON CONFLICT (user_id, sport) DO UPDATE SET
            rating = GREATEST(0, public.leaderboard_entries.rating + v_rating_delta),
            xp = public.leaderboard_entries.xp + v_xp_gain,
            races_completed = public.leaderboard_entries.races_completed + 1,
            wins = public.leaderboard_entries.wins + (CASE WHEN v_rank = 1 THEN 1 ELSE 0 END),
            updated_at = NOW();

        -- Award First Race achievement
        INSERT INTO public.user_achievements (user_id, achievement_id, earned_at)
        VALUES (v_part.user_id, 'first_race', NOW())
        ON CONFLICT DO NOTHING;

        IF v_rank = 1 THEN
            INSERT INTO public.user_achievements (user_id, achievement_id, earned_at)
            VALUES (v_part.user_id, 'podium_finisher', NOW())
            ON CONFLICT DO NOTHING;
        END IF;

        v_rank := v_rank + 1;
    END LOOP;

    -- Audit log
    INSERT INTO public.audit_events (
        actor_id,
        event_type,
        entity_type,
        entity_id,
        sanitized_metadata
    )
    VALUES (
        v_race.creator_id,
        'RACE_FINALIZED',
        'races',
        p_race_id::text,
        jsonb_build_object('sport', v_race.sport, 'mode', v_race.mode, 'ranks_awarded', v_rank - 1)
    );

    RETURN jsonb_build_object('status', 'SUCCESS', 'ranks_awarded', v_rank - 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
