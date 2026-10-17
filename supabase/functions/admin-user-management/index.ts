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
      .in('role', ['super_admin', 'operations_admin', 'support_admin'])
      .maybeSingle();

    if (!adminRole) {
      return new Response(JSON.stringify({ error: 'Forbidden: Insufficient privileges' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { action, target_user_id, status_to_set, reason } = await req.json();

    if (action === 'update_status') {
      if (!target_user_id || !status_to_set || !reason) {
        return new Response(JSON.stringify({ error: 'target_user_id, status_to_set, and reason are required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const { data: updatedProfile, error: updateErr } = await serviceClient
        .from('profiles')
        .update({ account_status: status_to_set })
        .eq('id', target_user_id)
        .select()
        .single();

      if (updateErr) {
        return new Response(JSON.stringify({ error: updateErr.message }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      // Record immutable audit event
      await serviceClient.from('audit_events').insert({
        actor_id: user.id,
        event_type: 'USER_STATUS_CHANGE',
        entity_type: 'profiles',
        entity_id: target_user_id,
        sanitized_metadata: {
          previous_status: 'unknown',
          new_status: status_to_set,
          reason,
          admin_role: adminRole.role,
        },
      });

      return new Response(JSON.stringify({ success: true, profile: updatedProfile }), {
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
