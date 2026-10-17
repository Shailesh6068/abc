class AppConfig {
  // Brand & Identification
  static const String appName = 'RaceZone';
  static const String appVersion = '1.0.0';
  static const String bundleId = 'com.racezone.app';

  // Backend Endpoints (Can be loaded from environment or defaults)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder-project.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  // Google Maps API Key
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'placeholder-maps-key',
  );

  // Google AdMob Configuration (Official Google Test Ad Unit IDs)
  // https://developers.google.com/admob/flutter/test-ads
  static const String admobBannerUnitIdAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111', // Test Banner ID
  );

  static const String admobBannerUnitIdIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716', // Test Banner ID
  );

  // Client-Side Anti-Cheat Pre-Validation Thresholds
  // Running: Max ~45 km/h (12.5 m/s)
  static const double maxRunningSpeedMps = 12.5;

  // Cycling: Max ~108 km/h (30.0 m/s)
  static const double maxCyclingSpeedMps = 30.0;

  // Motorbike: Max ~360 km/h (100.0 m/s)
  static const double maxMotorbikeSpeedMps = 100.0;

  // Reject GPS samples with horizontal accuracy worse than 45 meters
  static const double maxAllowedAccuracyMeters = 45.0;

  // Minimum displacement to record a sample (reduces jitter when stationary)
  static const double minDisplacementMeters = 1.5;
}
