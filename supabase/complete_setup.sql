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
-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: ROW LEVEL SECURITY POLICIES
-- Complete security and permission isolation
-- ==============================================================================

-- 1. Helper Function: Check Admin Role
CREATE OR REPLACE FUNCTION public.has_admin_role(VARIADIC allowed_roles admin_role_type[])
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM public.admin_roles 
        WHERE user_id = auth.uid() 
          AND role = ANY(allowed_roles)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 2. ENABLE RLS ON ALL TABLES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.races ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gps_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leaderboard_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operating_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revenue_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_analytics_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moderation_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_configuration ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- 7.1 profiles RLS
-- ------------------------------------------------------------------------------
-- Anyone authenticated can view profiles
CREATE POLICY "Profiles are viewable by authenticated users"
ON public.profiles FOR SELECT
TO authenticated
USING (true);

-- Users can only update their own display_name and avatar_url
-- Account status can only be modified by admins
CREATE POLICY "Users can update their own basic profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
    auth.uid() = id AND
    account_status = (SELECT p.account_status FROM public.profiles p WHERE p.id = auth.uid())
);

-- Admin update policy
CREATE POLICY "Admins can update any profile"
ON public.profiles FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'support_admin'));

-- ------------------------------------------------------------------------------
-- 7.2 player_preferences RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Users can manage their own preferences"
ON public.player_preferences FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ------------------------------------------------------------------------------
-- 7.3 player_presence RLS
-- ------------------------------------------------------------------------------
-- Users can only insert/update/delete their own presence
CREATE POLICY "Users manage own presence"
ON public.player_presence FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Direct SELECT is restricted; nearby matchmaking is accessed via secure RPC function
CREATE POLICY "Admins can view presence"
ON public.player_presence FOR SELECT
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin'));

-- ------------------------------------------------------------------------------
-- 7.4 race_routes RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Race routes are viewable by authenticated users"
ON public.race_routes FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Authenticated users can create routes"
ON public.race_routes FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = creator_id);

CREATE POLICY "Creators or admins can update routes"
ON public.race_routes FOR UPDATE
TO authenticated
USING (auth.uid() = creator_id OR public.has_admin_role('super_admin', 'operations_admin'));

-- ------------------------------------------------------------------------------
-- 7.5 races RLS
-- ------------------------------------------------------------------------------
-- Public races visible to everyone; private visible to participants or invited users
CREATE POLICY "View races policy"
ON public.races FOR SELECT
TO authenticated
USING (
    visibility = 'public' 
    OR creator_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.race_participants 
        WHERE race_id = public.races.id AND user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM public.race_invitations 
        WHERE race_id = public.races.id AND invitee_id = auth.uid()
    )
    OR public.has_admin_role('super_admin', 'operations_admin', 'support_admin', 'moderator')
);

-- Users can create races with creator_id = auth.uid()
CREATE POLICY "Users can create races"
ON public.races FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = creator_id AND status = 'WAITING');

-- Updates must go through trusted RPC, but creator can cancel before start
CREATE POLICY "Creators can cancel waiting race"
ON public.races FOR UPDATE
TO authenticated
USING (
    (auth.uid() = creator_id AND status IN ('WAITING', 'READY_CHECK'))
    OR public.has_admin_role('super_admin', 'operations_admin')
);

-- ------------------------------------------------------------------------------
-- 7.6 race_participants RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Participants viewable by race viewers"
ON public.race_participants FOR SELECT
TO authenticated
USING (true);

-- Joining and readiness are handled via RPC, but user can self-leave while WAITING
CREATE POLICY "Users can leave waiting race"
ON public.race_participants FOR DELETE
TO authenticated
USING (
    auth.uid() = user_id 
    AND EXISTS (
        SELECT 1 FROM public.races 
        WHERE id = public.race_participants.race_id 
          AND status IN ('WAITING', 'READY_CHECK')
    )
);

-- ------------------------------------------------------------------------------
-- 7.7 race_invitations RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Invitations viewable by inviter or invitee"
ON public.race_invitations FOR SELECT
TO authenticated
USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);

