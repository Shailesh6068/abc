# RaceZone — Production Deployment Guide

## 1. Supabase Backend Deployment

### Prerequisites
- Install Supabase CLI: `npm install -g supabase`
- Login to Supabase: `supabase login`
- Link remote project: `supabase link --project-ref your-project-id`

### Deploying Database Migrations & PostGIS
```bash
# Push migrations in version-controlled sequence
supabase db push

# Apply seed data (achievements, verified routes, and initial configs)
supabase db execute --file supabase/seed.sql
```

### Deploying Edge Functions
```bash
supabase functions deploy nearby-players
supabase functions deploy create-race
supabase functions deploy join-race
supabase functions deploy race-command
supabase functions deploy submit-location
supabase functions deploy finalize-race
supabase functions deploy report-race
supabase functions deploy admin-user-management
supabase functions deploy admin-race-management
supabase functions deploy admin-finance
supabase functions deploy import-admob-reports
```

---

## 2. Admin Web Dashboard Deployment (Next.js)

### Environment Variables
Configure the following in your hosting provider (e.g. Vercel, AWS ECS, or Cloudflare Pages):
```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
NEXT_PUBLIC_APP_ENV=production
```

### Production Build & Launch
```bash
cd admin
npm install
npm run build
npm run start
```

---

## 3. Flutter Mobile Application Release Checklists

### Android (Google Play)
1. **AdMob Production App ID:** Replace test ID in `mobile/android/app/src/main/AndroidManifest.xml` with your approved AdMob App ID.
2. **Google Maps API Key:** Add your restricted Android Google Maps API Key to `local.properties` or manifest.
3. **App Signing:** Generate release keystore and configure `key.properties`.
4. **Build App Bundle:**
   ```bash
   cd mobile
   flutter build appbundle --release
   ```

### iOS (Apple App Store)
1. **AdMob Production App ID:** Replace test ID in `mobile/ios/Runner/Info.plist`.
2. **App Tracking Transparency (ATT):** Ensure `NSUserTrackingUsageDescription` is localized.
3. **Location Permission Descriptions:** Verify `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription`.
4. **Build Archive:**
   ```bash
   cd mobile
   flutter build ipa --release
   ```
