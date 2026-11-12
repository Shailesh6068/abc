const { createClient } = require('../node_modules/@supabase/supabase-js');
const { Client } = require('../node_modules/pg');

const pgClient = new Client({ connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres' });

async function test() {
  await pgClient.connect();
  // Get shadowhh email or auth info
  const users = await pgClient.query("SELECT id, email FROM auth.users WHERE id = 'f0242a4a-857c-49e6-829d-2ab8eb8f5071';");
  console.log('User:', users.rows[0]);

  // Test the select query directly via Postgres
  const pgRes = await pgClient.query("SELECT * FROM races WHERE status = 'WAITING';");
  console.log('PG WAITING races:', pgRes.rows);

  await pgClient.end();
}

test().catch(console.error);

