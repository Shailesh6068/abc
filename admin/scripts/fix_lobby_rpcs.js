const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to PostgreSQL...');

  // 1. Clean up all stale waiting races older than 30 mins
  const cleanRes = await client.query(`
    UPDATE public.races
    SET status = 'CANCELLED'
    WHERE status IN ('WAITING', 'READY_CHECK')
      AND (created_at < NOW() - INTERVAL '30 minutes' OR id = 'a1d6619a-5f7f-41c3-b8f5-941d07072667');
  `);
  console.log('Stale races cancelled:', cleanRes.rowCount);

  // 2. Clean up participant rows for cancelled unstarted races
  await client.query(`
    DELETE FROM public.race_participants
    WHERE race_id IN (SELECT id FROM public.races WHERE status = 'CANCELLED');
  `);
  console.log('Cleaned participant rows for cancelled races.');

  // 3. Update create_race_secure to automatically cancel prior unstarted lobbies by the creator
  await client.query(`
    CREATE OR REPLACE FUNCTION public.create_race_secure(
        p_sport sport_type,
        p_mode race_mode_type,
        p_visibility race_visibility_type DEFAULT 'public',
        p_participant_limit INTEGER DEFAULT 4,
        p_route_id UUID DEFAULT NULL,
        p_configuration JSONB DEFAULT '{}'::jsonb
    )
    RETURNS UUID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
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

        -- Auto-cancel any existing unstarted lobby created by this user so old ghost lobbies never linger
        UPDATE public.races
        SET status = 'CANCELLED'
        WHERE creator_id = v_creator_id
          AND status IN ('WAITING', 'READY_CHECK');

        DELETE FROM public.race_participants
        WHERE race_id IN (SELECT id FROM public.races WHERE creator_id = v_creator_id AND status = 'CANCELLED');

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

        RETURN v_race_id;
    END;
    $$;
  `);
  console.log('Updated create_race_secure successfully.');

  // 4. Update cancel_race to completely cancel race and participant records
  await client.query(`
    CREATE OR REPLACE FUNCTION public.cancel_race(p_race_id UUID)
    RETURNS TEXT
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
    DECLARE
        v_user_id UUID := auth.uid();
        v_race RECORD;
    BEGIN
        SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
        IF NOT FOUND THEN
            RETURN 'NOT_FOUND';
        END IF;

        -- Cancel this race
        UPDATE public.races
        SET status = 'CANCELLED'
        WHERE id = p_race_id;

        DELETE FROM public.race_participants
        WHERE race_id = p_race_id;

        -- Also clean up any other stale waiting race by this host
        IF v_user_id IS NOT NULL THEN
            UPDATE public.races
            SET status = 'CANCELLED'
            WHERE creator_id = v_user_id
              AND status IN ('WAITING', 'READY_CHECK');

            DELETE FROM public.race_participants
            WHERE race_id IN (SELECT id FROM public.races WHERE creator_id = v_user_id AND status = 'CANCELLED');
        END IF;

        RETURN 'CANCELLED';
    END;
    $$;
  `);
  console.log('Updated cancel_race successfully.');

  // 5. Create leave_race RPC function
  await client.query(`DROP FUNCTION IF EXISTS public.leave_race(UUID);`);
  await client.query(`
    CREATE OR REPLACE FUNCTION public.leave_race(p_race_id UUID)
    RETURNS TEXT
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
    DECLARE
        v_user_id UUID := auth.uid();
        v_race RECORD;
        v_remaining_count INT;
    BEGIN
        IF v_user_id IS NULL THEN
            RAISE EXCEPTION 'Authentication required';
        END IF;

        SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
        IF NOT FOUND THEN
            RETURN 'NOT_FOUND';
        END IF;

        -- Remove the user from race_participants
        DELETE FROM public.race_participants
        WHERE race_id = p_race_id AND user_id = v_user_id;

        -- If the user who left is the creator, cancel the entire race
        IF v_race.creator_id = v_user_id THEN
            UPDATE public.races
            SET status = 'CANCELLED'
            WHERE id = p_race_id;
            
            DELETE FROM public.race_participants
            WHERE race_id = p_race_id;

            RETURN 'RACE_CANCELLED';
        END IF;

        -- Count remaining real human participants
        SELECT COUNT(*) INTO v_remaining_count
        FROM public.race_participants
        WHERE race_id = p_race_id AND user_id NOT IN (
            SELECT id FROM public.profiles WHERE is_bot = true
        );

        IF v_remaining_count = 0 THEN
            UPDATE public.races
            SET status = 'CANCELLED'
            WHERE id = p_race_id;
            RETURN 'RACE_CANCELLED';
        END IF;

        RETURN 'LEFT';
    END;
    $$;
  `);
  console.log('Created leave_race successfully.');

  // Check remaining active races
  const remaining = await client.query("SELECT id, creator_id, sport, mode, status, created_at FROM races WHERE status IN ('WAITING', 'READY_CHECK', 'IN_PROGRESS');");
  console.log('Active races remaining now:', remaining.rows.length);
  console.log(JSON.stringify(remaining.rows, null, 2));

  await client.end();
}

run().catch(console.error);
