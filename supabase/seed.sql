-- ==============================================================================
-- RACEZONE SEED DATA
-- Default Achievements, System Configurations, Verified Routes & Sample Finance
-- ==============================================================================

-- 1. ACHIEVEMENTS
INSERT INTO public.achievements (id, name, description, criteria) VALUES
('first_race', 'First Steps', 'Completed your very first official GPS race', '{"races_completed": 1}'::jsonb),
('podium_finisher', 'Podium Finisher', 'Secured 1st place in an official race', '{"wins": 1}'::jsonb),
('veteran_racer', 'Pace Setter', 'Completed 10 official races across any sport', '{"races_completed": 10}'::jsonb),
('speed_demon', 'Speed Demon', 'Maintained exceptional pace with verified zero GPS flags', '{"verified_speed": true}'::jsonb),
('trail_blazer', 'Trail Blazer', 'Created and hosted 5 public community races', '{"races_hosted": 5}'::jsonb),
('century_cyclist', 'Century Cyclist', 'Accumulated 100km in verified cycling races', '{"cycling_distance_m": 100000}'::jsonb),
('apex_rider', 'Apex Rider', 'Completed a sanctioned closed-circuit motorbike time trial', '{"sport": "motorbike"}'::jsonb)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name, 
    description = EXCLUDED.description, 
    criteria = EXCLUDED.criteria;

-- 2. APP CONFIGURATION (7.19)
INSERT INTO public.app_configuration (key, value) VALUES
('discovery_settings', '{
    "min_radius_m": 100,
    "default_radius_m": 500,
    "max_radius_m": 5000,
    "location_stale_threshold_seconds": 600,
    "presence_cleanup_interval_minutes": 15
}'::jsonb),
('race_rules', '{
    "participant_limit_min": 2,
    "participant_limit_max": 20,
    "default_countdown_seconds": 10,
    "max_race_duration_seconds": 7200,
    "allowed_modes": ["time_trial", "distance_race", "head_to_head"],
    "allowed_sports": ["running", "cycling", "motorbike"]
}'::jsonb),
('gps_anti_cheat', '{
    "max_accuracy_m": 35.0,
    "speed_thresholds_mps": {
        "running": 12.5,
        "cycling": 30.0,
        "motorbike": 100.0
    },
    "max_teleport_distance_m": 150.0,
    "mock_location_rejection": true
}'::jsonb),
('advertising_settings', '{
    "enabled_placements": {
        "home_banner": true,
        "results_banner": true,
        "feed_native": false
    },
    "block_ads_during_active_race": true,
    "consent_framework": "UMP",
    "test_mode": true
}'::jsonb),
('system_status', '{
    "maintenance_mode": false,
    "announcement": null,
    "min_client_version": "1.0.0"
}'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 3. VERIFIED RACE ROUTES (7.4)
-- Running: 1 km Point-to-Point (e.g. Marina Promenade, Lat 13.0475, Lon 80.2825)
INSERT INTO public.race_routes (
    id,
    route_name,
    distance_m,
    course_type,
    start_point,
    finish_point,
    course
)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Marina Beach Sprint 1K',
    1000.00,
    'point_to_point',
    ST_SetSRID(ST_MakePoint(80.2825, 13.0475), 4326)::geography,
    ST_SetSRID(ST_MakePoint(80.2835, 13.0565), 4326)::geography,
    ST_SetSRID(ST_MakeLine(ST_MakePoint(80.2825, 13.0475), ST_MakePoint(80.2835, 13.0565)), 4326)
) ON CONFLICT (id) DO NOTHING;

-- Cycling: 5 km Boulevard Circuit
INSERT INTO public.race_routes (
    id,
    route_name,
    distance_m,
    course_type,
    start_point,
    finish_point,
    course
)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    'Coastal Highway 5K Loop',
    5000.00,
    'circuit',
    ST_SetSRID(ST_MakePoint(80.2500, 13.0000), 4326)::geography,
    ST_SetSRID(ST_MakePoint(80.2500, 13.0000), 4326)::geography,
    ST_SetSRID(ST_MakeLine(ARRAY[
        ST_MakePoint(80.2500, 13.0000),
        ST_MakePoint(80.2600, 13.0100),
        ST_MakePoint(80.2550, 13.0200),
        ST_MakePoint(80.2450, 13.0100),
        ST_MakePoint(80.2500, 13.0000)
    ]), 4326)
) ON CONFLICT (id) DO NOTHING;

