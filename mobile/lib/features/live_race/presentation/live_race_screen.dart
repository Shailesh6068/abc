import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MapType;
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/core/security/gps_validator.dart';
import 'package:racezone/core/services/road_routing_service.dart';
import 'package:racezone/core/utils/geo_utils.dart';
import 'package:racezone/features/races/data/race_repository.dart';
import 'package:racezone/features/races/domain/race_model.dart';

class LiveRaceScreen extends ConsumerStatefulWidget {
  final String raceId;

  const LiveRaceScreen({super.key, required this.raceId});

  @override
  ConsumerState<LiveRaceScreen> createState() => _LiveRaceScreenState();
}

class _CompetitorPoint {
  final String name;
  final LatLng position;
  final double speedMps;

  _CompetitorPoint({
    required this.name,
    required this.position,
    required this.speedMps,
  });
}

class _LiveRaceScreenState extends ConsumerState<LiveRaceScreen> {
  RaceModel? _race;
  StreamSubscription<Position>? _positionStream;
  RealtimeChannel? _raceChannel;
  RealtimeChannel? _telemetryChannel;
  late GpsValidator _gpsValidator;

  GoogleMapController? _mapController;
  final List<LatLng> _myTrackPoints = [];
  final Map<String, _CompetitorPoint> _competitors = {};
  MapType _currentMapType = MapType.normal;

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
  Position? _startPosition;

  // Road Routing to Destination
  List<LatLng> _destinationRoutePoints = [];
  double? _liveRoadDistM;
  DateTime? _lastRouteFetchTime;

