const { Client } = require('../node_modules/pg');
const DB = 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres';
const fs = require('fs');
const path = require('path');

async function apply() {
  const client = new Client({ connectionString: DB });
  await client.connect();

  const sql = fs.readFileSync(
    path.join(__dirname, '../../supabase/migrations/20261112000001_fix_radar_discovery_bugs.sql'),
    'utf8'
  );

  console.log('Applying radar discovery fix migration...');
  try {
    await client.query(sql);
    console.log('Migration applied successfully.');
  } catch (e) {
    console.error('Migration error:', e.message);
  }

  // Verify results
  console.log('\n=== VERIFY: player_preferences after fix ===');
  const prefs = await client.query(`
    SELECT user_id, discovery_enabled FROM player_preferences ORDER BY user_id
  `);
  console.table(prefs.rows);

  console.log('\n=== VERIFY: player_presence after fix ===');
  const presence = await client.query(`
    SELECT pr.user_id, p.display_name, pr.selected_sport, pr.is_available, pref.discovery_enabled, pr.last_seen_at
    FROM player_presence pr
    JOIN profiles p ON p.id = pr.user_id
    LEFT JOIN player_preferences pref ON pref.user_id = pr.user_id
    ORDER BY pr.last_seen_at DESC
  `);
  console.table(presence.rows);

  await client.end();
}

apply().catch(console.error);

