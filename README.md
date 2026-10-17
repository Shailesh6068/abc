# RaceZone — Real-Time GPS Racing Platform

[![Next.js Build](https://img.shields.io/badge/Next.js-16.4.2-black?logo=next.js)](https://nextjs.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev/)
[![Supabase & PostGIS](https://img.shields.io/badge/Supabase-PostgreSQL%2015%20%2B%20PostGIS-3ECF8E?logo=supabase)](https://supabase.com/)
[![AdMob](https://img.shields.io/badge/Google%20AdMob-SDK%20Integrated-EA4335?logo=google)](https://admob.google.com/)
[![License](https://img.shields.io/badge/License-Proprietary-blue.svg)](#)

RaceZone is a real-time, location-based competitive racing application for Android and iOS, accompanied by an administrative command center and financial operations dashboard.

Athletes compete across three disciplines:
1. **Running** (Pace tracking, sprint intervals, urban circuits)
2. **Cycling** (Velocity telemetry, distance loops)
3. **Motorbike Racing** (Closed-circuit sanctioned tracks only; strictly non-public road)

---

## 🏗️ System Architecture & Technology Stack

### Mobile Application (`mobile/`)
- **Framework:** Flutter 3.x & Dart with sound null safety
- **State Management:** Riverpod (`flutter_riverpod`)
- **Navigation:** Declarative routing with GoRouter (`go_router`)
- **Geospatial & Sensors:** `geolocator`, `permission_handler`, `google_maps_flutter`
- **Monetization:** Official Google Mobile Ads Flutter SDK (`google_mobile_ads`) with safe placement engine
- **Design System:** Sports-tech dark charcoal (`#090D16`), electric neon green (`#00E676`), velocity cyan (`#00E5FF`), high-contrast telemetry

### Backend Infrastructure (`supabase/`)
- **Database:** PostgreSQL 15 with **PostGIS** geospatial extensions
- **Realtime:** Supabase Realtime channels for sub-second competitor coordinate streaming
- **Security:** 100% Row Level Security (RLS) across all 19 database tables (7.1 – 7.19)
- **Functions:** 10 TypeScript Edge Functions handling matchmaking, batch GPS anti-cheat ingestion, idempotent race finalization, and role authorization

### Admin Web Dashboard (`admin/`)
- **Framework:** Next.js 16 (App Router) + TypeScript + React 19
- **Styling:** Tailwind CSS with custom responsive sports-tech design tokens
- **Data Visualization:** Recharts for telemetry trends, category expenses, and revenue run-rates
- **Role-Based Access Control:** `super_admin`, `operations_admin`, `support_admin`, `finance_viewer`, `moderator`

---

## 📁 Repository Structure

```
e:/game/
├── mobile/                   # Flutter cross-platform mobile application
│   ├── lib/
│   │   ├── main.dart         # App entry point (Supabase & AdMob initialization)
│   │   ├── app/              # Router, App Theme, and MaterialApp shell
│   │   ├── core/             # GeoUtils, GpsValidator, AppConfig, AppColors
│   │   └── features/         # Feature-first modules (auth, home, discovery, races, live_race, results, profile, ads)
│   ├── test/                 # Flutter unit tests (math, anti-cheat, ad safety)
│   ├── android/              # AndroidManifest with permissions & AdMob app metadata
│   └── ios/                  # iOS Info.plist with ATT, background location, and AdMob
├── admin/                    # Next.js web administrative dashboard
│   ├── src/
│   │   ├── app/              # Routes: Overview (/), Users, Races, Moderation, Finance, Settings
│   │   ├── components/       # Layout (Sidebar, Header) and modular UI components
│   │   └── lib/              # Supabase clients & RBAC AuthProvider
│   └── package.json          # Next.js dependencies (Recharts, Lucide, Tailwind)
├── supabase/                 # Backend migrations & Edge Functions
│   ├── config.toml           # Supabase local environment config
│   ├── migrations/           # Version-controlled SQL migrations (Schema, RLS, RPCs)
│   ├── functions/            # 10 Edge Functions (matchmaking, GPS, finalization, finance)
│   └── seed.sql              # Seed data (Achievements, sanctioned routes, expenses)
├── tests/                    # Automated integration & verification test runner
├── docs/                     # Comprehensive engineering & operations documentation
│   ├── architecture.md       # High-level architecture & state machine specification
│   ├── database.md           # Schema dictionaries, spatial indexes, and RLS tables
│   ├── security.md           # Anti-cheat heuristics, zero trust keys, and legal compliance
│   ├── admob-setup.md        # Official test IDs, placement safety engine, and UMP
│   ├── admin-guide.md        # Operations manual & incident adjudication
│   └── deployment.md         # Production cloud deployment checklists
├── .env.example              # Centralized environment variable template
├── .gitignore                # Multi-stack git ignore configuration
└── README.md                 # Master project documentation
```

---

## ⚡ Quick Start Guide

### 1. Environment Configuration
Copy the configuration template:
```bash
cp .env.example .env
```
Populate your Supabase URL, anon key, Google Maps API key, and AdMob identifiers.

### 2. Run the Admin Dashboard
```bash
cd admin
npm install
npm run dev
```
Open [http://localhost:3000](http://localhost:3000) to access the Admin Command Center.

### 3. Run the Automated Test Suite
Execute the comprehensive mathematical and anti-cheat verification tests:
```bash
node tests/run_verification_tests.js
```

### 4. Build the Admin Dashboard Bundle
```bash
cd admin
npm run build
```

---

## 🛡️ Anti-Cheat & Fair Play Specifications

1. **Dual Validation Pipeline:** Client pre-filters noisy readings (> 45m accuracy), while PostgreSQL procedures strictly validate coordinate velocity jumps against sport-specific physical ceilings:
   - **Running:** Capped at 12.5 m/s (~45 km/h)
   - **Cycling:** Capped at 30.0 m/s (~108 km/h)
   - **Motorbike:** Capped at 100.0 m/s (~360 km/h, closed circuit only)
2. **Privacy Fuzzing:** Matchmaking queries (`get_nearby_players`) round distances to the nearest 25m to protect athletes from exact triangulation.
3. **AdMob Safety Matrix:** Google AdMob banner ads are restricted to static Home and post-race Results views. Ads are **strictly prohibited** during countdowns, on active live race maps, or around emergency abandon controls.
4. **Legal & Anti-Gambling Compliance:** The platform strictly disallows real-money entry fees, pooled stakes, cash prize payouts, or withdrawals. Competition is driven purely by skill, XP, ratings, and achievements.
