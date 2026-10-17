import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:racezone/core/config/app_config.dart';

class AdService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_isInitialized) return;
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('AdMob initialization error: $e');
    }
  }

  /// Get the appropriate platform banner ad unit ID (Test IDs in development)
  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return AppConfig.admobBannerUnitIdAndroid;
    } else if (Platform.isIOS) {
      return AppConfig.admobBannerUnitIdIos;
    }
    return '';
  }

  /// Enforce strict safety constraints from Section 13:
  /// Ads are NEVER permitted during countdown, live race, on live map, or active controls.
  static bool canShowAd({
    required String screenName,
    required bool isLiveRacing,
  }) {
    if (isLiveRacing) return false;

    const blockedScreens = [
      'live_race',
      'countdown',
      'emergency_stop',
      'race_lobby_active',
    ];

    if (blockedScreens.contains(screenName)) {
      return false;
    }

    // Permitted on Home and Results screens only
    const permittedScreens = ['home', 'results', 'profile'];
    return permittedScreens.contains(screenName);
  }
}
