const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres'
});
async function run() {
  await client.connect();
  const active = await client.query("SELECT id, creator_id, sport, mode, status, configuration, created_at FROM races WHERE status IN ('WAITING', 'READY_CHECK', 'IN_PROGRESS') ORDER BY created_at DESC;");
  console.log('Active races count:', active.rows.length);
  console.log(JSON.stringify(active.rows, null, 2));
  await client.end();
}
run().catch(console.error);
