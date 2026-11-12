const { Client } = require('../node_modules/pg');

const DB = 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres';

async function check() {
  const client = new Client({ connectionString: DB });
  await client.connect();

  console.log('\n=== ALL PLAYER PRESENCE (with profile join) ===');
  const presence = await client.query(`
    SELECT pr.user_id, p.display_name, p.account_status,
           pr.selected_sport, pr.is_available, pr.last_seen_at,
           pref.discovery_enabled,
           ST_Y(pr.location::geometry) as lat,
           ST_X(pr.location::geometry) as lng,
           NOW() - pr.last_seen_at as age
    FROM player_presence pr
    LEFT JOIN profiles p ON p.id = pr.user_id
    LEFT JOIN player_preferences pref ON pref.user_id = pr.user_id
    ORDER BY pr.last_seen_at DESC
    LIMIT 20
  `);
  console.table(presence.rows);

  console.log('\n=== DUPLICATE USER IDs IN PRESENCE ===');
  const dups = await client.query(`
    SELECT user_id, COUNT(*) as cnt
    FROM player_presence
    GROUP BY user_id
    HAVING COUNT(*) > 1
  `);
  console.table(dups.rows);

  console.log('\n=== PROFILES WITH MATCHING DISPLAY NAMES (possible self-ghosting) ===');
  const dupNames = await client.query(`
    SELECT display_name, COUNT(*) as cnt, array_agg(id) as user_ids
    FROM profiles
    WHERE display_name IS NOT NULL
    GROUP BY display_name
    HAVING COUNT(*) > 1
    LIMIT 20
  `);
  console.table(dupNames.rows);

  console.log('\n=== ALL PROFILES ===');
  const profiles = await client.query(`
    SELECT id, display_name, account_status, created_at
    FROM profiles
    ORDER BY created_at DESC
    LIMIT 20
  `);
  console.table(profiles.rows);

  console.log('\n=== PLAYER PREFERENCES ===');
  const prefs = await client.query(`
    SELECT user_id, discovery_enabled
    FROM player_preferences
    LIMIT 20
  `);
  console.table(prefs.rows);

  console.log('\n=== ACTIVE SESSIONS / AUTH USERS ===');
  const authUsers = await client.query(`
    SELECT au.id, au.email, au.raw_user_meta_data->>'display_name' as display_name,
           au.created_at, au.last_sign_in_at
    FROM auth.users au
    ORDER BY au.last_sign_in_at DESC NULLS LAST
    LIMIT 20
  `);
  console.table(authUsers.rows);

  await client.end();
}

check().catch(console.error);
