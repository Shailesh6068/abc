import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getServiceClient, getUserClient } from '../_shared/supabaseClient.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const userClient = getUserClient(req);
    const { data: { user }, error: authError } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Verify admin role
    const serviceClient = getServiceClient();
    const { data: adminRole } = await serviceClient
      .from('admin_roles')
      .select('role')
      .eq('user_id', user.id)
      .in('role', ['super_admin', 'operations_admin', 'moderator'])
      .maybeSingle();

    if (!adminRole) {
      return new Response(JSON.stringify({ error: 'Forbidden: Insufficient privileges' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { action, race_id, reason, result_id, new_rank, new_validation_status } = await req.json();

    if (!race_id) {
      return new Response(JSON.stringify({ error: 'race_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (action === 'cancel_race') {
      if (!reason) {
        return new Response(JSON.stringify({ error: 'Cancellation reason is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      await serviceClient
        .from('races')
        .update({ status: 'CANCELLED' })
        .eq('id', race_id);

      await serviceClient.from('audit_events').insert({
        actor_id: user.id,
        event_type: 'ADMIN_RACE_CANCELLED',
        entity_type: 'races',
        entity_id: race_id,
        sanitized_metadata: { reason, admin_role: adminRole.role },
      });

      return new Response(JSON.stringify({ success: true, status: 'CANCELLED' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } else if (action === 'correct_result') {
      if (!result_id || !new_validation_status || !reason) {
        return new Response(JSON.stringify({ error: 'result_id, new_validation_status, and reason are required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const updatePayload: any = { validation_status: new_validation_status };
      if (new_rank) updatePayload.rank = new_rank;

      const { data: updatedResult, error: updErr } = await serviceClient
        .from('race_results')
        .update(updatePayload)
        .eq('id', result_id)
        .select()
        .single();

      if (updErr) {
        return new Response(JSON.stringify({ error: updErr.message }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      await serviceClient.from('audit_events').insert({
        actor_id: user.id,
        event_type: 'ADMIN_RESULT_CORRECTION',
        entity_type: 'race_results',
        entity_id: result_id,
        sanitized_metadata: { race_id, new_validation_status, new_rank, reason, admin_role: adminRole.role },
      });

      return new Response(JSON.stringify({ success: true, result: updatedResult }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Invalid action' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
