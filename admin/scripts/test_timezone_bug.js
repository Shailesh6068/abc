const { Client } = require('../node_modules/pg');

const client = new Client({ connectionString: 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres' });

async function test() {
  await client.connect();

  // Test 1: with local-like string without Z (like Dart's DateTime.now().toIso8601String())
  // In IST, 12:30 PM local
  const badCutoff = '2026-11-12T12:30:00.000';
  const res1 = await client.query("SELECT COUNT(*) FROM races WHERE status = 'WAITING' AND created_at >= \$1;", [badCutoff]);
  console.log('Count with bad local cutoff (12:30):', res1.rows[0].count);

  // Test 2: with UTC string with Z
  const goodCutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  console.log('Good UTC cutoff:', goodCutoff);
  const res2 = await client.query("SELECT COUNT(*) FROM races WHERE status = 'WAITING' AND created_at >= \$1;", [goodCutoff]);
  console.log('Count with good UTC cutoff:', res2.rows[0].count);

  await client.end();
}

test().catch(console.error);

