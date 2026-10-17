# RaceZone — System Architecture Specification

## 1. High-Level Topology

```
+-------------------------------------------------------------+
|                      RACEZONE CLIENTS                       |
|                                                             |
|   +-----------------------+     +-----------------------+   |
|   |   Mobile App (Flutter)|     | Admin Dashboard (Next)|   |
|   |   Android / iOS       |     | TypeScript, Tailwind  |   |
|   +-----------+-----------+     +-----------+-----------+   |
+---------------|-----------------------------|---------------+
                |                             |
                | WebSocket Realtime          | HTTPS REST / RPC
                | & HTTPS                     |
+---------------v-----------------------------v---------------+
|                    SUPABASE CLOUD INFRASTRUCTURE            |
|                                                             |
|   +-----------------------------------------------------+   |
|   |               PostgreSQL 15 + PostGIS               |   |
|   |  - ST_DWithin Geospatial Matchmaking                |   |
|   |  - Row Level Security (RLS) on all 19 Tables        |   |
|   |  - Server-Authoritative State Machine & Anti-Cheat  |   |
|   +-----------------------------------------------------+   |
|                                                             |
|   +-----------------------------------------------------+   |
|   |                 Supabase Edge Functions             |   |
|   |  - nearby-players       - submit-location           |   |
|   |  - create-race          - finalize-race             |   |
|   |  - race-command         - admin-user-management     |   |
|   |  - admin-finance        - import-admob-reports      |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

## 2. Server-Authoritative Race State Machine

Race lifecycle transitions are strictly validated by the backend procedure `transition_race_state`:

```
                 [WAITING]
                     |
                     v
               [READY_CHECK] ──(host or admin cancel)──> [CANCELLED]
                     |
                     v
                [COUNTDOWN]  (10-second authoritative countdown)
                     |
                     v
               [IN_PROGRESS] ──(emergency abandon)─────> [ABORTED]
                     |
                     v
                [FINISHING]
                     |
                     v
                [COMPLETED]  (Idempotent rank & XP finalization)
```

### Transition Security Rules
1. Only the race creator or an authorized administrator (`super_admin`, `operations_admin`) can advance or cancel waiting races.
2. Direct client updates to `status = 'COMPLETED'` or `status = 'IN_PROGRESS'` are blocked by RLS policies; transitions must pass through `transition_race_state`.
3. Client phone clocks are never trusted for race finish timing or rankings. Start times and durations are stamped authoritatively on PostgreSQL servers.

## 3. PostGIS Matchmaking & Privacy Fuzzing

Nearby competitor discovery uses `ST_DWithin` on the `player_presence.location` geography column backed by a spatial GiST index:

```sql
SELECT p.id, p.display_name, (ROUND(ST_Distance(pr.location, v_origin) / 25.0) * 25)::INTEGER AS approx_distance_m
FROM public.player_presence pr
JOIN public.profiles p ON p.id = pr.user_id
WHERE ST_DWithin(pr.location, v_origin, p_radius_m)
  AND pr.is_available = true
  AND pref.discovery_enabled = true;
```

**Privacy Guarantee:** Raw coordinates are never returned by the discovery API. Distances are fuzzed and rounded to the nearest 25 meters to prevent triangulation attacks.
