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

  // 1. Add destination_race to enum if not present
  try {
    await client.query(`ALTER TYPE public.race_mode_type ADD VALUE IF NOT EXISTS 'destination_race';`);
    console.log('Added destination_race to enum!');
  } catch (e) {
    console.log('Enum note:', e.message);
  }

  // 2. View create_race_secure
  const res = await client.query(`
    SELECT routine_definition FROM information_schema.routines WHERE routine_name = 'create_race_secure';
  `);
  console.log('--- create_race_secure ---');
  console.log(res.rows[0]?.routine_definition);

  await client.end();
}
run().catch(console.error);
