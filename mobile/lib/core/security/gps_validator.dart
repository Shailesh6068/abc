import 'package:racezone/core/config/app_config.dart';
import 'package:racezone/core/utils/geo_utils.dart';

enum GpsValidationResult {
  valid,
  excessiveSpeed,
  poorAccuracy,
  outOfSequence,
  teleportationJump,
  mockLocationDetected,
}

class GpsValidationReport {
  final bool isValid;
  final GpsValidationResult result;
  final double calculatedSpeedMps;
  final double distanceDeltaMeters;

  const GpsValidationReport({
    required this.isValid,
    required this.result,
    this.calculatedSpeedMps = 0.0,
    this.distanceDeltaMeters = 0.0,
  });
}

class GpsValidator {
  final String sport; // 'running', 'cycling', 'motorbike'
  int _lastSequence = -1;
  double? _lastLat;
  double? _lastLng;
  DateTime? _lastTimestamp;

  GpsValidator({required this.sport});

  double get maxAllowedSpeedMps {
    switch (sport.toLowerCase()) {
      case 'cycling':
        return AppConfig.maxCyclingSpeedMps;
      case 'motorbike':
        return AppConfig.maxMotorbikeSpeedMps;
      case 'running':
      default:
        return AppConfig.maxRunningSpeedMps;
    }
  }

  GpsValidationReport validateSample({
    required int sequenceNo,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime recordedAt,
    bool isMocked = false,
  }) {
    // 1. Mock location rejection
    if (isMocked) {
      return const GpsValidationReport(
        isValid: false,
        result: GpsValidationResult.mockLocationDetected,
      );
    }

    // 2. Accuracy check (reject noisy readings)
    if (accuracyMeters > AppConfig.maxAllowedAccuracyMeters) {
      return const GpsValidationReport(
        isValid: false,
        result: GpsValidationResult.poorAccuracy,
      );
    }

    // 3. Sequence increment check
    if (sequenceNo <= _lastSequence) {
      return const GpsValidationReport(
        isValid: false,
        result: GpsValidationResult.outOfSequence,
      );
    }

    // First sample is always accepted if accuracy is good
    if (_lastLat == null || _lastLng == null || _lastTimestamp == null) {
      _lastSequence = sequenceNo;
      _lastLat = latitude;
      _lastLng = longitude;
      _lastTimestamp = recordedAt;
      return const GpsValidationReport(
        isValid: true,
        result: GpsValidationResult.valid,
      );
    }

    // 4. Calculate displacement and velocity delta
    final distanceMeters = GeoUtils.haversineDistanceMeters(
      _lastLat!,
      _lastLng!,
      latitude,
      longitude,
    );

    final durationSeconds = recordedAt.difference(_lastTimestamp!).inMilliseconds / 1000.0;

    if (durationSeconds > 0.05) {
      final speedMps = distanceMeters / durationSeconds;

      // 5. Sport physical speed limit check
      if (speedMps > maxAllowedSpeedMps) {
        return GpsValidationReport(
          isValid: false,
          result: GpsValidationResult.excessiveSpeed,
          calculatedSpeedMps: speedMps,
          distanceDeltaMeters: distanceMeters,
        );
      }

      // 6. Teleportation jump check (> 200m in < 2 seconds)
      if (distanceMeters > 200.0 && durationSeconds < 2.0) {
        return GpsValidationReport(
          isValid: false,
          result: GpsValidationResult.teleportationJump,
          calculatedSpeedMps: speedMps,
          distanceDeltaMeters: distanceMeters,
        );
      }

      // Update state on valid sample
      _lastSequence = sequenceNo;
      _lastLat = latitude;
      _lastLng = longitude;
      _lastTimestamp = recordedAt;

      return GpsValidationReport(
        isValid: true,
        result: GpsValidationResult.valid,
        calculatedSpeedMps: speedMps,
        distanceDeltaMeters: distanceMeters,
      );
    }

    return const GpsValidationReport(
      isValid: true,
      result: GpsValidationResult.valid,
    );
  }

  void reset() {
    _lastSequence = -1;
    _lastLat = null;
    _lastLng = null;
    _lastTimestamp = null;
  }
}
