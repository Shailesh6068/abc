const { createClient } = require('../node_modules/@supabase/supabase-js');
const fs = require('fs');

const supabase = createClient(
  'https://zifkhsscgjojtmzwbqio.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppZmtoc3NjZ2pvanRtendicWlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIyMjcyODEsImV4cCI6MjEwNzgwMzI4MX0.J8018X2dah2-YBhRyqZDCr90uio1eCnMwybfk728nBI'
);

async function test() {
  // Sign in as anonymous or test user
  const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
  console.log('Auth user:', authData?.user?.id, authErr);

  const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  console.log('Cutoff:', cutoff);

  const { data, error } = await supabase
    .from('races')
    .select('*, race_participants(*, profiles(display_name, avatar_url))')
    .eq('status', 'WAITING')
    .eq('visibility', 'public')
    .neq('mode', 'head_to_head')
    .gte('created_at', cutoff);

  console.log('Error:', error);
  console.log('Data length:', data ? data.length : null);
  console.log('Data:', JSON.stringify(data, null, 2));
}

test().catch(console.error);

