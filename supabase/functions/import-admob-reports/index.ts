import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getServiceClient } from '../_shared/supabaseClient.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Requires privileged secret or super_admin token
    const authHeader = req.headers.get('Authorization') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    // Verify authorized service role caller
    if (!authHeader.includes(serviceRoleKey)) {
      return new Response(JSON.stringify({ error: 'Forbidden: Service key required' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { report_date, reports } = await req.json();

    if (!report_date || !Array.isArray(reports)) {
      return new Response(JSON.stringify({ error: 'report_date and reports array required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const serviceClient = getServiceClient();
    let totalEstimatedEarningsUsd = 0;

    for (const item of reports) {
      const { platform, placement, impressions, clicks, estimated_earnings, ecpm, currency = 'USD' } = item;
      totalEstimatedEarningsUsd += Number(estimated_earnings || 0);

      // Upsert into ad_analytics_daily
      await serviceClient
        .from('ad_analytics_daily')
        .upsert(
          {
            report_date,
            platform,
            placement,
            impressions,
            clicks,
            estimated_earnings,
            currency,
            ecpm,
            source: 'admob_reporting_api',
            imported_at: new Date().toISOString(),
          },
          { onConflict: 'report_date,platform,placement,source' }
        );
    }

    // Convert estimated earnings to INR at approx exchange rate (e.g. 84.0) and record in revenue_records
    const amountInr = totalEstimatedEarningsUsd * 84.0;
    const refKey = `ADMOB-DAILY-${report_date}`;

    await serviceClient
      .from('revenue_records')
      .upsert(
        {
          source: 'admob',
          provider: 'Google AdMob',
          amount: amountInr,
          currency: 'INR',
          record_type: 'estimated',
          external_reference: refKey,
          recorded_at: new Date().toISOString(),
        },
        { onConflict: 'provider,external_reference' }
      );

    return new Response(JSON.stringify({
      success: true,
      report_date,
      records_imported: reports.length,
      estimated_inr: amountInr,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
