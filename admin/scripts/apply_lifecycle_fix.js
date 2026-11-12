const { Client } = require('../node_modules/pg');
const DB = 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres';
const fs = require('fs');
const path = require('path');

async function apply() {
  const client = new Client({ connectionString: DB });
  await client.connect();

  const sql = fs.readFileSync(
    path.join(__dirname, '../../supabase/migrations/20261112000002_fix_race_lifecycle_and_cancel.sql'),
    'utf8'
  );

  console.log('Applying race lifecycle and cancel fix migration...');
  try {
    await client.query(sql);
    console.log('Migration applied successfully.');
  } catch (e) {
    console.error('Migration error:', e.message);
  }

  // Check active races now
  const res = await client.query(`
    SELECT id, sport, mode, visibility, status, created_at, completed_at
    FROM races
    WHERE status IN ('WAITING', 'IN_PROGRESS', 'COUNTDOWN')
    ORDER BY created_at DESC;
  `);
  console.log('\n=== CURRENT ACTIVE RACES ===');
  console.table(res.rows);

  await client.end();
}

apply().catch(console.error);

