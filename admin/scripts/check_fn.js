const { Client } = require('../node_modules/pg');
const DB = 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres';

async function test() {
  const client = new Client({ connectionString: DB });
  await client.connect();

  const fnTypes = await client.query(`
    SELECT proname, pg_get_function_result(oid) as ret, pg_get_function_arguments(oid) as args
    FROM pg_proc
    WHERE proname IN ('cancel_race', 'record_participant_finish', 'transition_race_state');
  `);
  console.table(fnTypes.rows);

  await client.end();
}

test().catch(console.error);

