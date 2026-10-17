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

    // Verify finance permission
    const serviceClient = getServiceClient();
    const { data: adminRole } = await serviceClient
      .from('admin_roles')
      .select('role')
      .eq('user_id', user.id)
      .in('role', ['super_admin', 'operations_admin', 'finance_viewer'])
      .maybeSingle();

    if (!adminRole) {
      return new Response(JSON.stringify({ error: 'Forbidden: Insufficient privileges' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { action, startDate, endDate, expenseData } = await req.json();

    if (action === 'summary') {
      let expenseQuery = serviceClient.from('operating_expenses').select('amount, currency, category, payment_status, expense_date');
      let revenueQuery = serviceClient.from('revenue_records').select('amount, currency, source, record_type, recorded_at');

      if (startDate) {
        expenseQuery = expenseQuery.gte('expense_date', startDate);
        revenueQuery = revenueQuery.gte('recorded_at', startDate);
      }
      if (endDate) {
        expenseQuery = expenseQuery.lte('expense_date', endDate);
        revenueQuery = revenueQuery.lte('recorded_at', endDate);
      }

      const [{ data: expenses }, { data: revenues }] = await Promise.all([
        expenseQuery,
        revenueQuery,
      ]);

      const totalExpenses = (expenses ?? []).reduce((acc, curr) => acc + Number(curr.amount || 0), 0);
      const totalRevenue = (revenues ?? []).reduce((acc, curr) => acc + Number(curr.amount || 0), 0);
      const operatingResult = totalRevenue - totalExpenses;

      const categoryBreakdown: Record<string, number> = {};
      (expenses ?? []).forEach(e => {
        categoryBreakdown[e.category] = (categoryBreakdown[e.category] || 0) + Number(e.amount || 0);
      });

      return new Response(JSON.stringify({
        recordedRevenue: totalRevenue,
        recordedOperatingExpenses: totalExpenses,
        operatingResult,
        currency: 'INR',
        categoryBreakdown,
        expenseCount: expenses?.length ?? 0,
        revenueCount: revenues?.length ?? 0,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } else if (action === 'add_expense') {
      const { category, description, amount, currency = 'INR', expense_date, vendor, payment_status = 'paid', recurring = false } = expenseData;

      if (!category || !description || !amount || !vendor) {
        return new Response(JSON.stringify({ error: 'Missing required expense fields' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const { data: newExpense, error: expErr } = await serviceClient
        .from('operating_expenses')
        .insert({
          category,
          description,
          amount,
          currency,
          expense_date: expense_date || new Date().toISOString().split('T')[0],
          vendor,
          payment_status,
          recurring,
          created_by: user.id,
        })
        .select()
        .single();

      if (expErr) {
        return new Response(JSON.stringify({ error: expErr.message }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      await serviceClient.from('audit_events').insert({
        actor_id: user.id,
        event_type: 'EXPENSE_ADDED',
        entity_type: 'operating_expenses',
        entity_id: newExpense.id,
        sanitized_metadata: { category, amount, currency, vendor },
      });

      return new Response(JSON.stringify({ success: true, expense: newExpense }), {
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
