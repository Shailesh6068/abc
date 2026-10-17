# RaceZone — Database & Storage Specification

## Database Architecture
- Engine: PostgreSQL 15+
- Spatial Extension: PostGIS (`postgis`, `uuid-ossp`)
- Security: Row Level Security (RLS) active on 100% of exposed tables.

---

## Table Dictionary

| Section | Table Name | Purpose | RLS Policy Summary |
|---|---|---|---|
| **7.1** | `profiles` | Athlete profiles linked to `auth.users(id)` | Public read; self-update for display name/avatar; status editable only by admins |
| **7.2** | `player_preferences` | Sports choices, discovery toggle, search radius | Read/write strictly restricted to owner (`auth.uid() = user_id`) |
| **7.3** | `player_presence` | Ephemeral GPS coordinates & availability | Direct queries restricted; exposed via `get_nearby_players` RPC; auto-cleaned |
| **7.4** | `race_routes` | Sanctioned GPS LineString courses & points | Public read; creation authenticated; updates restricted to creator or admin |
| **7.5** | `races` | Active/completed race instances and status | Public or participant read; creation authenticated; state changes strictly via RPC |
| **7.6** | `race_participants` | Racer enrollment, readiness, finish times | Public read; self-join and self-leave while WAITING; readiness managed via RPC |
| **7.7** | `race_invitations` | Head-to-Head & group invites | Restricted to `inviter_id` and `invitee_id` |
| **7.8** | `gps_samples` | Time-series GPS telemetry stream | Write restricted to verified participant during active race; read by participants/admins |
| **7.9** | `race_results` | Official verified finish standings & ranks | Public read; insertions and updates exclusively restricted to backend finalization RPC |
| **7.10** | `leaderboard_entries` | Sport ratings, XP, race counts, and wins | Public read; rating updates locked to trusted server finalization RPC |
| **7.11** | `achievements` | Badges and criteria definitions | Public read; modifications restricted to super admins |
| **7.12** | `user_achievements` | Unlocked achievements ledger | Public read; earned stamps awarded via finalization RPC |
| **7.13** | `audit_events` | Immutable log of administrative and race actions | Readable exclusively by authorized staff (`super_admin`, `operations_admin`) |
| **7.14** | `admin_roles` | Role-based authorization mappings | Read restricted to current user or super admin; writes strictly super admin |
| **7.15** | `operating_expenses` | Financial ledger of cloud, Maps, and dev costs | Read/write restricted to `finance_viewer`, `operations_admin`, `super_admin` |
| **7.16** | `revenue_records` | AdMob settlements and recognized revenues | Read/write restricted to finance and super admin |
| **7.17** | `ad_analytics_daily` | Imported daily AdMob impressions and eCPMs | Read restricted to finance and admin staff |
| **7.18** | `moderation_reports` | Incident queue for GPS spoofing and abuse | Insert by reporter; updates restricted to moderators and admins |
| **7.19** | `app_configuration` | Global discovery, participant limits, speed caps | Public read; updates strictly restricted to super admin |

---

## Critical Spatial Indexes
- `idx_player_presence_location_gist`: GiST index on `player_presence.location` for sub-10ms `ST_DWithin` discovery queries.
- `idx_race_routes_start_gist`: GiST index on route starting points.
- `idx_gps_samples_lookup`: Composite B-Tree index on `(race_id, user_id, sequence_no)`.
- `idx_leaderboard_sorting`: Multi-column index on `(sport, rating DESC, xp DESC)`.
