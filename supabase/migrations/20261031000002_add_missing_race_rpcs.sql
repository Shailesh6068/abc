-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: ADD MISSING RACE RPCS
-- Adds: start_race_now, add_bot_participant, cancel_race, leave_race
-- Updates submit_gps_batch to accept samples during 'FINISHING' state
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. START RACE NOW (Host force start)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_race_now(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    -- Allow creator or participant
    IF v_race.creator_id <> v_user_id THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.race_participants 
            WHERE race_id = p_race_id AND user_id = v_user_id
        ) THEN
            RAISE EXCEPTION 'Only race host can force start the race';
        END IF;
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        RAISE EXCEPTION 'Cannot start race with status %', v_race.status;
    END IF;

    -- Set all joined participants to ready
    UPDATE public.race_participants
    SET status = 'ready'::participant_status_type,
        ready_at = COALESCE(ready_at, NOW())
    WHERE race_id = p_race_id AND status = 'joined';

    -- Set race status to COUNTDOWN with scheduled start in 5 seconds
    UPDATE public.races
    SET status = 'COUNTDOWN',
        scheduled_start_at = NOW() + INTERVAL '5 seconds'
    WHERE id = p_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 2. ADD BOT PARTICIPANT (Simulated AI competitor for lobby testing)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_bot_participant(
    p_race_id UUID,
    p_bot_name TEXT DEFAULT 'Racer Vikram (AI)'
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_bot_id UUID;
    v_bot_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status <> 'WAITING' THEN
        RAISE EXCEPTION 'Cannot add bots to race with status %', v_race.status;
    END IF;

    -- Generate a deterministic UUID based on race and existing participant count
    SELECT COUNT(*) INTO v_bot_count FROM public.race_participants WHERE race_id = p_race_id;
    v_bot_id := md5(p_race_id::text || '_bot_' || v_bot_count::text)::uuid;

    -- Ensure bot user exists in auth.users if auth table is active
    BEGIN
        INSERT INTO auth.users (id, aud, role, email)
        VALUES (v_bot_id, 'authenticated', 'authenticated', 'bot_' || SUBSTRING(v_bot_id::text, 1, 8) || '@racezone.local')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        -- Auth table might not be directly writeable in non-superuser mode
        NULL;
    END;

    -- Ensure bot profile exists in public.profiles
    INSERT INTO public.profiles (id, display_name, account_status)
    VALUES (v_bot_id, COALESCE(p_bot_name, 'Racer Vikram (AI)'), 'active')
    ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

    -- Add bot to race participants as ready
    INSERT INTO public.race_participants (race_id, user_id, status, joined_at, ready_at)
    VALUES (p_race_id, v_bot_id, 'ready'::participant_status_type, NOW(), NOW())
    ON CONFLICT (race_id, user_id) DO UPDATE SET status = 'ready'::participant_status_type;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 3. CANCEL RACE (Host or Admin disbands room)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_race(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.creator_id <> v_user_id AND NOT public.has_admin_role('super_admin', 'operations_admin') THEN
        RAISE EXCEPTION 'Only creator or authorized administrator can cancel this race';
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        RAISE EXCEPTION 'Race cannot be cancelled once in progress';
    END IF;

    UPDATE public.races
    SET status = 'CANCELLED'
    WHERE id = p_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 4. LEAVE RACE (Participant leaves lobby or marks DNF during live race)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_race(p_race_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_next_creator UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        -- Remove participant from lobby
        DELETE FROM public.race_participants
        WHERE race_id = p_race_id AND user_id = v_user_id;

        -- If creator left, promote next participant or cancel race
        IF v_race.creator_id = v_user_id THEN
            SELECT user_id INTO v_next_creator
            FROM public.race_participants
            WHERE race_id = p_race_id
            ORDER BY joined_at ASC
            LIMIT 1;

            IF v_next_creator IS NOT NULL THEN
                UPDATE public.races SET creator_id = v_next_creator WHERE id = p_race_id;
            ELSE
                UPDATE public.races SET status = 'CANCELLED' WHERE id = p_race_id;
            END IF;
        END IF;

        RETURN 'LEFT_LOBBY';
    ELSIF v_race.status IN ('IN_PROGRESS', 'FINISHING') THEN
        -- Mark participant as DNF
        UPDATE public.race_participants
        SET status = 'dnf'::participant_status_type
        WHERE race_id = p_race_id AND user_id = v_user_id;

        -- If no one is actively racing anymore, finalize the race
        IF NOT EXISTS (
            SELECT 1 FROM public.race_participants
            WHERE race_id = p_race_id AND status = 'racing'
        ) THEN
            PERFORM public.finalize_race_results(p_race_id);
        END IF;

        RETURN 'MARKED_DNF';
    ELSE
        RETURN 'NO_ACTION';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 5. UPDATE SUBMIT_GPS_BATCH TO ACCEPT SAMPLES IN 'FINISHING' STATUS
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
    IF NOT FOUND OR v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN
        RAISE EXCEPTION 'Race is not active';
    END IF;

    -- Sport specific physical max speeds
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
        -- Bounds & accuracy check
        IF v_sample.latitude < -90 OR v_sample.latitude > 90 OR 
           v_sample.longitude < -180 OR v_sample.longitude > 180 OR
           v_sample.accuracy_m > 50.0
        THEN
            v_rejected := v_rejected + 1;
            CONTINUE;
        END IF;

        -- Ensure sequence increment
        IF v_last_sample.sequence_no IS NOT NULL AND v_sample.sequence_no <= v_last_sample.sequence_no THEN
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