-- Motorbike: 3.2 km Closed Speedway Track (Strictly controlled, non-public road)
INSERT INTO public.race_routes (
    id,
    route_name,
    distance_m,
    course_type,
    start_point,
    finish_point,
    course
)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    'Apex International Speedway - Outer Loop (Closed Track)',
    3200.00,
    'circuit',
    ST_SetSRID(ST_MakePoint(79.9800, 12.9200), 4326)::geography,
    ST_SetSRID(ST_MakePoint(79.9800, 12.9200), 4326)::geography,
    ST_SetSRID(ST_MakeLine(ARRAY[
        ST_MakePoint(79.9800, 12.9200),
        ST_MakePoint(79.9880, 12.9250),
        ST_MakePoint(79.9920, 12.9180),
        ST_MakePoint(79.9830, 12.9120),
        ST_MakePoint(79.9800, 12.9200)
    ]), 4326)
) ON CONFLICT (id) DO NOTHING;

-- 4. OPERATING EXPENSES SAMPLE (7.15, INR initial reporting currency)
INSERT INTO public.operating_expenses (category, description, amount, currency, expense_date, vendor, payment_status, recurring) VALUES
('Supabase and backend hosting', 'Supabase Pro Tier database & compute clusters', 2200.00, 'INR', CURRENT_DATE - INTERVAL '15 days', 'Supabase Inc', 'paid', true),
('Maps API', 'Google Maps Platform Geocoding & Tiles quota', 1450.00, 'INR', CURRENT_DATE - INTERVAL '10 days', 'Google Cloud India', 'paid', false),
('Storage and networking', 'Cloud storage & CDN egress for avatars and assets', 680.00, 'INR', CURRENT_DATE - INTERVAL '8 days', 'Cloudflare', 'paid', true),
('Apple and Google developer accounts', 'Annual Developer Program licenses allocation', 1850.00, 'INR', CURRENT_DATE - INTERVAL '25 days', 'Apple / Google', 'paid', false),
('Software subscriptions', 'Monitoring and log aggregator tools', 920.00, 'INR', CURRENT_DATE - INTERVAL '5 days', 'Datadog', 'paid', true)
ON CONFLICT DO NOTHING;

-- 5. REVENUE RECORDS SAMPLE (7.16)
INSERT INTO public.revenue_records (source, provider, amount, currency, record_type, external_reference, recorded_at) VALUES
('admob', 'Google AdMob', 3800.00, 'INR', 'recognized', 'ADMOB-SETTLEMENT-2026-09', NOW() - INTERVAL '12 days'),
('admob', 'Google AdMob', 1250.00, 'INR', 'estimated', 'ADMOB-EST-2026-10-W1', NOW() - INTERVAL '4 days'),
('admob', 'Google AdMob', 1650.00, 'INR', 'estimated', 'ADMOB-EST-2026-10-W2', NOW() - INTERVAL '1 days')
ON CONFLICT (provider, external_reference) DO NOTHING;

-- 6. AD ANALYTICS DAILY SAMPLE (7.17)
INSERT INTO public.ad_analytics_daily (report_date, platform, placement, impressions, clicks, estimated_earnings, currency, ecpm) VALUES
(CURRENT_DATE - INTERVAL '3 days', 'android', 'home_banner', 1420, 48, 12.45, 'USD', 8.76),
(CURRENT_DATE - INTERVAL '3 days', 'ios', 'home_banner', 980, 31, 10.80, 'USD', 11.02),
(CURRENT_DATE - INTERVAL '2 days', 'android', 'home_banner', 1650, 52, 14.10, 'USD', 8.54),
(CURRENT_DATE - INTERVAL '2 days', 'ios', 'home_banner', 1120, 39, 13.50, 'USD', 12.05),
(CURRENT_DATE - INTERVAL '1 days', 'android', 'results_banner', 840, 29, 9.20, 'USD', 10.95),
(CURRENT_DATE - INTERVAL '1 days', 'ios', 'results_banner', 630, 24, 8.40, 'USD', 13.33)
ON CONFLICT (report_date, platform, placement, source) DO NOTHING;
