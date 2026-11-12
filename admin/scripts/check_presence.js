const { Client } = require('../node_modules/pg');
const client = new Client({ connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres' });
async function check() {
  await client.connect();
  const res = await client.query("SELECT * FROM player_presence LIMIT 5;");
  console.log('Player presence sample:', res.rows);
  await client.end();
}
check().catch(console.error);
