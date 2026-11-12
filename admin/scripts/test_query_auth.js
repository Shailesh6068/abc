const { createClient } = require('../node_modules/@supabase/supabase-js');

const serviceClient = createClient(
  'https://zifkhsscgjojtmzwbqio.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppZmtoc3NjZ2pvanRtendicWlvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MjIyNzI4MSwiZXhwIjoyMTA3ODAzMjgxfQ.JCB77L4lpGQau9jemQ5MEvj3HrZhx3qVJuSYiKCuvhE'
);

async function test() {
  // Test query with service client
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  const { data, error } = await serviceClient
    .from('races')
    .select('*, race_participants(*, profiles(display_name, avatar_url))')
    .eq('status', 'WAITING')
    .eq('visibility', 'public')
    .neq('mode', 'head_to_head')
    .gte('created_at', cutoff);

  console.log('Error:', error);
  console.log('Data count:', data?.length);
  if (data) console.log('Data sample:', JSON.stringify(data[0], null, 2));
}

test().catch(console.error);
