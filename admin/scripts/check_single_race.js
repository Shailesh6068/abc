const { Client } = require('../node_modules/pg');
const client = new Client({ connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres' });
async function check() {
  await client.connect();
  const p = await client.query("SELECT * FROM race_participants WHERE race_id = '820f1d55-5292-46a2-883a-56c0f549f95e'");
  console.log('Participants:', p.rows);
  const r = await client.query("SELECT id, creator_id, visibility, status, sport, mode FROM races WHERE id = '820f1d55-5292-46a2-883a-56c0f549f95e'");
  console.log('Race:', r.rows);
  const profiles = await client.query("SELECT id, display_name FROM profiles");
  console.log('Profiles:', profiles.rows);
  await client.end();
}
check().catch(console.error);

