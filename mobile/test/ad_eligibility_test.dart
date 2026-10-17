import 'package:flutter_test/flutter_test.dart';
import 'package:racezone/features/ads/services/ad_service.dart';

void main() {
  group('Ad Placement & Safety Eligibility Tests', () {
    test('Ads are strictly blocked during active racing', () {
      expect(
        AdService.canShowAd(screenName: 'home', isLiveRacing: true),
        isFalse,
      );
      expect(
        AdService.canShowAd(screenName: 'live_race', isLiveRacing: true),
        isFalse,
      );
    });

    test('Ads are strictly blocked on safety-critical screens', () {
      expect(
        AdService.canShowAd(screenName: 'live_race', isLiveRacing: false),
        isFalse,
      );
      expect(
        AdService.canShowAd(screenName: 'countdown', isLiveRacing: false),
        isFalse,
      );
      expect(
        AdService.canShowAd(screenName: 'emergency_stop', isLiveRacing: false),
        isFalse,
      );
    });

    test('Ads are permitted only on non-disruptive static views when not racing', () {
      expect(
        AdService.canShowAd(screenName: 'home', isLiveRacing: false),
        isTrue,
      );
      expect(
        AdService.canShowAd(screenName: 'results', isLiveRacing: false),
        isTrue,
      );
      expect(
        AdService.canShowAd(screenName: 'profile', isLiveRacing: false),
        isTrue,
      );
    });
  });
}