CREATE POLICY "Inviters can send invitations"
ON public.race_invitations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = inviter_id);

CREATE POLICY "Invitee can update status"
ON public.race_invitations FOR UPDATE
TO authenticated
USING (auth.uid() = invitee_id)
WITH CHECK (auth.uid() = invitee_id);

-- ------------------------------------------------------------------------------
-- 7.8 gps_samples RLS
-- ------------------------------------------------------------------------------
-- Samples can only be inserted by the participant for an IN_PROGRESS race
CREATE POLICY "Users can insert own samples during race"
ON public.gps_samples FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.race_participants rp
        JOIN public.races r ON r.id = rp.race_id
        WHERE rp.race_id = public.gps_samples.race_id 
          AND rp.user_id = auth.uid()
          AND r.status = 'IN_PROGRESS'
    )
);

-- Samples are readable by participants of that race and admins (for live map and review)
CREATE POLICY "Race participants can view race samples"
ON public.gps_samples FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.race_participants 
        WHERE race_id = public.gps_samples.race_id AND user_id = auth.uid()
    )
    OR public.has_admin_role('super_admin', 'operations_admin', 'moderator')
);

-- ------------------------------------------------------------------------------
-- 7.9 race_results RLS
-- ------------------------------------------------------------------------------
-- Results are public to authenticated users
CREATE POLICY "Race results viewable by authenticated users"
ON public.race_results FOR SELECT
TO authenticated
USING (true);

-- Results can ONLY be inserted or updated by server functions or super_admin
CREATE POLICY "Admins can manage race results"
ON public.race_results FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin'));

-- ------------------------------------------------------------------------------
-- 7.10 leaderboard_entries RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Leaderboards are publicly viewable"
ON public.leaderboard_entries FOR SELECT
TO authenticated
USING (true);

-- Updates exclusively restricted to backend RPC and super admins
CREATE POLICY "Admins manage leaderboards"
ON public.leaderboard_entries FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin'));

-- ------------------------------------------------------------------------------
-- 7.11 achievements & 7.12 user_achievements RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Achievements viewable by all"
ON public.achievements FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "User achievements viewable by all"
ON public.user_achievements FOR SELECT
TO authenticated
USING (true);

-- ------------------------------------------------------------------------------
-- 7.13 audit_events RLS
-- ------------------------------------------------------------------------------
-- Ordinary users CANNOT read or alter audit events
CREATE POLICY "Audit events readable only by authorized admins"
ON public.audit_events FOR SELECT
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'support_admin'));

-- ------------------------------------------------------------------------------
-- 7.14 admin_roles RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Admin roles readable by current user or super admin"
ON public.admin_roles FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR public.has_admin_role('super_admin'));

CREATE POLICY "Super admin can modify admin roles"
ON public.admin_roles FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin'));

-- ------------------------------------------------------------------------------
-- 7.15 operating_expenses RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Expenses readable by finance staff and super admin"
ON public.operating_expenses FOR SELECT
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'finance_viewer'));

CREATE POLICY "Expenses editable by finance and super admin"
ON public.operating_expenses FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin', 'finance_viewer'));

-- ------------------------------------------------------------------------------
-- 7.16 revenue_records RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Revenue readable by finance and super admin"
ON public.revenue_records FOR SELECT
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'finance_viewer'));

CREATE POLICY "Revenue editable by super admin"
ON public.revenue_records FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin'));

-- ------------------------------------------------------------------------------
-- 7.17 ad_analytics_daily RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Ad analytics readable by authorized admin and finance"
ON public.ad_analytics_daily FOR SELECT
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'finance_viewer'));

CREATE POLICY "Ad analytics manageable by super admin"
ON public.ad_analytics_daily FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin'));

-- ------------------------------------------------------------------------------
-- 7.18 moderation_reports RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Users can create reports"
ON public.moderation_reports FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "Reporters can view their submitted reports"
ON public.moderation_reports FOR SELECT
TO authenticated
USING (
    auth.uid() = reporter_id 
    OR public.has_admin_role('super_admin', 'operations_admin', 'support_admin', 'moderator')
);

