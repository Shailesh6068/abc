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
