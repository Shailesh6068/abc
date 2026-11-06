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
    SELECT routine_definition FROM information_schema.routines WHERE routine_name = 'submit_gps_batch';
  `);
  console.log('--- submit_gps_batch ---');
  console.log(res.rows[0]?.routine_definition);

  await client.end();
}
run().catch(console.error);
