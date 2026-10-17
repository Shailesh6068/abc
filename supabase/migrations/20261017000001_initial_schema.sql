-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: INITIAL SCHEMA
-- Tables 7.1 to 7.19 with PostGIS, Spatial Indexes, Constraints & Triggers
-- ==============================================================================

-- 1. Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. ENUM TYPES
DO $$ BEGIN
    CREATE TYPE account_status_type AS ENUM ('active', 'suspended', 'deactivated', 'pending_verification');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE sport_type AS ENUM ('running', 'cycling', 'motorbike');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE race_mode_type AS ENUM ('time_trial', 'distance_race', 'head_to_head');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE race_visibility_type AS ENUM ('public', 'invitation_only');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE race_status_type AS ENUM (
        'WAITING',
        'READY_CHECK',
        'COUNTDOWN',
        'IN_PROGRESS',
        'FINISHING',
        'COMPLETED',
        'CANCELLED',
        'ABORTED'
    );
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE participant_status_type AS ENUM (
        'joined',
        'ready',
        'racing',
        'finished',
        'dnf',
        'disqualified'
    );
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE invitation_status_type AS ENUM ('pending', 'accepted', 'declined', 'expired');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE validation_status_type AS ENUM ('valid', 'flagged_review', 'disqualified');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE admin_role_type AS ENUM (
        'super_admin',
        'operations_admin',
        'support_admin',
        'finance_viewer',
        'moderator'
    );
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE moderation_status_type AS ENUM ('OPEN', 'UNDER_REVIEW', 'RESOLVED', 'DISMISSED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- Generic update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------------------
-- 7.1 profiles
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    account_status account_status_type NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER update_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 7.2 player_preferences
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.player_preferences (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    preferred_sports sport_type[] NOT NULL DEFAULT ARRAY['running']::sport_type[],
    discovery_enabled BOOLEAN NOT NULL DEFAULT true,
    preferred_radius_m INTEGER NOT NULL DEFAULT 500 CHECK (preferred_radius_m BETWEEN 50 AND 5000),
    privacy_settings JSONB NOT NULL DEFAULT '{"hide_exact_location": true, "allow_race_invites_from": "everyone"}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER update_player_preferences_updated_at
BEFORE UPDATE ON public.player_preferences
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 7.3 player_presence (Temporary location data, automatically expired)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.player_presence (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    selected_sport sport_type NOT NULL DEFAULT 'running',
    is_available BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    location_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_presence_location_gist 
ON public.player_presence USING GIST (location);

CREATE INDEX IF NOT EXISTS idx_player_presence_availability 
ON public.player_presence (is_available, selected_sport, last_seen_at);

-- ------------------------------------------------------------------------------
-- 7.4 race_routes
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    route_name TEXT NOT NULL,
    course GEOMETRY(LineString, 4326),
    distance_m NUMERIC(10, 2) NOT NULL CHECK (distance_m > 0),
    start_point GEOGRAPHY(Point, 4326) NOT NULL,
    finish_point GEOGRAPHY(Point, 4326) NOT NULL,
    course_type TEXT NOT NULL DEFAULT 'point_to_point', -- point_to_point, circuit, open_track
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_race_routes_start_gist 
ON public.race_routes USING GIST (start_point);

-- ------------------------------------------------------------------------------
-- 7.5 races
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.races (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    sport sport_type NOT NULL,
    mode race_mode_type NOT NULL,
    visibility race_visibility_type NOT NULL DEFAULT 'public',
    status race_status_type NOT NULL DEFAULT 'WAITING',
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    route_id UUID REFERENCES public.race_routes(id) ON DELETE SET NULL,
    participant_limit INTEGER NOT NULL DEFAULT 4 CHECK (participant_limit BETWEEN 2 AND 20),
    scheduled_start_at TIMESTAMPTZ,
    actual_start_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_races_status_start 
ON public.races (status, scheduled_start_at);

CREATE INDEX IF NOT EXISTS idx_races_creator 
ON public.races (creator_id);

CREATE TRIGGER update_races_updated_at
BEFORE UPDATE ON public.races
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 7.6 race_participants
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_participants (
    race_id UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status participant_status_type NOT NULL DEFAULT 'joined',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ready_at TIMESTAMPTZ,
    finish_time_ms BIGINT,
    validated_distance_m NUMERIC(10, 2) DEFAULT 0,
    disqualification_reason TEXT,
    PRIMARY KEY (race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_participants_user 
ON public.race_participants (user_id, status);

-- ------------------------------------------------------------------------------
-- 7.7 race_invitations
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_invitations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    race_id UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    invitee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status invitation_status_type NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '10 minutes')
);

CREATE INDEX IF NOT EXISTS idx_race_invitations_invitee 
ON public.race_invitations (invitee_id, status);

-- ------------------------------------------------------------------------------
-- 7.8 gps_samples (Immutable time-series GPS stream with strict validation)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gps_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    race_id UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    sequence_no INTEGER NOT NULL CHECK (sequence_no >= 0),
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    accuracy_m DOUBLE PRECISION NOT NULL CHECK (accuracy_m >= 0),
    altitude_m DOUBLE PRECISION,
    speed_mps DOUBLE PRECISION,
    heading_deg DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_gps_sample_sequence UNIQUE (race_id, user_id, sequence_no)
);

CREATE INDEX IF NOT EXISTS idx_gps_samples_lookup 
ON public.gps_samples (race_id, user_id, sequence_no);

CREATE INDEX IF NOT EXISTS idx_gps_samples_recorded_at 
ON public.gps_samples (race_id, recorded_at);

-- ------------------------------------------------------------------------------
-- 7.9 race_results
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    race_id UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rank INTEGER NOT NULL CHECK (rank >= 1),
    verified_distance_m NUMERIC(10, 2) NOT NULL DEFAULT 0,
    elapsed_ms BIGINT NOT NULL CHECK (elapsed_ms >= 0),
    validation_status validation_status_type NOT NULL DEFAULT 'valid',
    validation_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    finalized_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_race_results_user UNIQUE (race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_results_user 
ON public.race_results (user_id, finalized_at);

-- ------------------------------------------------------------------------------
-- 7.10 leaderboard_entries
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.leaderboard_entries (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    sport sport_type NOT NULL,
    rating INTEGER NOT NULL DEFAULT 1200 CHECK (rating >= 0),
    xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
    races_completed INTEGER NOT NULL DEFAULT 0 CHECK (races_completed >= 0),
    wins INTEGER NOT NULL DEFAULT 0 CHECK (wins >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, sport)
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_sorting 
ON public.leaderboard_entries (sport, rating DESC, xp DESC);

-- ------------------------------------------------------------------------------
-- 7.11 achievements
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.achievements (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    criteria JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- ------------------------------------------------------------------------------
-- 7.12 user_achievements
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_achievements (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    achievement_id TEXT NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
    earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, achievement_id)
);

-- ------------------------------------------------------------------------------
-- 7.13 audit_events (Protected ledger of critical admin/system actions)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    sanitized_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_events_created 
ON public.audit_events (created_at DESC);

-- ------------------------------------------------------------------------------
-- 7.14 admin_roles
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_roles (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role admin_role_type NOT NULL,
    granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role)
);

-- ------------------------------------------------------------------------------
-- 7.15 operating_expenses
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.operating_expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'INR',
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    vendor TEXT NOT NULL,
    payment_status TEXT NOT NULL DEFAULT 'paid', -- pending, paid, cancelled
    recurring BOOLEAN NOT NULL DEFAULT false,
    receipt_file_path TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_operating_expenses_date 
ON public.operating_expenses (expense_date DESC);

CREATE TRIGGER update_operating_expenses_updated_at
BEFORE UPDATE ON public.operating_expenses
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 7.16 revenue_records
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.revenue_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source TEXT NOT NULL, -- admob, sponsorship, merchandise
    provider TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'INR',
    record_type TEXT NOT NULL DEFAULT 'recognized', -- estimated, accrued, recognized
    external_reference TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_revenue_external UNIQUE (provider, external_reference)
);

CREATE INDEX IF NOT EXISTS idx_revenue_records_date 
ON public.revenue_records (recorded_at DESC);

-- ------------------------------------------------------------------------------
-- 7.17 ad_analytics_daily
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ad_analytics_daily (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_date DATE NOT NULL,
    platform TEXT NOT NULL, -- android, ios
    placement TEXT NOT NULL, -- home_banner, results_banner, feed_native
    impressions INTEGER NOT NULL DEFAULT 0 CHECK (impressions >= 0),
    clicks INTEGER NOT NULL DEFAULT 0 CHECK (clicks >= 0),
    estimated_earnings NUMERIC(10, 4) NOT NULL DEFAULT 0 CHECK (estimated_earnings >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    ecpm NUMERIC(10, 4) NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'admob_reporting_api',
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_ad_analytics_daily UNIQUE (report_date, platform, placement, source)
);

CREATE INDEX IF NOT EXISTS idx_ad_analytics_date 
ON public.ad_analytics_daily (report_date DESC);

-- ------------------------------------------------------------------------------
-- 7.18 moderation_reports
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.moderation_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    race_id UUID REFERENCES public.races(id) ON DELETE SET NULL,
    category TEXT NOT NULL, -- abuse, harassment, fake_account, gps_cheating, unsafe_racing, inappropriate_content
    description TEXT NOT NULL,
    status moderation_status_type NOT NULL DEFAULT 'OPEN',
    assigned_moderator_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    resolution TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moderation_reports_status 
ON public.moderation_reports (status, created_at DESC);

CREATE TRIGGER update_moderation_reports_updated_at
BEFORE UPDATE ON public.moderation_reports
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------
-- 7.19 app_configuration
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_configuration (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User auto-creation trigger from auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, avatar_url, account_status)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', 'Racer_' || SUBSTRING(NEW.id::text, 1, 6)),
        NEW.raw_user_meta_data->>'avatar_url',
        'active'
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.player_preferences (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.leaderboard_entries (user_id, sport, rating, xp)
    VALUES 
        (NEW.id, 'running', 1200, 0),
        (NEW.id, 'cycling', 1200, 0),
        (NEW.id, 'motorbike', 1200, 0)
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
