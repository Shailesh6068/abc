# RaceZone — Google AdMob Integration & Placement Safety Guide

## 1. Official Google Test Ad Identifiers

For development, testing, and continuous integration, official Google Test Ad IDs are configured:

### Android
- **AdMob App ID:** `ca-app-pub-3940256099942544~3347511713`
- **Banner Ad Unit ID:** `ca-app-pub-3940256099942544/6300978111`

### iOS
- **AdMob App ID:** `ca-app-pub-3940256099942544~1458002511`
- **Banner Ad Unit ID:** `ca-app-pub-3940256099942544/2934735716`

---

## 2. Strict Placement Safety Rules

Advertisements are strictly governed by `AdService.canShowAd` in `mobile/lib/features/ads/services/ad_service.dart`:

| Screen / State | Ad Allowed? | Reason |
|---|---|---|
| **Active Race Stage (`isLiveRacing == true`)** | **STRICTLY FORBIDDEN** | Safety hazard; racer must never be distracted while in motion |
| **Live Map & Telemetry HUD** | **STRICTLY FORBIDDEN** | Distraction hazard; accidental clicks during navigation |
| **Race Countdown** | **STRICTLY FORBIDDEN** | High tension; prevents misclicks before start |
| **Emergency Stop / Abandon Dialog** | **STRICTLY FORBIDDEN** | Critical safety control must remain unobstructed |
| **Home Matchmaking Drawer** | **ALLOWED** | Static adaptive banner below nearby competitor drawer |
| **Post-Race Verified Standings** | **ALLOWED** | Static banner below podium results table |

---

## 3. Privacy & User Messaging Platform (UMP) Consent

- **Location Data Protection:** Precise race coordinates and real-time GPS paths are NEVER transmitted to Google Mobile Ads or third-party ad networks.
- **Consent Framework:** The app supports Google's User Messaging Platform (UMP) SDK for GDPR / CCPA compliance and iOS App Tracking Transparency (ATT).
