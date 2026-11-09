const { Client } = require('../node_modules/pg');

const client = new Client({
  connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres'
});

async function run() {
  await client.connect();
  const pubs = await client.query("SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime';");
  console.log('Realtime tables:', pubs.rows);

  const invs = await client.query("SELECT id, race_id, inviter_id, invitee_id, status, created_at FROM race_invitations ORDER BY created_at DESC LIMIT 5;");
  console.log('Recent invitations:', invs.rows);

  const races = await client.query("SELECT id, creator_id, status, mode, configuration, created_at FROM races ORDER BY created_at DESC LIMIT 5;");
  console.log('Recent races:', races.rows);

  const participants = await client.query("SELECT race_id, user_id, status, joined_at FROM race_participants ORDER BY joined_at DESC LIMIT 6;");
  console.log('Recent participants:', participants.rows);

  await client.end();
}

run().catch(console.error);
