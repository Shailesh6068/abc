const { Client } = require('../node_modules/pg');
const DB = 'postgresql://postgres.zifkhsscgjojtmzwbqio:Spdj60686068%40@aws-0-ap-northeast-1.pooler.supabase.com:6543/postgres';

async function check() {
  const client = new Client({ connectionString: DB });
  await client.connect();

  // Compute distances between all presence rows
  console.log('\n=== DISTANCES BETWEEN ALL PRESENCE ROWS ===');
  const dists = await client.query(`
    SELECT 
      a.user_id as user_a, pa.display_name as name_a,
      b.user_id as user_b, pb.display_name as name_b,
      ROUND(ST_Distance(a.location, b.location))::integer as distance_m,
      a.last_seen_at as a_last_seen,
      b.last_seen_at as b_last_seen
    FROM player_presence a
    JOIN player_presence b ON a.user_id < b.user_id
    JOIN profiles pa ON pa.id = a.user_id
    JOIN profiles pb ON pb.id = b.user_id
    ORDER BY distance_m
  `);
  console.table(dists.rows);

  // Check what shadowhh (the main device f0242a...) sees when querying nearby players
  // Simulate: who would shadowhh see?
  console.log('\n=== WHAT shadowhh (f0242a4a) WOULD SEE (SQL simulation) ===');
  const shadowhhId = 'f0242a4a-857c-49e6-829d-2ab8eb8f5071';
  const shadowhhPos = await client.query(`
    SELECT ST_Y(location::geometry) as lat, ST_X(location::geometry) as lng
    FROM player_presence WHERE user_id = $1
  `, [shadowhhId]);
  
  if (shadowhhPos.rows.length > 0) {
    const { lat, lng } = shadowhhPos.rows[0];
    console.log(`shadowhh is at lat=${lat}, lng=${lng}`);
    
    const nearby = await client.query(`
      SELECT 
        p.id AS user_id,
        p.display_name,
        ROUND(ST_Distance(pr.location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography))::integer AS approx_distance_m,
        pr.selected_sport,
        pr.is_available,
        pref.discovery_enabled,
        p.account_status,
        pr.last_seen_at,
        NOW() - pr.last_seen_at as age
      FROM player_presence pr
      JOIN profiles p ON p.id = pr.user_id
      LEFT JOIN player_preferences pref ON pref.user_id = pr.user_id
      WHERE pr.user_id <> $3
        AND ST_DWithin(pr.location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, 5000)
      ORDER BY approx_distance_m
    `, [lat, lng, shadowhhId]);
    console.table(nearby.rows);
  }

  // Check what hhhj (55f12265) sees
  console.log('\n=== WHAT hhhj (55f12265) WOULD SEE (SQL simulation) ===');
  const hhhjId = '55f12265-100d-4747-9a84-58f9440dcc1a';
  const hhhjPos = await client.query(`
    SELECT ST_Y(location::geometry) as lat, ST_X(location::geometry) as lng
    FROM player_presence WHERE user_id = $1
  `, [hhhjId]);
  
  if (hhhjPos.rows.length > 0) {
    const { lat, lng } = hhhjPos.rows[0];
    console.log(`hhhj is at lat=${lat}, lng=${lng}`);
    
    const nearby = await client.query(`
      SELECT 
        p.id AS user_id,
        p.display_name,
        ROUND(ST_Distance(pr.location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography))::integer AS approx_distance_m,
        pr.selected_sport,
        pr.is_available,
        pref.discovery_enabled,
        p.account_status,
        pr.last_seen_at,
        NOW() - pr.last_seen_at as age
      FROM player_presence pr
      JOIN profiles p ON p.id = pr.user_id
      LEFT JOIN player_preferences pref ON pref.user_id = pr.user_id
      WHERE pr.user_id <> $3
        AND ST_DWithin(pr.location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, 5000)
      ORDER BY approx_distance_m
    `, [lat, lng, hhhjId]);
    console.table(nearby.rows);
  }

  // KEY CHECK: Is shadowhh's discovery_enabled = false? That blocks them from appearing in other's radar
  console.log('\n=== CRITICAL: shadowhh discovery_enabled status ===');
  const shadowDiscovery = await client.query(`
    SELECT user_id, discovery_enabled FROM player_preferences WHERE user_id = 'f0242a4a-857c-49e6-829d-2ab8eb8f5071'
  `);
  console.table(shadowDiscovery.rows);
  console.log('NOTE: If discovery_enabled=false, shadowhh CANNOT be seen by others on radar!');

  await client.end();
}
check().catch(console.error);

