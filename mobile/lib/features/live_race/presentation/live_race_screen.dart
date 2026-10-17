import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/core/security/gps_validator.dart';
import 'package:racezone/core/utils/geo_utils.dart';
import 'package:racezone/features/races/data/race_repository.dart';
import 'package:racezone/features/races/domain/race_model.dart';

class LiveRaceScreen extends ConsumerStatefulWidget {
  final String raceId;

  const LiveRaceScreen({super.key, required this.raceId});

  @override
  ConsumerState<LiveRaceScreen> createState() => _LiveRaceScreenState();
}

class _LiveRaceScreenState extends ConsumerState<LiveRaceScreen> {
  RaceModel? _race;
  StreamSubscription<Position>? _positionStream;
  RealtimeChannel? _raceChannel;
  late GpsValidator _gpsValidator;

  int _sequenceCounter = 0;
  final List<Map<String, dynamic>> _pendingSamples = [];
  Timer? _batchUploadTimer;
  Timer? _tickerTimer;

  // Telemetry metrics
  DateTime? _raceStartTime;
  Duration _elapsed = Duration.zero;
  double _totalDistanceMeters = 0.0;
  double _currentSpeedMps = 0.0;
  double _currentAccuracyM = 0.0;
  Position? _lastValidPosition;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _gpsValidator = GpsValidator(sport: 'running');
    _initializeRace();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _positionStream?.cancel();
    _batchUploadTimer?.cancel();
    _tickerTimer?.cancel();
    _raceChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _initializeRace() async {
    final repo = ref.read(raceRepositoryProvider);
    try {
      final race = await repo.getRaceDetails(widget.raceId);
      if (_isDisposed) return;

      setState(() {
        _race = race;
        _gpsValidator = GpsValidator(sport: race.sport);
        _raceStartTime = race.actualStartAt ?? DateTime.now();
      });

      // Local authoritative timer ticker
      _tickerTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_raceStartTime != null && mounted) {
          setState(() {
            _elapsed = DateTime.now().difference(_raceStartTime!);
          });
        }
      });

      // Start continuous location stream
      _startGpsTracking();

      // Batch submission every 3 seconds to backend anti-cheat
      _batchUploadTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _flushGpsBatch();
      });

      // Realtime subscription for competitor updates & completion
      _raceChannel = repo.subscribeToRace(widget.raceId, (updatedRace) {
        if (_isDisposed || !mounted) return;
        setState(() => _race = updatedRace);

        if (updatedRace.status == 'COMPLETED' || updatedRace.status == 'FINISHING') {
          context.go('/results/${widget.raceId}');
        }
      });
    } catch (e) {
      debugPrint('Live race init error: $e');
    }
  }

  void _startGpsTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      if (_isDisposed || !mounted) return;

      // Client pre-validation
      final report = _gpsValidator.validateSample(
        sequenceNo: _sequenceCounter++,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        recordedAt: position.timestamp,
        isMocked: position.isMocked,
      );

      if (report.isValid) {
        setState(() {
          _currentAccuracyM = position.accuracy;
          _currentSpeedMps = position.speed >= 0 ? position.speed : report.calculatedSpeedMps;
          _totalDistanceMeters += report.distanceDeltaMeters;
          _lastValidPosition = position;
        });

        _pendingSamples.add({
          'sequence_no': _sequenceCounter,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_m': position.accuracy,
          'altitude_m': position.altitude,
          'recorded_at': position.timestamp.toIso8601String(),
        });
      }
    });
  }

  Future<void> _flushGpsBatch() async {
    if (_pendingSamples.isEmpty) return;

    final samplesToSend = List<Map<String, dynamic>>.from(_pendingSamples);
    _pendingSamples.clear();

    try {
      await SupabaseService.client.rpc('submit_gps_batch', params: {
        'p_race_id': widget.raceId,
        'p_samples': samplesToSend,
      });
    } catch (e) {
      debugPrint('Batch GPS submit error: $e');
    }
  }

  Future<void> _finishRace() async {
    await _flushGpsBatch();
    try {
      await SupabaseService.client.rpc('finalize_race_results', params: {
        'p_race_id': widget.raceId,
      });
      if (mounted) {
        context.go('/results/${widget.raceId}');
      }
    } catch (e) {
      debugPrint('Finalize error: $e');
      if (mounted) context.go('/results/${widget.raceId}');
    }
  }

  Future<void> _abandonRace() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Abandon Race?', style: TextStyle(color: AppColors.accentRose)),
        content: const Text(
          'Are you sure you want to stop? Your race result will be marked as Did Not Finish (DNF).',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('RESUME RACING', style: TextStyle(color: AppColors.primaryGreen)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRose),
            child: const Text('ABANDON', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _flushGpsBatch();
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sport = _race?.sport ?? 'running';
    final isRunning = sport == 'running';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Telemetry Header (Authoritative Clock & GPS Accuracy)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: AppColors.backgroundSecondary,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _currentAccuracyM < 25 ? AppColors.statusOnline : AppColors.accentAmber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GPS: ${_currentAccuracyM.toStringAsFixed(1)}m',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    'LIVE ${sport.toUpperCase()} STAGE',
                    style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: AppColors.accentRose),
                    tooltip: 'Emergency Stop / Abandon',
                    onPressed: _abandonRace,
                  ),
                ],
              ),
            ),

            // Giant High-Contrast Timer Section
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Text('ELAPSED TIME', style: AppTypography.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    GeoUtils.formatDuration(_elapsed),
                    style: AppTypography.telemetryGiant,
                  ),
                ],
              ),
            ),

            // Live Performance Metrics Cards (Speed/Pace & Distance)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  // Metric 1: Velocity or Pace
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderHighlight),
                      ),
                      child: Column(
                        children: [
                          Text(isRunning ? 'PACE' : 'SPEED', style: AppTypography.labelSmall),
                          const SizedBox(height: 6),
                          Text(
                            isRunning
                                ? GeoUtils.formatRunningPace(_currentSpeedMps)
                                : '${GeoUtils.mpsToKmh(_currentSpeedMps).toStringAsFixed(1)} km/h',
                            style: AppTypography.telemetrySpeed,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Metric 2: Distance Covered
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderHighlight),
                      ),
                      child: Column(
                        children: [
                          const Text('DISTANCE', style: AppTypography.labelSmall),
                          const SizedBox(height: 6),
                          Text(
                            GeoUtils.formatDistance(_totalDistanceMeters),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Live Map & Competitor Standings Section
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // Stylized Live Vector Grid Map
                      CustomPaint(
                        size: Size.infinite,
                        painter: _LiveTrackPainter(
                          distanceM: _totalDistanceMeters,
                          participants: _race?.participants ?? [],
                        ),
                      ),

                      // Live Standings Overlay (Top Right)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('STANDINGS', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...(_race?.participants ?? []).take(3).map((p) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.circle, size: 8, color: AppColors.primaryCyan),
                                      const SizedBox(width: 6),
                                      Text(
                                        p.displayName,
                                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Bottom Finish Line Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ElevatedButton(
                onPressed: _finishRace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.textInverse,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flag_outlined, size: 24),
                    SizedBox(width: 8),
                    Text('CROSS FINISH LINE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Live Track & Competitor Marker Painter
class _LiveTrackPainter extends CustomPainter {
  final double distanceM;
  final List<RaceParticipant> participants;

  _LiveTrackPainter({required this.distanceM, required this.participants});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = const Color(0x3300E676)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;

    final userPaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.fill;

    // Draw stylized racing circuit track
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.8)
      ..lineTo(size.width * 0.8, size.height * 0.8)
      ..quadraticBezierTo(size.width * 0.9, size.height * 0.5, size.width * 0.8, size.height * 0.2)
      ..lineTo(size.width * 0.2, size.height * 0.2)
      ..quadraticBezierTo(size.width * 0.1, size.height * 0.5, size.width * 0.2, size.height * 0.8);

    canvas.drawPath(path, trackPaint);

    // Compute progress ratio along track (simulated course curve)
    final progress = ((distanceM / 1000.0) % 1.0);
    final userPos = Offset(
      size.width * (0.2 + 0.6 * progress),
      size.height * 0.8,
    );

    // Draw user glowing dot
    canvas.drawCircle(userPos, 8, userPaint);
    canvas.drawCircle(userPos, 14, Paint()..color = AppColors.primaryGreen.withOpacity(0.3)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _LiveTrackPainter oldDelegate) => true;
}
