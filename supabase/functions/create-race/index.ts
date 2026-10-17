import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getUserClient } from '../_shared/supabaseClient.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getUserClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { sport, mode, visibility = 'public', participant_limit = 4, route_id = null, configuration = {} } = await req.json();

    if (!['running', 'cycling', 'motorbike'].includes(sport)) {
      return new Response(JSON.stringify({ error: 'Invalid sport' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!['time_trial', 'distance_race', 'head_to_head'].includes(mode)) {
      return new Response(JSON.stringify({ error: 'Invalid race mode' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: raceId, error } = await supabase.rpc('create_race_secure', {
      p_sport: sport,
      p_mode: mode,
      p_visibility: visibility,
      p_participant_limit: participant_limit,
      p_route_id: route_id,
      p_configuration: configuration,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ race_id: raceId }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
