import 'package:flutter_test/flutter_test.dart';
import 'package:racezone/core/security/gps_validator.dart';

void main() {
  group('GpsValidator Anti-Cheat Tests', () {
    test('Rejects mock location', () {
      final validator = GpsValidator(sport: 'running');
      final report = validator.validateSample(
        sequenceNo: 1,
        latitude: 13.0,
        longitude: 80.0,
        accuracyMeters: 5.0,
        recordedAt: DateTime.now(),
        isMocked: true,
      );

      expect(report.isValid, isFalse);
      expect(report.result, equals(GpsValidationResult.mockLocationDetected));
    });

    test('Rejects noisy GPS samples with poor accuracy', () {
      final validator = GpsValidator(sport: 'running');
      final report = validator.validateSample(
        sequenceNo: 1,
        latitude: 13.0,
        longitude: 80.0,
        accuracyMeters: 65.0, // Exceeds 45m threshold
        recordedAt: DateTime.now(),
      );

      expect(report.isValid, isFalse);
      expect(report.result, equals(GpsValidationResult.poorAccuracy));
    });

    test('Accepts valid initial and incremental running samples within physiological limits', () {
      final validator = GpsValidator(sport: 'running');
      final now = DateTime.now();

      final r1 = validator.validateSample(
        sequenceNo: 1,
        latitude: 13.0000,
        longitude: 80.0000,
        accuracyMeters: 4.0,
        recordedAt: now,
      );
      expect(r1.isValid, isTrue);

      // Moved 5 meters in 1 second = 5 m/s (valid running speed)
      final r2 = validator.validateSample(
        sequenceNo: 2,
        latitude: 13.000045,
        longitude: 80.0000,
        accuracyMeters: 4.0,
        recordedAt: now.add(const Duration(seconds: 1)),
      );
      expect(r2.isValid, isTrue);
      expect(r2.result, equals(GpsValidationResult.valid));
    });

    test('Rejects excessive speed for runners (e.g. driving a car or spoofing)', () {
      final validator = GpsValidator(sport: 'running');
      final now = DateTime.now();

      validator.validateSample(
        sequenceNo: 1,
        latitude: 13.0000,
        longitude: 80.0000,
        accuracyMeters: 4.0,
        recordedAt: now,
      );

      // Jumped 100 meters in 1 second = 100 m/s (~360 km/h) -> Excessive for running!
      final r2 = validator.validateSample(
        sequenceNo: 2,
        latitude: 13.0009,
        longitude: 80.0000,
        accuracyMeters: 4.0,
        recordedAt: now.add(const Duration(seconds: 1)),
      );

      expect(r2.isValid, isFalse);
      expect(r2.result, equals(GpsValidationResult.excessiveSpeed));
    });

    test('Rejects duplicate or out-of-order sequence samples', () {
      final validator = GpsValidator(sport: 'cycling');
      final now = DateTime.now();

      validator.validateSample(
        sequenceNo: 5,
        latitude: 13.0,
        longitude: 80.0,
        accuracyMeters: 5.0,
        recordedAt: now,
      );

      // Sequence 3 arrives after Sequence 5
      final r2 = validator.validateSample(
        sequenceNo: 3,
        latitude: 13.0001,
        longitude: 80.0001,
        accuracyMeters: 5.0,
        recordedAt: now.add(const Duration(seconds: 1)),
      );

      expect(r2.isValid, isFalse);
      expect(r2.result, equals(GpsValidationResult.outOfSequence));
    });
  });
}
