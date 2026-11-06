const { Client } = require('pg');

async function test() {
  const client = new Client({
    host: 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: 6543,
    user: 'postgres.zifkhsscgjojtmzwbqio',
    password: 'Spdj60686068@',
    database: 'postgres',
    ssl: { rejectUnauthorized: false }
  });
  await client.connect();

  const races = await client.query(`
    SELECT id, status, creator_id, configuration->>'course_name' as course_name, created_at 
    FROM public.races 
    ORDER BY created_at DESC 
    LIMIT 6;
  `);
  console.log('Recent races in DB:', races.rows);

  await client.end();
}
test().catch(console.error);