CREATE POLICY "Moderators can update reports"
ON public.moderation_reports FOR UPDATE
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin', 'moderator'));

-- ------------------------------------------------------------------------------
-- 7.19 app_configuration RLS
-- ------------------------------------------------------------------------------
CREATE POLICY "Configuration readable by authenticated users"
ON public.app_configuration FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Configuration editable only by super admin"
ON public.app_configuration FOR ALL
TO authenticated
USING (public.has_admin_role('super_admin', 'operations_admin'));
-- ==============================================================================
-- RACEZONE DATABASE MIGRATION: FUNCTIONS, PROCEDURES AND RPC
-- Server-authoritative logic for matchmaking, race lifecycle, GPS anti-cheat,
-- result finalization, and audit ledger.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CLEANUP STALE PRESENCE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_stale_presence()
RETURNS void AS $$
BEGIN
    DELETE FROM public.player_presence
    WHERE last_seen_at < (NOW() - INTERVAL '15 minutes');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 2. UPDATE PLAYER PRESENCE (Heartbeat & Location)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_player_presence(
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_sport sport_type DEFAULT 'running',
    p_is_available BOOLEAN DEFAULT true
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_latitude < -90 OR p_latitude > 90 OR p_longitude < -180 OR p_longitude > 180 THEN
        RAISE EXCEPTION 'Invalid coordinates provided';
    END IF;

    -- Ensure profile exists and account is active so user appears in discovery
    INSERT INTO public.profiles (id, display_name, account_status)
    VALUES (
        v_user_id,
        'Racer_' || SUBSTRING(v_user_id::text, 1, 6),
        'active'
    ) ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    -- Ensure player_preferences exists with discovery_enabled = true
    INSERT INTO public.player_preferences (user_id, discovery_enabled)
    VALUES (v_user_id, true)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.player_presence (
        user_id,
        location,
        selected_sport,
        is_available,
        last_seen_at,
        location_updated_at
    )
    VALUES (
        v_user_id,
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
        COALESCE(p_sport, 'running'::sport_type),
        p_is_available,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        location = EXCLUDED.location,
        selected_sport = EXCLUDED.selected_sport,
        is_available = EXCLUDED.is_available,
        last_seen_at = NOW(),
        location_updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 3. NEARBY MATCHMAKING (Section 9: ST_DWithin with Privacy Fuzzing)
-- Never returns raw coordinates; fuzzes distance to prevent triangulation
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_nearby_players(
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_radius_m INTEGER DEFAULT 1000,
    p_sport sport_type DEFAULT NULL,
    p_limit INTEGER DEFAULT 30
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    approx_distance_m INTEGER,
    sport sport_type,
    is_available BOOLEAN,
    rating INTEGER
) AS $$
DECLARE
    v_origin GEOGRAPHY;
    v_max_radius INTEGER := 50000; -- Support up to 50km for cycling, motorbike and regional matchmaking
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Validate radius bound
    p_radius_m := LEAST(GREATEST(p_radius_m, 50), v_max_radius);
    v_origin := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;

    -- Clean stale records (30 minutes)
    DELETE FROM public.player_presence
    WHERE last_seen_at < (NOW() - INTERVAL '30 minutes');

    RETURN QUERY
    SELECT 
        p.id AS user_id,
        COALESCE(p.display_name, 'Racer_' || SUBSTRING(p.id::text, 1, 6)) AS display_name,
        p.avatar_url,
        -- Round distance to nearest 25 meters (minimum 10m to prevent 0m display when adjacent)
        GREATEST(10, (ROUND(ST_Distance(pr.location, v_origin) / 25.0) * 25)::INTEGER) AS approx_distance_m,
        pr.selected_sport AS sport,
        COALESCE(pr.is_available, true) AS is_available,
        COALESCE(le.rating, 1200) AS rating
    FROM public.player_presence pr
    JOIN public.profiles p ON p.id = pr.user_id
    LEFT JOIN public.player_preferences pref ON pref.user_id = pr.user_id
    LEFT JOIN public.leaderboard_entries le ON le.user_id = pr.user_id AND le.sport = pr.selected_sport
    WHERE pr.user_id <> auth.uid()
      AND COALESCE(pr.is_available, true) = true
      AND COALESCE(pref.discovery_enabled, true) = true
      AND COALESCE(p.account_status, 'active') = 'active'
      AND (p_sport IS NULL OR pr.selected_sport = p_sport)
      AND ST_DWithin(pr.location, v_origin, p_radius_m)
      AND pr.last_seen_at >= (NOW() - INTERVAL '30 minutes')
    ORDER BY ST_Distance(pr.location, v_origin) ASC
    LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_players(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, sport_type, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_player_presence(DOUBLE PRECISION, DOUBLE PRECISION, sport_type, BOOLEAN) TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. CREATE RACE SECURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_race_secure(
    p_sport sport_type,
    p_mode race_mode_type,
    p_visibility race_visibility_type DEFAULT 'public',
    p_participant_limit INTEGER DEFAULT 4,
    p_route_id UUID DEFAULT NULL,
    p_configuration JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
    v_creator_id UUID := auth.uid();
    v_race_id UUID;
BEGIN
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_participant_limit < 2 OR p_participant_limit > 20 THEN
        RAISE EXCEPTION 'Participant limit must be between 2 and 20';
    END IF;

    -- Insert race in WAITING status
    INSERT INTO public.races (
        creator_id,
        sport,
        mode,
        visibility,
        status,
        participant_limit,
        route_id,
        configuration
    )
    VALUES (
        v_creator_id,
        p_sport,
        p_mode,
        p_visibility,
        'WAITING',
        p_participant_limit,
        p_route_id,
        p_configuration
    )
    RETURNING id INTO v_race_id;

    -- Automatically enroll creator as ready
    INSERT INTO public.race_participants (
        race_id,
        user_id,
        status,
        joined_at,
        ready_at
    )
    VALUES (
        v_race_id,
        v_creator_id,
        'ready',
        NOW(),
        NOW()
    );

    -- Log audit event
    INSERT INTO public.audit_events (
        actor_id,
        event_type,
        entity_type,
        entity_id,
        sanitized_metadata
    )
    VALUES (
        v_creator_id,
        'RACE_CREATED',
        'races',
        v_race_id::text,
        jsonb_build_object('sport', p_sport, 'mode', p_mode, 'visibility', p_visibility)
    );

    RETURN v_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 5. JOIN RACE SECURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_race_secure(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_current_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status <> 'WAITING' THEN
        RAISE EXCEPTION 'Cannot join race; status is %', v_race.status;
    END IF;

    SELECT COUNT(*) INTO v_current_count 
    FROM public.race_participants 
    WHERE race_id = p_race_id;

    IF v_current_count >= v_race.participant_limit THEN
        RAISE EXCEPTION 'Race lobby is full';
    END IF;

    INSERT INTO public.race_participants (race_id, user_id, status, joined_at)
    VALUES (p_race_id, v_user_id, 'joined', NOW())
    ON CONFLICT (race_id, user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 6. SET PARTICIPANT READINESS & CHECK AUTO-START
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_participant_ready(
    p_race_id UUID,
    p_is_ready BOOLEAN
)
RETURNS TEXT AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_total_participants INTEGER;
    v_ready_participants INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK') THEN
        RAISE EXCEPTION 'Cannot change readiness in status %', v_race.status;
    END IF;

    UPDATE public.race_participants
    SET status = CASE WHEN p_is_ready THEN 'ready'::participant_status_type ELSE 'joined'::participant_status_type END,
        ready_at = CASE WHEN p_is_ready THEN NOW() ELSE NULL END
    WHERE race_id = p_race_id AND user_id = v_user_id;

    -- Check if all participants are ready
    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'ready')
    INTO v_total_participants, v_ready_participants
    FROM public.race_participants
    WHERE race_id = p_race_id;

    IF v_total_participants >= 2 AND v_total_participants = v_ready_participants THEN
        UPDATE public.races
        SET status = 'COUNTDOWN',
            scheduled_start_at = NOW() + INTERVAL '10 seconds'
        WHERE id = p_race_id;
        RETURN 'COUNTDOWN_STARTED';
    END IF;

    RETURN 'READY_UPDATED';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 7. TRANSITION RACE STATE (Strict State Machine)
-- Allowed: WAITING -> READY_CHECK -> COUNTDOWN -> IN_PROGRESS -> FINISHING -> COMPLETED
-- Or CANCELLED / ABORTED
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_race_state(
    p_race_id UUID,
    p_new_status race_status_type
)
RETURNS race_status_type AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_is_admin BOOLEAN;
BEGIN
    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    v_is_admin := public.has_admin_role('super_admin', 'operations_admin');

    -- Authorization check
    IF NOT v_is_admin AND v_race.creator_id <> v_user_id THEN
        RAISE EXCEPTION 'Only creator or authorized administrator can transition race state';
    END IF;

    -- Valid state transitions validation
    IF p_new_status = 'CANCELLED' THEN
        IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
            RAISE EXCEPTION 'Race cannot be cancelled once in progress';
        END IF;
    ELSIF p_new_status = 'ABORTED' THEN
        IF v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN
            RAISE EXCEPTION 'Only active races can be aborted';
        END IF;
    ELSIF p_new_status = 'READY_CHECK' THEN
        IF v_race.status <> 'WAITING' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'COUNTDOWN' THEN
        IF v_race.status NOT IN ('WAITING', 'READY_CHECK') THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'IN_PROGRESS' THEN
        IF v_race.status <> 'COUNTDOWN' THEN RAISE EXCEPTION 'Race must go through countdown before starting'; END IF;
        UPDATE public.races SET actual_start_at = NOW() WHERE id = p_race_id;
        UPDATE public.race_participants SET status = 'racing' WHERE race_id = p_race_id AND status = 'ready';
    ELSIF p_new_status = 'FINISHING' THEN
        IF v_race.status <> 'IN_PROGRESS' THEN RAISE EXCEPTION 'Invalid transition'; END IF;
    ELSIF p_new_status = 'COMPLETED' THEN
        IF v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN RAISE EXCEPTION 'Invalid transition'; END IF;
        UPDATE public.races SET completed_at = NOW() WHERE id = p_race_id;
    END IF;

    UPDATE public.races
    SET status = p_new_status
    WHERE id = p_race_id;

    RETURN p_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 8. SUBMIT GPS BATCH WITH ANTI-CHEAT VALIDATION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_gps_batch(
    p_race_id UUID,
    p_samples JSONB -- Array of {sequence_no, latitude, longitude, accuracy_m, altitude_m, recorded_at}
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_sample RECORD;
    v_last_sample RECORD;
    v_accepted INTEGER := 0;
    v_rejected INTEGER := 0;
    v_max_speed_mps DOUBLE PRECISION;
    v_speed_calculated DOUBLE PRECISION;
    v_delta_meters DOUBLE PRECISION;
    v_delta_seconds DOUBLE PRECISION;
    v_flagged_reason TEXT := NULL;
    v_total_valid_dist NUMERIC := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id;
    IF NOT FOUND OR v_race.status NOT IN ('IN_PROGRESS', 'FINISHING') THEN
        RAISE EXCEPTION 'Race is not active';
    END IF;

    -- Sport specific physical max speeds (with margin for GPS jitter)
    -- Running: 12.5 m/s (~45 km/h, Usain Bolt peak is ~44.7 km/h)
    -- Cycling: 30 m/s (~108 km/h, sprint/descent)
    -- Motorbike: 100 m/s (~360 km/h, closed circuit)
    IF v_race.sport = 'running' THEN
        v_max_speed_mps := 12.5;
    ELSIF v_race.sport = 'cycling' THEN
        v_max_speed_mps := 30.0;
    ELSE
        v_max_speed_mps := 100.0;
    END IF;

    -- Fetch the participant's most recent valid sample
    SELECT * INTO v_last_sample 
    FROM public.gps_samples 
    WHERE race_id = p_race_id AND user_id = v_user_id 
    ORDER BY sequence_no DESC LIMIT 1;

    -- Iterate through submitted samples
    FOR v_sample IN 
        SELECT 
            (s->>'sequence_no')::INTEGER AS sequence_no,
            (s->>'latitude')::DOUBLE PRECISION AS latitude,
            (s->>'longitude')::DOUBLE PRECISION AS longitude,
            (s->>'accuracy_m')::DOUBLE PRECISION AS accuracy_m,
            (s->>'altitude_m')::DOUBLE PRECISION AS altitude_m,
            (s->>'recorded_at')::TIMESTAMPTZ AS recorded_at
        FROM jsonb_array_elements(p_samples) AS s
        ORDER BY (s->>'sequence_no')::INTEGER ASC
    LOOP
        -- Sanity & bounds check
        IF v_sample.latitude < -90 OR v_sample.latitude > 90 OR 
           v_sample.longitude < -180 OR v_sample.longitude > 180 OR
           v_sample.accuracy_m > 50.0 -- Reject noisy samples > 50m accuracy
        THEN
            v_rejected := v_rejected + 1;
            CONTINUE;
        END IF;

        -- Ensure sequence increment
        IF v_last_sample.sequence_no IS NOT NULL AND v_sample.sequence_no <= v_last_sample.sequence_no THEN
            -- Duplicate or out-of-order sample
            v_rejected := v_rejected + 1;
            CONTINUE;
        END IF;

        -- Velocity jump calculation
        IF v_last_sample.latitude IS NOT NULL THEN
            v_delta_meters := ST_Distance(
                ST_SetSRID(ST_MakePoint(v_sample.longitude, v_sample.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint(v_last_sample.longitude, v_last_sample.latitude), 4326)::geography
            );
            v_delta_seconds := EXTRACT(EPOCH FROM (v_sample.recorded_at - v_last_sample.recorded_at));

            IF v_delta_seconds > 0.05 THEN
                v_speed_calculated := v_delta_meters / v_delta_seconds;
                IF v_speed_calculated > v_max_speed_mps THEN
                    -- Flag implausible teleportation / spoofing
                    v_flagged_reason := 'IMPLAUSIBLE_SPEED_JUMP';
                    v_rejected := v_rejected + 1;
                    CONTINUE;
                END IF;
                v_total_valid_dist := v_total_valid_dist + v_delta_meters;
            END IF;
        END IF;

        -- Insert valid sample
        INSERT INTO public.gps_samples (
            race_id,
            user_id,
            sequence_no,
            latitude,
            longitude,
            accuracy_m,
            altitude_m,
            speed_mps,
            recorded_at,
            received_at
        )
        VALUES (
            p_race_id,
            v_user_id,
            v_sample.sequence_no,
            v_sample.latitude,
            v_sample.longitude,
            v_sample.accuracy_m,
            v_sample.altitude_m,
            COALESCE(v_speed_calculated, 0),
            v_sample.recorded_at,
            NOW()
        )
        ON CONFLICT (race_id, user_id, sequence_no) DO NOTHING;

        v_accepted := v_accepted + 1;
        v_last_sample := v_sample;
    END LOOP;

    -- Update participant's validated distance
    IF v_total_valid_dist > 0 THEN
        UPDATE public.race_participants
        SET validated_distance_m = COALESCE(validated_distance_m, 0) + v_total_valid_dist
        WHERE race_id = p_race_id AND user_id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'accepted', v_accepted,
        'rejected', v_rejected,
        'flagged_reason', v_flagged_reason
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 9. FINALIZE RACE RESULTS (Idempotent Server Finalization)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalize_race_results(p_race_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_race RECORD;
    v_part RECORD;
    v_rank INTEGER := 1;
    v_existing_results_count INTEGER;
    v_xp_gain INTEGER;
    v_rating_delta INTEGER;
    v_elapsed BIGINT;
BEGIN
    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    -- Idempotency check: if already finalized, return existing results
    SELECT COUNT(*) INTO v_existing_results_count FROM public.race_results WHERE race_id = p_race_id;
    IF v_existing_results_count > 0 THEN
        RETURN jsonb_build_object('status', 'ALREADY_FINALIZED', 'results_count', v_existing_results_count);
    END IF;

    -- Transition race to COMPLETED
    UPDATE public.races 
    SET status = 'COMPLETED', completed_at = NOW() 
    WHERE id = p_race_id;

    -- Process rankings based on race mode
    -- Time Trial: highest verified distance wins
    -- Distance Race: fastest finish time or highest distance
    FOR v_part IN
        SELECT 
            rp.user_id,
            rp.validated_distance_m,
            rp.finish_time_ms,
            rp.status AS part_status
        FROM public.race_participants rp
        WHERE rp.race_id = p_race_id
        ORDER BY 
            CASE WHEN v_race.mode = 'time_trial' THEN rp.validated_distance_m END DESC NULLS LAST,
            CASE WHEN v_race.mode <> 'time_trial' THEN COALESCE(rp.finish_time_ms, 999999999) END ASC,
            rp.joined_at ASC
    LOOP
        v_elapsed := COALESCE(v_part.finish_time_ms, 
            EXTRACT(EPOCH FROM (NOW() - COALESCE(v_race.actual_start_at, v_race.created_at))) * 1000)::BIGINT;

        -- Insert official verified result
        INSERT INTO public.race_results (
            race_id,
            user_id,
            rank,
            verified_distance_m,
            elapsed_ms,
            validation_status,
            validation_summary,
            finalized_at
        )
        VALUES (
            p_race_id,
            v_part.user_id,
            v_rank,
            COALESCE(v_part.validated_distance_m, 0),
            v_elapsed,
            'valid',
            jsonb_build_object('rank', v_rank, 'mode', v_race.mode, 'sport', v_race.sport),
            NOW()
        );

        -- Calculate XP & Rating awards
        -- 1st: 100 XP, +25 Rating
        -- 2nd: 60 XP, +10 Rating
        -- 3rd: 40 XP, +5 Rating
        -- Others: 20 XP, 0 Rating
        IF v_rank = 1 THEN
            v_xp_gain := 100;
            v_rating_delta := 25;
        ELSIF v_rank = 2 THEN
            v_xp_gain := 60;
            v_rating_delta := 10;
        ELSIF v_rank = 3 THEN
            v_xp_gain := 40;
            v_rating_delta := 5;
        ELSE
            v_xp_gain := 20;
            v_rating_delta := 0;
        END IF;

        -- Update Leaderboard entries
        INSERT INTO public.leaderboard_entries (
            user_id,
            sport,
            rating,
            xp,
            races_completed,
            wins
        )
        VALUES (
            v_part.user_id,
            v_race.sport,
            1200 + v_rating_delta,
            v_xp_gain,
            1,
            CASE WHEN v_rank = 1 THEN 1 ELSE 0 END
        )
        ON CONFLICT (user_id, sport) DO UPDATE SET
            rating = GREATEST(0, public.leaderboard_entries.rating + v_rating_delta),
            xp = public.leaderboard_entries.xp + v_xp_gain,
            races_completed = public.leaderboard_entries.races_completed + 1,
            wins = public.leaderboard_entries.wins + (CASE WHEN v_rank = 1 THEN 1 ELSE 0 END),
            updated_at = NOW();

        -- Award First Race achievement
        INSERT INTO public.user_achievements (user_id, achievement_id, earned_at)
        VALUES (v_part.user_id, 'first_race', NOW())
        ON CONFLICT DO NOTHING;

        IF v_rank = 1 THEN
            INSERT INTO public.user_achievements (user_id, achievement_id, earned_at)
            VALUES (v_part.user_id, 'podium_finisher', NOW())
            ON CONFLICT DO NOTHING;
        END IF;

        v_rank := v_rank + 1;
    END LOOP;

    -- Audit log
    INSERT INTO public.audit_events (
        actor_id,
        event_type,
        entity_type,
        entity_id,
        sanitized_metadata
    )
    VALUES (
        v_race.creator_id,
        'RACE_FINALIZED',
        'races',
        p_race_id::text,
        jsonb_build_object('sport', v_race.sport, 'mode', v_race.mode, 'ranks_awarded', v_rank - 1)
    );

    RETURN jsonb_build_object('status', 'SUCCESS', 'ranks_awarded', v_rank - 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
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

-- ==============================================================================
-- 7. RACE LIFECYCLE EXTENSIONS (start_race_now, add_bot_participant, cancel_race, leave_race)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.start_race_now(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.creator_id <> v_user_id THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.race_participants 
            WHERE race_id = p_race_id AND user_id = v_user_id
        ) THEN
            RAISE EXCEPTION 'Only race host can force start the race';
        END IF;
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        RAISE EXCEPTION 'Cannot start race with status %', v_race.status;
    END IF;

    UPDATE public.race_participants
    SET status = 'ready'::participant_status_type,
        ready_at = COALESCE(ready_at, NOW())
    WHERE race_id = p_race_id AND status = 'joined';

    UPDATE public.races
    SET status = 'COUNTDOWN',
        scheduled_start_at = NOW() + INTERVAL '5 seconds'
    WHERE id = p_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.add_bot_participant(
    p_race_id UUID,
    p_bot_name TEXT DEFAULT 'Racer Vikram (AI)'
)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_bot_id UUID;
    v_bot_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status <> 'WAITING' THEN
        RAISE EXCEPTION 'Cannot add bots to race with status %', v_race.status;
    END IF;

    SELECT COUNT(*) INTO v_bot_count FROM public.race_participants WHERE race_id = p_race_id;
    v_bot_id := md5(p_race_id::text || '_bot_' || v_bot_count::text)::uuid;

    BEGIN
        INSERT INTO auth.users (id, aud, role, email)
        VALUES (v_bot_id, 'authenticated', 'authenticated', 'bot_' || SUBSTRING(v_bot_id::text, 1, 8) || '@racezone.local')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    INSERT INTO public.profiles (id, display_name, account_status)
    VALUES (v_bot_id, COALESCE(p_bot_name, 'Racer Vikram (AI)'), 'active')
    ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

    INSERT INTO public.race_participants (race_id, user_id, status, joined_at, ready_at)
    VALUES (p_race_id, v_bot_id, 'ready'::participant_status_type, NOW(), NOW())
    ON CONFLICT (race_id, user_id) DO UPDATE SET status = 'ready'::participant_status_type;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.cancel_race(p_race_id UUID)
RETURNS void AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.creator_id <> v_user_id AND NOT public.has_admin_role('super_admin', 'operations_admin') THEN
        RAISE EXCEPTION 'Only creator or authorized administrator can cancel this race';
    END IF;

    IF v_race.status NOT IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        RAISE EXCEPTION 'Race cannot be cancelled once in progress';
    END IF;

    UPDATE public.races
    SET status = 'CANCELLED'
    WHERE id = p_race_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.leave_race(p_race_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_race RECORD;
    v_next_creator UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_race FROM public.races WHERE id = p_race_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Race not found';
    END IF;

    IF v_race.status IN ('WAITING', 'READY_CHECK', 'COUNTDOWN') THEN
        DELETE FROM public.race_participants
        WHERE race_id = p_race_id AND user_id = v_user_id;

        IF v_race.creator_id = v_user_id THEN
            SELECT user_id INTO v_next_creator
            FROM public.race_participants
            WHERE race_id = p_race_id
            ORDER BY joined_at ASC
            LIMIT 1;

            IF v_next_creator IS NOT NULL THEN
                UPDATE public.races SET creator_id = v_next_creator WHERE id = p_race_id;
            ELSE
                UPDATE public.races SET status = 'CANCELLED' WHERE id = p_race_id;
            END IF;
        END IF;

        RETURN 'LEFT_LOBBY';
    ELSIF v_race.status IN ('IN_PROGRESS', 'FINISHING') THEN
        UPDATE public.race_participants
        SET status = 'dnf'::participant_status_type
        WHERE race_id = p_race_id AND user_id = v_user_id;

        IF NOT EXISTS (
            SELECT 1 FROM public.race_participants
            WHERE race_id = p_race_id AND status = 'racing'
        ) THEN
            PERFORM public.finalize_race_results(p_race_id);
        END IF;

        RETURN 'MARKED_DNF';
    ELSE
        RETURN 'NO_ACTION';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

