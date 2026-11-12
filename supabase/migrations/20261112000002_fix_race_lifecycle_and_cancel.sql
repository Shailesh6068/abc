-- Migration: 20261112000002_fix_race_lifecycle_and_cancel.sql
-- Fixes:
-- 1. cancel_race allows cancelling/disbanding races in IN_PROGRESS or WAITING status
-- 2. record_participant_finish auto-completes head_to_head races and races where all participants finished
-- 3. transition_race_state allows any participant to mark COMPLETED on finish
-- 4. Cleans up stale races stuck IN_PROGRESS

-- 1. Cancel Race Function
DROP FUNCTION IF EXISTS public.cancel_race(UUID);

CREATE OR REPLACE FUNCTION public.cancel_race(p_race_id UUID)
RETURNS text AS $$
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

    IF v_race.creator_id <> v_user_id 
       AND NOT EXISTS (SELECT 1 FROM public.race_participants WHERE race_id = p_race_id AND user_id = v_user_id)
       AND NOT public.has_admin_role('super_admin', 'operations_admin') THEN
        RAISE EXCEPTION 'Only creator or authorized participant can cancel this race';
    END IF;

    UPDATE public.races
    SET status = 'CANCELLED',
        completed_at = NOW()
    WHERE id = p_race_id;

    UPDATE public.race_participants
    SET status = 'left'
    WHERE race_id = p_race_id AND status NOT IN ('finished');

    UPDATE public.race_invitations
    SET status = 'declined'
    WHERE race_id = p_race_id AND status = 'pending';

    RETURN 'CANCELLED';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Record Participant Finish Function
DROP FUNCTION IF EXISTS public.record_participant_finish(UUID, BIGINT, NUMERIC);

CREATE OR REPLACE FUNCTION public.record_participant_finish(
    p_race_id UUID,
    p_finish_time_ms BIGINT,
    p_validated_distance_m NUMERIC DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_unfinished_count INT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    UPDATE public.race_participants
    SET status = 'finished'::participant_status_type,
        finish_time_ms = p_finish_time_ms,
        validated_distance_m = COALESCE(p_validated_distance_m, validated_distance_m)
    WHERE race_id = p_race_id AND user_id = v_user_id;

    SELECT COUNT(*) INTO v_unfinished_count
    FROM public.race_participants
    WHERE race_id = p_race_id
      AND status NOT IN ('finished', 'left', 'dnf');

    IF v_race.mode = 'head_to_head' OR v_unfinished_count = 0 THEN
        UPDATE public.races
        SET status = 'COMPLETED',
            completed_at = NOW()
        WHERE id = p_race_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Transition Race State Function
CREATE OR REPLACE FUNCTION public.transition_race_state(
    p_race_id UUID,
    p_new_status race_status_type
)
RETURNS race_status_type AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_is_participant BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    v_is_admin := public.has_admin_role('super_admin', 'operations_admin');
    SELECT EXISTS (
        SELECT 1 FROM public.race_participants WHERE race_id = p_race_id AND user_id = v_user_id
    ) INTO v_is_participant;

    IF NOT v_is_admin AND v_race.creator_id <> v_user_id AND NOT v_is_participant THEN
        RAISE EXCEPTION 'Unauthorized to transition race state';
    END IF;

    IF p_new_status = 'CANCELLED' THEN
        UPDATE public.races SET status = 'CANCELLED', completed_at = NOW() WHERE id = p_race_id;
    ELSIF p_new_status = 'IN_PROGRESS' THEN
        UPDATE public.races SET status = 'IN_PROGRESS', actual_start_at = COALESCE(actual_start_at, NOW()) WHERE id = p_race_id;
        UPDATE public.race_participants SET status = 'racing' WHERE race_id = p_race_id AND status = 'ready';
    ELSIF p_new_status = 'COMPLETED' THEN
        UPDATE public.races SET status = 'COMPLETED', completed_at = NOW() WHERE id = p_race_id;
    ELSE
        UPDATE public.races SET status = p_new_status WHERE id = p_race_id;
    END IF;

    RETURN p_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Clean up old stuck races (> 30 minutes in active state)
UPDATE public.races
SET status = 'COMPLETED',
    completed_at = NOW()
WHERE status IN ('IN_PROGRESS', 'COUNTDOWN', 'READY_CHECK')
  AND created_at < NOW() - INTERVAL '30 minutes';
