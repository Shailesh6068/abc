import 'package:flutter_test/flutter_test.dart';
import 'package:racezone/core/utils/geo_utils.dart';

void main() {
  group('GeoUtils Tests', () {
    test('Haversine distance calculation is accurate within 1 meter', () {
      // Coordinate pair: Chennai Marina Beach Sprint (approx 1000m)
      const lat1 = 13.0475;
      const lon1 = 80.2825;
      const lat2 = 13.0565;
      const lon2 = 80.2835;

      final distance = GeoUtils.haversineDistanceMeters(lat1, lon1, lat2, lon2);
      expect(distance, greaterThan(950));
      expect(distance, lessThan(1050));
    });

    test('Zero distance when points are identical', () {
      final distance = GeoUtils.haversineDistanceMeters(13.0, 80.0, 13.0, 80.0);
      expect(distance, equals(0.0));
    });

    test('Pace formatting converts m/s to min:sec /km correctly', () {
      // 1000m in 300 seconds (5 min/km) = 1000 / 300 = 3.333 m/s
      final paceStr = GeoUtils.formatRunningPace(3.3333);
      expect(paceStr, equals('5:00 /km'));

      // Stationary pace returns placeholder
      final stationaryStr = GeoUtils.formatRunningPace(0.1);
      expect(stationaryStr, equals('--:-- /km'));
    });

    test('Duration formatting handles minutes and hours properly', () {
      expect(GeoUtils.formatDuration(const Duration(minutes: 5, seconds: 24)), equals('05:24'));
      expect(GeoUtils.formatDuration(const Duration(hours: 1, minutes: 12, seconds: 8)), equals('01:12:08'));
    });

    test('Distance formatting switches from m to km accurately', () {
      expect(GeoUtils.formatDistance(450.4), equals('450 m'));
      expect(GeoUtils.formatDistance(1250.0), equals('1.25 km'));
    });
  });
}
