const { Client } = require('../node_modules/pg');

const client = new Client({
  connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to DB');

  // 1. Enable REPLICA IDENTITY FULL for detailed realtime payloads
  await client.query(`
    ALTER TABLE public.race_invitations REPLICA IDENTITY FULL;
    ALTER TABLE public.races REPLICA IDENTITY FULL;
    ALTER TABLE public.race_participants REPLICA IDENTITY FULL;
    ALTER TABLE public.player_presence REPLICA IDENTITY FULL;
  `);
  console.log('Replica identity set to FULL');

  // 2. Add tables to supabase_realtime publication
  await client.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
      END IF;
    END $$;

    ALTER PUBLICATION supabase_realtime ADD TABLE public.race_invitations;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.races;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.race_participants;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.player_presence;
  `);
  console.log('Added tables to supabase_realtime publication');

  // 3. Verify
  const pubs = await client.query("SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime';");
  console.log('Updated Realtime tables:', pubs.rows);

  // 4. Cancel any old lingering WAITING races
  const cleaned = await client.query(`
    UPDATE public.races 
    SET status = 'CANCELLED' 
    WHERE status IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') 
      AND created_at < NOW() - INTERVAL '15 minutes';
  `);
  console.log('Cleaned old stale races:', cleaned.rowCount);

  await client.end();
}

run().catch(console.error);
