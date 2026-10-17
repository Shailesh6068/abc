import 'dart:math' as math;

class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

class GeoUtils {
  static const double earthRadiusMeters = 6371000.0;

  /// Calculate great-circle distance between two GPS coordinates using the Haversine formula
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Convert velocity from meters/second to kilometers/hour
  static double mpsToKmh(double mps) {
    return mps * 3.6;
  }

  /// Calculate running pace string (e.g. "4:32 /km") from speed in m/s
  static String formatRunningPace(double speedMps) {
    if (speedMps <= 0.2) return "--:-- /km"; // Stationary
    final secondsPerKm = 1000.0 / speedMps;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
  }

  /// Format elapsed duration into HH:MM:SS or MM:SS
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format distance into readable meters or kilometers (e.g., "750 m", "2.45 km")
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  /// Bearing between two points in degrees (0..360)
  static double calculateBearing(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final lat1 = _toRadians(startLat);
    final lat2 = _toRadians(endLat);
    final dLon = _toRadians(endLng - startLng);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return (_toDegrees(radians) + 360) % 360;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);
  static double _toDegrees(double radians) => radians * (180.0 / math.pi);
}
