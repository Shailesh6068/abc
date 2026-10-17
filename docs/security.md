# RaceZone — Application Security & Legal Compliance

## 1. Zero Trust Architecture & Privileged Credentials

- **Secret Key Isolation:** The Supabase `service_role` key and backend signing secrets are NEVER embedded or referenced in the Flutter mobile application or Next.js browser client bundles. All privileged actions pass through authenticated Supabase Edge Functions with server-side authorization checks.
- **Client Elevation Prevention:** Clients cannot directly write or alter:
  - Account status (active/suspended)
  - Leaderboard ratings or XP
  - Verified race results
  - Administrative roles
  - Audit event logs

## 2. GPS Anti-Cheat Heuristics & Speed Thresholds

GPS tracking is protected via dual client and server validation layers:

| Check | Constraint | Action Upon Violation |
|---|---|---|
| **Mock Location** | `position.isMocked == true` | Immediate drop; flag raised in telemetry stream |
| **Accuracy Filter** | Horizontal error > 45.0 meters | Dropped from course progress accumulation |
| **Sequence Integrity** | `sequence_no <= last_sequence` | Duplicate or out-of-order rejection |
| **Running Velocity Cap** | Speed > 12.5 m/s (~45 km/h) | Dropped; flagged for vehicle spoofing |
| **Cycling Velocity Cap** | Speed > 30.0 m/s (~108 km/h) | Dropped; flagged for vehicle spoofing |
| **Motorbike Velocity Cap**| Speed > 100.0 m/s (~360 km/h) | Dropped; flagged for telemetry jump |
| **Teleportation Delta** | > 200m delta in < 2.0 seconds | Dropped; flagged for manual review |

## 3. Legal Restrictions & Anti-Gambling Compliance (Section 14)

### Explicit Prohibition of Real-Money Gaming
1. **No Cash Deposits:** The application contains zero payment gateways for user wallet balances or cash deposits.
2. **No Paid Race Entries or Pooled Stakes:** Racers compete exclusively on physical fitness and skill. Entry fees and pooled stakes are strictly disabled in backend policies.
3. **No Cash Prize Distributions or Withdrawals:** Victory awards non-monetary XP, rating points, and achievement badges only.
4. **Physical Racing Law & Motorbike Safety:** Indian gaming law and motor vehicle safety rules prohibit competitive high-speed racing on public roads. Motorbike racing in RaceZone is permitted strictly on sanctioned, closed circuits. Clear safety warnings are displayed before every event.
