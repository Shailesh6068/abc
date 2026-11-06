const { Client } = require('pg');

async function run() {
  const client = new Client({
    host: 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: 6543,
    user: 'postgres.zifkhsscgjojtmzwbqio',
    password: 'Spdj60686068@',
    database: 'postgres',
    ssl: { rejectUnauthorized: false }
  });
  await client.connect();

  await client.query(`DROP FUNCTION IF EXISTS public.add_bot_participant(UUID, TEXT);`);
  await client.query(`DROP FUNCTION IF EXISTS public.add_bot_participant(UUID);`);

  // 2. Fix add_bot_participant to use real auth users with valid foreign key
  await client.query(`
    CREATE OR REPLACE FUNCTION public.add_bot_participant(
        p_race_id UUID,
        p_bot_name TEXT DEFAULT 'Racer Vikram (AI)'
    )
    RETURNS TEXT
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
    DECLARE
        v_bot_id UUID;
        v_bot_name TEXT := p_bot_name;
        v_count INTEGER;
    BEGIN
        -- Find a bot account that is not yet participating in this race
        SELECT u.id, p.display_name INTO v_bot_id, v_bot_name
        FROM auth.users u
        JOIN public.profiles p ON p.id = u.id
        WHERE u.email LIKE 'bot.%@racezone.internal'
          AND u.id NOT IN (
              SELECT user_id FROM public.race_participants WHERE race_id = p_race_id
          )
        LIMIT 1;

        -- If none found, fallback to the first bot account
        IF v_bot_id IS NULL THEN
            SELECT u.id, p.display_name INTO v_bot_id, v_bot_name
            FROM auth.users u
            JOIN public.profiles p ON p.id = u.id
            WHERE u.email LIKE 'bot.%@racezone.internal'
            LIMIT 1;
        END IF;

        IF v_bot_id IS NULL THEN
            RAISE EXCEPTION 'No bot account configured';
        END IF;

        -- Ensure profile has proper name
        UPDATE public.profiles 
        SET display_name = COALESCE(p_bot_name, v_bot_name)
        WHERE id = v_bot_id;

        -- Add bot to race participants marked ready
        INSERT INTO public.race_participants (race_id, user_id, status, joined_at, ready_at)
        VALUES (p_race_id, v_bot_id, 'ready', NOW(), NOW())
        ON CONFLICT (race_id, user_id) 
        DO UPDATE SET status = 'ready', ready_at = NOW();

        RETURN 'BOT_ADDED';
    END;
    $$;
  `);
  console.log('Updated add_bot_participant successfully!');

  // 3. Update start_race_now to allow starting countdown smoothly
  await client.query(`
    CREATE OR REPLACE FUNCTION public.start_race_now(p_race_id UUID)
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
            RAISE EXCEPTION 'Race not found';
        END IF;

        -- Mark host participant ready
        IF v_user_id IS NOT NULL THEN
            UPDATE public.race_participants
            SET status = 'ready', ready_at = NOW()
            WHERE race_id = p_race_id AND user_id = v_user_id;
        END IF;

        -- Transition to COUNTDOWN
        UPDATE public.races
        SET status = 'COUNTDOWN',
            scheduled_start_at = NOW() + INTERVAL '5 seconds'
        WHERE id = p_race_id;

        RETURN 'COUNTDOWN_STARTED';
    END;
    $$;
  `);
  console.log('Updated start_race_now successfully!');

  // 4. Update cancel_race to allow clean cancel
  await client.query(`DROP FUNCTION IF EXISTS public.cancel_race(UUID);`);
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
            RAISE EXCEPTION 'Race not found';
        END IF;

        UPDATE public.races
        SET status = 'CANCELLED'
        WHERE id = p_race_id;

        RETURN 'CANCELLED';
    END;
    $$;
  `);
  console.log('Updated cancel_race successfully!');

  await client.end();
}
run().catch(console.error);
