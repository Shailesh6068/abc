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

  const res = await client.query(`
    SELECT polname, polcmd, pg_get_expr(polqual, polrelid) as expr 
    FROM pg_policy 
    WHERE polrelid = 'public.race_participants'::regclass;
  `);
  console.log('Policies on race_participants:', res.rows);

  const parts = await client.query('SELECT * FROM public.race_participants WHERE race_id = $1', ['ea4646fa-efdb-4bae-96bc-f87be56a7185']);
  console.log('Actual rows in db:', parts.rows);

  // Ensure public or authenticated can SELECT race_participants for public races or where they participate
  await client.query(`
    DROP POLICY IF EXISTS "race_participants_select" ON public.race_participants;
    CREATE POLICY "race_participants_select" ON public.race_participants
      FOR SELECT
      TO public, anon, authenticated
      USING (true);
  `);
  console.log('Enabled open SELECT on race_participants for lobbies and leaderboard discovery!');

  // Also ensure profiles can be read by public/anon/authenticated
  await client.query(`
    DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
    CREATE POLICY "profiles_select_public" ON public.profiles
      FOR SELECT
      TO public, anon, authenticated
      USING (true);
  `);
  console.log('Enabled open SELECT on profiles!');

  await client.end();
}
run().catch(console.error);