  bool _isDisposed = false;
  bool _isFinishing = false;

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
    _telemetryChannel?.unsubscribe();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeRace() async {
    final repo = ref.read(raceRepositoryProvider);
    try {
      var race = await repo.getRaceDetails(widget.raceId);
      if (_isDisposed) return;

      final currentUserId = SupabaseService.currentUser?.id;
      final isHost = race.creatorId == currentUserId;

      // Authoritative fallback: if host reaches live race while still in COUNTDOWN or WAITING, transition to IN_PROGRESS
      if (isHost && (race.status == 'COUNTDOWN' || race.status == 'WAITING')) {
        try {
          if (race.status == 'WAITING') {
            await repo.startRaceNow(widget.raceId);
          }
          await repo.transitionRaceState(widget.raceId, 'IN_PROGRESS');
          race = await repo.getRaceDetails(widget.raceId);
        } catch (e) {
          debugPrint('Live race transition fallback note: $e');
        }
      }

      setState(() {
        _race = race;
        _gpsValidator = GpsValidator(sport: race.sport);
        _raceStartTime = race.actualStartAt ?? DateTime.now();

        if (race.mode == 'destination_race') {
          final pts = race.configuration['route_points'] as List?;
          if (pts != null && pts.isNotEmpty) {
            _destinationRoutePoints = pts
                .map((p) {
                  final list = p as List;
                  return LatLng((list[0] as num).toDouble(), (list[1] as num).toDouble());
                })
                .toList();
          }
          final roadM = (race.configuration['road_distance_m'] as num?)?.toDouble();
          if (roadM != null) {
            _liveRoadDistM = roadM;
          }
        }
      });

      // Authoritative Ticker: updates elapsed time & checks time trial completion
      _tickerTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_raceStartTime != null && mounted) {
          final nowElapsed = DateTime.now().difference(_raceStartTime!);
          setState(() {
            _elapsed = nowElapsed;
          });

          // Time Trial auto-complete check
          if (_race?.mode == 'time_trial') {
            final durationMins = (_race?.configuration['duration_minutes'] as num?)?.toInt() ?? 5;
            final totalDuration = Duration(minutes: durationMins);
            if (nowElapsed >= totalDuration && !_isFinishing) {
              _finishRace();
            }
          }
        }
      });

      // Start continuous location stream
      _startGpsTracking();

      // Realtime sub-100ms telemetry broadcasting channel for live peer movement
      _initTelemetryBroadcast();


      // Batch submission every 3 seconds to backend anti-cheat
      _batchUploadTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _flushGpsBatch();
      });

      // Realtime subscription for race state updates & completion
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

  void _initTelemetryBroadcast() {
    try {
      _telemetryChannel = SupabaseService.client.channel('race_live_${widget.raceId}');
      _telemetryChannel!.onBroadcast(event: 'location_update', callback: (payload) {
        if (_isDisposed || !mounted) return;
        final String userId = payload['user_id']?.toString() ?? '';
        final myId = SupabaseService.currentUser?.id ?? '';

        // Skip echo of self
        if (userId.isNotEmpty && userId == myId) return;

        final double? lat = (payload['lat'] as num?)?.toDouble();
        final double? lng = (payload['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return;

        final String name = payload['name']?.toString() ?? 'Competitor';
        final double speed = (payload['speed'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _competitors[userId] = _CompetitorPoint(
            name: name,
            position: LatLng(lat, lng),
            speedMps: speed,
          );
        });
      }).subscribe();
    } catch (e) {
      debugPrint('Realtime telemetry channel error: $e');
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

      _startPosition ??= position;

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
        final currentLatLng = LatLng(position.latitude, position.longitude);

        setState(() {
          _currentAccuracyM = position.accuracy;
          _currentSpeedMps = position.speed >= 0 ? position.speed : report.calculatedSpeedMps;
          _totalDistanceMeters += report.distanceDeltaMeters;
          _lastValidPosition = position;
          _myTrackPoints.add(currentLatLng);
        });

        // Update road route to destination dynamically
        _updateDestinationRoadRoute(position);

        // Broadcast live movement to all competitors in race lobby
        try {
          _telemetryChannel?.sendBroadcastMessage(
            event: 'location_update',
            payload: {
              'user_id': SupabaseService.currentUser?.id ?? 'racer_local',
              'name': SupabaseService.currentUser?.userMetadata?['display_name'] ?? 'You',
              'lat': position.latitude,
              'lng': position.longitude,
              'speed': _currentSpeedMps,
            },
          );
        } catch (_) {}

        // Smooth camera follow
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(currentLatLng),
        );

        _pendingSamples.add({
          'sequence_no': _sequenceCounter,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_m': position.accuracy,
          'altitude_m': position.altitude,
          'recorded_at': position.timestamp.toIso8601String(),
          'speed_mps': _currentSpeedMps,
          'bearing_degrees': position.heading,
          'is_mocked': position.isMocked,
        });

        // Check auto-completion conditions:
        // 1. Distance Race: First to complete target distance wins
        if (_race?.mode == 'distance_race' || _race?.mode == 'head_to_head') {
          final targetDistance = (_race?.configuration['target_distance_m'] as num?)?.toDouble() ?? 1000.0;
          if (_totalDistanceMeters >= targetDistance && !_isFinishing) {
            _finishRace();
          }
        }

        // 2. Destination Race: First to reach within 35m of destination pin wins
        if (_race?.mode == 'destination_race') {
          final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble();
          final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble();
          if (destLat != null && destLng != null) {
            final distToDest = GeoUtils.haversineDistanceMeters(position.latitude, position.longitude, destLat, destLng);
            if (distToDest <= 35.0 && !_isFinishing) {
              _finishRace();
            }
          }
        }
      }
    });
  }

  Future<void> _flushGpsBatch() async {
    if (_pendingSamples.isEmpty || _isDisposed) return;

    final batchToUpload = List<Map<String, dynamic>>.from(_pendingSamples);
    _pendingSamples.clear();

    try {
      await SupabaseService.client.rpc('submit_gps_batch', params: {
        'p_race_id': widget.raceId,
        'p_samples': batchToUpload,
      });
    } catch (e) {
      if (!_isDisposed) {
        _pendingSamples.insertAll(0, batchToUpload);
      }
    }
  }

  Future<void> _finishRace() async {
    if (_isFinishing) return;
    _isFinishing = true;

    _positionStream?.cancel();
    _tickerTimer?.cancel();

    try {
      await _flushGpsBatch();
    } catch (e) {
      debugPrint('Flush GPS batch error: $e');
    }

    try {
      final repo = ref.read(raceRepositoryProvider);
      final elapsedMs = _elapsed.inMilliseconds;
      await repo.recordParticipantFinish(widget.raceId, elapsedMs, _totalDistanceMeters);
      await repo.transitionRaceState(widget.raceId, 'COMPLETED');
    } catch (e) {
      debugPrint('Participant finish update note: $e');
    }

    try {
      await SupabaseService.client.rpc('finalize_race_results', params: {
        'p_race_id': widget.raceId,
      });
    } catch (e) {
      debugPrint('Finalize RPC note: $e');
    }

    if (mounted) {
      context.go('/results/${widget.raceId}');
    }
  }

  Future<void> _abandonRace() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentRose.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: AppColors.accentRose, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Abandon Race?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
          ],
        ),
        content: const Text(
          'Leaving now will mark your status as DNF (Did Not Finish). Are you sure you want to quit?',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('RESUME RACE', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w800)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRose,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ABANDON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _flushGpsBatch();
      try {
        final repo = ref.read(raceRepositoryProvider);
        final currentUserId = SupabaseService.currentUser?.id;
        final isHost = _race?.creatorId == currentUserId || (_race?.participants.length ?? 0) <= 2;
        if (isHost || _race?.mode == 'head_to_head') {
          // Disband and stop the race completely so it never lingers
          await repo.cancelRace(widget.raceId);
        } else {
          await repo.leaveRace(widget.raceId);
        }
      } catch (e) {
        debugPrint('Abandon race note: $e');
      }
      if (mounted) context.go('/home');
    }
  }

  Set<Marker> _buildMapMarkers() {
    final Set<Marker> markers = {};

    // 1. My Current Marker (Green)
    if (_lastValidPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_position'),
          position: LatLng(_lastValidPosition!.latitude, _lastValidPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'You (${GeoUtils.mpsToKmh(_currentSpeedMps).toStringAsFixed(1)} km/h)',
            snippet: 'Distance: ${GeoUtils.formatDistance(_totalDistanceMeters)}',
          ),
        ),
      );
    }

    // 2. Real-time Competitors Markers (Cyan)
    _competitors.forEach((id, comp) {
      markers.add(
        Marker(
          markerId: MarkerId('competitor_$id'),
          position: comp.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: comp.name,
            snippet: '${GeoUtils.mpsToKmh(comp.speedMps).toStringAsFixed(1)} km/h',
          ),
        ),
      );
    });

    // 3. Destination Checkpoint Marker (Yellow / Gold) if destination_race
    if (_race?.mode == 'destination_race') {
      final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble() ?? 13.0850;
      final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble() ?? 80.2850;
      final destName = (_race?.configuration['destination_name'] as String?) ?? 'Destination Finish';

      markers.add(
        Marker(
          markerId: const MarkerId('destination_pin'),
          position: LatLng(destLat, destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: InfoWindow(
            title: '🏁 FINISH: $destName',
            snippet: 'Get within 35m to win!',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildMapCircles() {
    final Set<Circle> circles = {};

    if (_race?.mode == 'destination_race') {
      final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble() ?? 13.0850;
      final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble() ?? 80.2850;

      circles.add(
        Circle(
          circleId: const CircleId('dest_finish_zone'),
          center: LatLng(destLat, destLng),
          radius: 35.0,
          fillColor: AppColors.primaryGreen.withValues(alpha: 0.35),
          strokeColor: AppColors.primaryGreen,
          strokeWidth: 2,
        ),
      );
    }

    return circles;
  }

  Set<Polyline> _buildMapPolylines() {
    final Set<Polyline> polylines = {};

    if (_myTrackPoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('my_live_trail'),
          points: _myTrackPoints,
          color: AppColors.primaryGreen,
          width: 5,
        ),
      );
    }

    // Direction line to destination along real streets
    if (_race?.mode == 'destination_race') {
      final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble() ?? 13.0850;
      final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble() ?? 80.2850;

      final pts = _destinationRoutePoints.isNotEmpty
          ? _destinationRoutePoints
          : (_lastValidPosition != null
              ? [LatLng(_lastValidPosition!.latitude, _lastValidPosition!.longitude), LatLng(destLat, destLng)]
              : <LatLng>[]);

      if (pts.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('destination_road_guideline'),
            points: pts,
            color: AppColors.primaryCyan,
            width: 5,
          ),
        );
      }
    }

    return polylines;
  }

  Future<void> _updateDestinationRoadRoute(Position pos) async {
    if (_race?.mode != 'destination_race') return;
    final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble();
    final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble();
    if (destLat == null || destLng == null) return;

    final now = DateTime.now();
    if (_lastRouteFetchTime != null && now.difference(_lastRouteFetchTime!).inSeconds < 10) {
      return;
    }
    _lastRouteFetchTime = now;

    try {
      final res = await RoadRoutingService.getRoadRoute(
        start: LatLng(pos.latitude, pos.longitude),
        destination: LatLng(destLat, destLng),
        sport: _race?.sport ?? 'running',
      );
      if (!_isDisposed && mounted) {
        setState(() {
          _destinationRoutePoints = res.points;
          _liveRoadDistM = res.distanceMeters;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sport = _race?.sport ?? 'running';
    final isRunning = sport == 'running';
    final mode = _race?.mode ?? 'distance_race';

    final isDistanceRace = mode == 'distance_race' || mode == 'head_to_head';
    final isTimeTrial = mode == 'time_trial';
    final isDestinationRace = mode == 'destination_race';

    // 1. Target parameters
    final targetDistance = (_race?.configuration['target_distance_m'] as num?)?.toDouble() ?? 1000.0;
    final durationMins = (_race?.configuration['duration_minutes'] as num?)?.toInt() ?? 5;
    final totalDuration = Duration(minutes: durationMins);
    final remainingDuration = totalDuration - _elapsed;

    final destLat = (_race?.configuration['destination_lat'] as num?)?.toDouble() ?? 13.0850;
    final destLng = (_race?.configuration['destination_lng'] as num?)?.toDouble() ?? 80.2850;
    final destName = (_race?.configuration['destination_name'] as String?) ?? 'Checkpoint Finish';
    final straightDist = _lastValidPosition != null
        ? GeoUtils.haversineDistanceMeters(_lastValidPosition!.latitude, _lastValidPosition!.longitude, destLat, destLng)
        : 1000.0;
    final distToDest = _liveRoadDistM ?? straightDist;

    // 2. Completion Check & Button Text
    bool isCompleted = false;
    String buttonText = '';
    double progressPercent = 0.0;

    if (isDistanceRace) {
      progressPercent = (_totalDistanceMeters / targetDistance).clamp(0.0, 1.0);
      isCompleted = _totalDistanceMeters >= targetDistance;
      final metersLeft = (targetDistance - _totalDistanceMeters).clamp(0.0, targetDistance).toInt();
      buttonText = isCompleted
          ? 'CROSS FINISH LINE (100% COMPLETE)'
          : 'LOCKED: SPRINT ${metersLeft}m MORE TO FINISH';
    } else if (isTimeTrial) {
      isCompleted = remainingDuration <= Duration.zero;
      final displaySecs = remainingDuration.isNegative ? Duration.zero : remainingDuration;
      progressPercent = (_elapsed.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0);
      buttonText = isCompleted
          ? 'TIME EXPIRED • SUBMIT FINAL DISTANCE'
          : 'LOCKED: ${GeoUtils.formatDuration(displaySecs)} REMAINING (RUN FOR MAX DIST)';
    } else if (isDestinationRace) {
      isCompleted = straightDist <= 35.0 || (_liveRoadDistM != null && _liveRoadDistM! <= 35.0);
      progressPercent = isCompleted ? 1.0 : (1.0 - (distToDest / 2000.0)).clamp(0.0, 0.95);
      buttonText = isCompleted
          ? 'DESTINATION REACHED! CROSS FINISH LINE'
          : 'LOCKED: ${distToDest.toInt()}m TO FINISH PIN (GET WITHIN 35m)';
    }

    final initialTarget = _lastValidPosition != null
        ? LatLng(_lastValidPosition!.latitude, _lastValidPosition!.longitude)
        : const LatLng(13.0827, 80.2707);

    // Compute Position / Rank (#1 ST, #2 ND) and Live Rival Split Gap
    int myRank = 1;
    String rivalGapText = 'MAINTAIN MAXIMUM ACCELERATION';
    LinearGradient gapGradient = AppColors.greenGradient;
    Color gapBorderColor = AppColors.primaryGreen;

    if (_competitors.isNotEmpty) {
      final compList = _competitors.values.toList();
      double maxCompDist = 0.0;
      String leadCompName = '';
      for (final c in compList) {
        if (_startPosition != null) {
          final cDist = GeoUtils.haversineDistanceMeters(
            _startPosition!.latitude,
            _startPosition!.longitude,
            c.position.latitude,
            c.position.longitude,
          );
          if (cDist > maxCompDist) {
            maxCompDist = cDist;
            leadCompName = c.name;
          }
        }
      }

      if (_totalDistanceMeters >= maxCompDist) {
        myRank = 1;
        final leadMeters = (_totalDistanceMeters - maxCompDist).toInt();
        rivalGapText = leadMeters > 5
            ? '⚡ YOU LEAD BY +${leadMeters}m AHEAD OF ${leadCompName.toUpperCase()}'
            : '⚡ YOU ARE IN P1 • HOLD YOUR LEAD!';
        gapGradient = AppColors.greenGradient;
        gapBorderColor = AppColors.primaryGreen;
      } else {
        myRank = 2;
        final trailMeters = (maxCompDist - _totalDistanceMeters).toInt();
        rivalGapText = '🔥 CHASE RIVAL: ${trailMeters}m TO OVERTAKE ${leadCompName.toUpperCase()}!';
        gapGradient = AppColors.fireGradient;
        gapBorderColor = AppColors.accentRose;
      }
    } else {
      if (isDistanceRace) {
        final left = (targetDistance - _totalDistanceMeters).clamp(0.0, targetDistance).toInt();
        rivalGapText = '⚡ SPRINT $left METERS TO CROSS FINISH LINE';
      } else if (isTimeTrial) {
        rivalGapText = '⚡ RUN FOR MAXIMUM DISTANCE • BEAT THE RECORD';
      } else {
        rivalGapText = '⚡ TARGET: REACH $destName FINISH PIN';
      }
      gapGradient = AppColors.cyanGradient;
      gapBorderColor = AppColors.primaryCyan;
    }

    final isFirst = myRank == 1;
    final rankGradient = isFirst ? AppColors.metallicGold : AppColors.metallicSilver;
    final rankLabel = isFirst ? '1ST' : '2ND';
    final rankTitle = isFirst ? 'LEADER' : 'CHASER';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Cockpit Header: Metallic Position Shield + Mode Capsule + Emergency Abort
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.backgroundSecondary,
                border: Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1)),
              ),
              child: Row(
                children: [
                  // Metallic Position Shield Badge (#1 ST or #2 ND)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: rankGradient,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: (isFirst ? AppColors.gold : AppColors.silver).withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#$rankLabel',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rankTitle,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Mode & GPS Satellite Capsule
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isDistanceRace
                              ? 'DISTANCE SPEEDWAY'
                              : (isTimeTrial ? 'TIME TRIAL ARENA' : 'DESTINATION RALLY'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentAccuracyM < 25 ? AppColors.statusOnline : AppColors.accentAmber,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_currentAccuracyM < 25 ? AppColors.statusOnline : AppColors.accentAmber)
                                        .withValues(alpha: 0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'GPS LOCK ${_currentAccuracyM.toStringAsFixed(1)}m',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Emergency Eject / Abandon Cockpit Button
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accentRose.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accentRose.withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.power_settings_new, color: AppColors.accentRose, size: 18),
                    ),
                    tooltip: 'Emergency Abort Race',
                    onPressed: _abandonRace,
                  ),
                ],
              ),
            ),

            // 2. High-Tech Speedometer & Telemetry Instrument Panel
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF142037), Color(0xFF0C1322)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.35), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryCyan.withValues(alpha: 0.1),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Sub-Meter 1: Race Chronometer
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTimeTrial ? 'TIME REMAINING' : 'ELAPSED TIME',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isTimeTrial
                                  ? GeoUtils.formatDuration(remainingDuration.isNegative ? Duration.zero : remainingDuration)
                                  : GeoUtils.formatDuration(_elapsed),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                color: isTimeTrial
                                    ? (remainingDuration.inSeconds <= 60 ? AppColors.accentRose : AppColors.accentAmber)
                                    : AppColors.timerGlow,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center: Giant Glowing Speedometer Digit
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                isRunning
                                    ? GeoUtils.formatRunningPace(_currentSpeedMps)
                                    : GeoUtils.mpsToKmh(_currentSpeedMps).toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isRunning ? 'PACE' : 'KM/H',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primaryCyan,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isRunning
                                ? (_currentSpeedMps < 0.8 ? 'STATIONARY' : 'SPRINT PACE')
                                : 'VELOCITY',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),

                      // Sub-Meter 2: Distance Progress
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isDestinationRace ? 'TO FINISH' : 'DISTANCE',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDestinationRace
                                  ? GeoUtils.formatDistance(distToDest)
                                  : GeoUtils.formatDistance(_totalDistanceMeters),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Tachometer Speed LED Bar (10 Segment Illuminated Meter)
                  Row(
                    children: List.generate(10, (idx) {
                      final speedNormalized = (GeoUtils.mpsToKmh(_currentSpeedMps) / (isRunning ? 25.0 : 60.0)).clamp(0.0, 1.0);
                      final isActive = idx < (speedNormalized * 10).ceil();
                      Color cellColor;
                      if (idx < 3) {
                        cellColor = AppColors.primaryCyan;
                      } else if (idx < 6) {
                        cellColor = AppColors.primaryGreen;
                      } else if (idx < 8) {
                        cellColor = AppColors.accentAmber;
                      } else {
                        cellColor = AppColors.accentRose;
                      }

                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isActive ? cellColor : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: cellColor.withValues(alpha: 0.6),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            // 3. Dynamic Live Rival Split / Gap Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: gapGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: gapBorderColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(isFirst ? Icons.stars : Icons.local_fire_department, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rivalGapText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 4. Live Interactive Google Map with Cockpit HUD Framing & Competitors
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Google Maps Engine
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: initialTarget,
                          zoom: 17,
                        ),
                        mapType: _currentMapType,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: true,
                        markers: _buildMapMarkers(),
                        circles: _buildMapCircles(),
                        polylines: _buildMapPolylines(),
                        onMapCreated: (ctrl) {
                          _mapController = ctrl;
                        },
                      ),

                      // Corner HUD Brackets
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Text('┌', style: TextStyle(color: AppColors.primaryGreen.withValues(alpha: 0.8), fontSize: 20, fontFamily: 'monospace')),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Text('┐', style: TextStyle(color: AppColors.primaryGreen.withValues(alpha: 0.8), fontSize: 20, fontFamily: 'monospace')),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Text('└', style: TextStyle(color: AppColors.primaryGreen.withValues(alpha: 0.8), fontSize: 20, fontFamily: 'monospace')),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Text('┘', style: TextStyle(color: AppColors.primaryGreen.withValues(alpha: 0.8), fontSize: 20, fontFamily: 'monospace')),
                      ),

                      // Floating Map Controls
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'recenter_cam',
                              backgroundColor: AppColors.surfaceElevated,
                              child: const Icon(Icons.my_location, color: AppColors.primaryGreen),
                              onPressed: () {
                                if (_lastValidPosition != null) {
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLng(
                                      LatLng(_lastValidPosition!.latitude, _lastValidPosition!.longitude),
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'toggle_layer',
                              backgroundColor: AppColors.surfaceElevated,
                              child: Icon(
                                _currentMapType == MapType.normal ? Icons.satellite_alt : Icons.map,
                                color: AppColors.primaryCyan,
                              ),
                              onPressed: () {
                                setState(() {
                                  _currentMapType = _currentMapType == MapType.normal
                                      ? MapType.satellite
                                      : MapType.normal;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // Live Standings Overlay (Top Right)
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.5)),
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.radar, size: 13, color: AppColors.primaryGreen),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${1 + _competitors.length} RACERS LIVE',
                                    style: const TextStyle(color: AppColors.primaryGreen, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              ...(_race?.participants ?? []).take(3).map((p) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.circle, size: 6, color: AppColors.primaryCyan),
                                      const SizedBox(width: 5),
                                      Text(
                                        p.displayName,
                                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 8),

            // 5. Checkered Flag Race Progress Highway
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🏁 START',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${(progressPercent * 100).toInt()}% • ${isDistanceRace ? "${(targetDistance - _totalDistanceMeters).clamp(0, targetDistance).toInt()}m LEFT" : "IN PROGRESS"}',
                        style: const TextStyle(color: AppColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                      const Text(
                        'FINISH 🏁',
                        style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progressPercent,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted ? AppColors.primaryGreen : AppColors.primaryCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 6. Cockpit Finish Line Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  gradient: isCompleted ? AppColors.greenGradient : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isCompleted ? AppColors.greenGlowShadow : null,
                ),
                child: ElevatedButton(
                  onPressed: isCompleted ? _finishRace : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCompleted ? Colors.transparent : AppColors.surfaceElevated,
                    foregroundColor: isCompleted ? Colors.black : AppColors.textMuted,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: AppColors.surfaceElevated,
                    disabledForegroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isCompleted ? Colors.transparent : AppColors.borderSubtle,
                        width: isCompleted ? 0 : 1.0,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isCompleted ? Icons.emoji_events : Icons.lock_outline,
                        size: 20,
                        color: isCompleted ? Colors.black : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          buttonText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: isCompleted ? Colors.black : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
