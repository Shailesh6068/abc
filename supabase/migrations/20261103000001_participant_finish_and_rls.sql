-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: PARTICIPANT FINISH & RLS UPDATE
-- Adds UPDATE policy on race_participants for authenticated racers
-- Adds record_participant_finish RPC function
-- ==============================================================================

-- 1. RLS UPDATE policy on race_participants
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'race_participants' 
          AND policyname = 'Users can update their own participant record'
    ) THEN
        CREATE POLICY "Users can update their own participant record"
        ON public.race_participants FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 2. Secure RPC to record participant finish
CREATE OR REPLACE FUNCTION public.record_participant_finish(
    p_race_id UUID,
    p_finish_time_ms BIGINT,
    p_validated_distance_m NUMERIC DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    UPDATE public.race_participants
    SET status = 'finished'::participant_status_type,
        finish_time_ms = p_finish_time_ms,
        validated_distance_m = COALESCE(p_validated_distance_m, validated_distance_m)
    WHERE race_id = p_race_id AND user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

