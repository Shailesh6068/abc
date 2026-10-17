# RaceZone — Admin Command Center Operations Guide

## 1. Role-Based Access Control (RBAC) Matrix

| Administrative Role | Overview Analytics | User Management | Race Ops & Disqualification | Moderation Queue | Finance & Operating Expenses | System Configuration |
|---|---|---|---|---|---|---|
| **`super_admin`** | Full | Full (Suspend/Activate) | Full | Full | Full (Add/Edit/Export) | Full |
| **`operations_admin`** | Full | Full | Full | Full | View Only | Full |
| **`support_admin`** | Full | Suspend / Reactivate | View Only | Full | No Access | No Access |
| **`finance_viewer`** | Financials | No Access | No Access | No Access | Full (Add/Export) | No Access |
| **`moderator`** | Limited | View Only | Inspect Telemetry | Adjudicate | No Access | No Access |

---

## 2. Operational Workflows

### 2.1 Adjudicating GPS Cheating & Teleportation Flags
1. Navigate to **Race Control** (`/races`).
2. Filter for races with `FLAGGED REVIEW` anti-cheat status.
3. Click the eye icon to inspect the sequence telemetry stream and velocity spikes.
4. If a teleportation jump (> 200m in < 2s) or velocity violation is confirmed:
   - Click **Disqualify Competitor**.
   - Input the mandatory audit justification.
   - The result rank is invalidated in `race_results`, XP is retracted, and an immutable entry is added to `audit_events`.

### 2.2 Recording Operating Expenses
1. Navigate to **Finance & Analytics** (`/finance`).
2. Click **Record Expense**.
3. Select the appropriate operational category (e.g., *Supabase hosting*, *Google Maps API*, *Storage*, *Developer licenses*).
4. Enter amount in INR, payee vendor, and description.
5. Click **Save Record**. The financial dashboard automatically recalculates the **Operating Result** (`Recorded Revenue - Operating Expenses`).
