import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/core/utils/geo_utils.dart';
import 'package:racezone/features/races/data/race_repository.dart';
import 'package:racezone/features/races/presentation/destination_map_picker_screen.dart';

class CreateRaceScreen extends ConsumerStatefulWidget {
  final String? challengeUserId;
  final String? challengeUserName;

  const CreateRaceScreen({
    super.key,
    this.challengeUserId,
    this.challengeUserName,
  });

  @override
  ConsumerState<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends ConsumerState<CreateRaceScreen> {
  String _selectedSport = 'running';
  String _selectedMode = 'distance_race'; // distance_race, time_trial, destination_race
  int _participantLimit = 4;
  int _durationMinutes = 5;
  int _targetDistanceM = 1000;
  String _visibility = 'public';
  bool _isCreating = false;
  Position? _userPosition;

  // Custom Destination state
  bool _isCustomDestination = false;
  LatLng? _customDestinationLatLng;
  String _customDestinationName = 'Custom Map Finish Point';
  double _customDestinationDistanceM = 1000.0;
  List<LatLng>? _customRoutePoints;

  // Preset Destination Options
  int _selectedDestinationIndex = 0;
  final List<Map<String, dynamic>> _destinationOptions = [
    {
      'name': 'Marina Lighthouse Checkpoint',
      'label': 'Sprint to Lighthouse (1.0 km)',
      'distance_m': 1000,
      'lat_offset': 0.0075,
      'lng_offset': 0.0055,
    },
    {
      'name': 'Promenade Pier Checkpoint',
      'label': 'Coastal Pier Finish (2.5 km)',
      'distance_m': 2500,
      'lat_offset': 0.0180,
      'lng_offset': 0.0095,
    },
    {
      'name': 'Apex Speedway Arch',
      'label': 'Speedway North Arch (4.0 km)',
      'distance_m': 4000,
      'lat_offset': 0.0310,
      'lng_offset': 0.0160,
    },
  ];

  final Map<String, String> _sampleRoutes = {
    '11111111-1111-1111-1111-111111111111': 'Marina Beach Sprint Circuit (1.0 km)',
    '22222222-2222-2222-2222-222222222222': 'Coastal Highway Loop (5.0 km)',
    '33333333-3333-3333-3333-333333333333': 'Apex Speedway Closed Track (3.2 km)',
  };
  late String _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _selectedRouteId = _sampleRoutes.keys.first;
    if (widget.challengeUserId != null) {
      _selectedMode = 'head_to_head';
      _participantLimit = 2;
      _visibility = 'invitation_only';
    }
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && mounted) {
        setState(() => _userPosition = cached);
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {}
  }

  Future<void> _openMapPicker() async {
    final baseLat = _userPosition?.latitude ?? 13.0827;
    final baseLng = _userPosition?.longitude ?? 80.2707;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationMapPickerScreen(
          initialUserLocation: LatLng(baseLat, baseLng),
          initialTargetLocation: _customDestinationLatLng,
          initialName: _customDestinationName,
          sport: _selectedSport,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _isCustomDestination = true;
        _customDestinationLatLng = LatLng((result['lat'] as num).toDouble(), (result['lng'] as num).toDouble());
        _customDestinationName = result['name'] as String;
        _customDestinationDistanceM = (result['distance_m'] as num).toDouble();
        final rawPts = result['route_points'] as List?;
        if (rawPts != null) {
          _customRoutePoints = rawPts
              .map((p) {
                final list = p as List;
                return LatLng((list[0] as num).toDouble(), (list[1] as num).toDouble());
              })
              .toList();
        }
      });
    }
  }

  Future<void> _handleCreateRace() async {
    setState(() => _isCreating = true);
    try {
      if (!SupabaseService.isAuthenticated) {
        try {
          await SupabaseService.client.auth.signInAnonymously();
        } catch (_) {
          try {
            final testEmail = 'guest_${DateTime.now().millisecondsSinceEpoch}@racezone.com';
            await SupabaseService.client.auth.signUp(
              email: testEmail,
              password: 'RaceZoneGuestPass123!',
              data: {'display_name': 'Racer_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'},
            );
          } catch (authErr) {
            debugPrint('Auto-auth note: $authErr');
          }
        }
      }

      final baseLat = _userPosition?.latitude ?? 13.0827;
      final baseLng = _userPosition?.longitude ?? 80.2707;

      double destLat;
      double destLng;
      String destName;
      String courseName;

      double? roadDistanceM;
      if (_selectedMode == 'destination_race') {
        if (_isCustomDestination && _customDestinationLatLng != null) {
          destLat = _customDestinationLatLng!.latitude;
          destLng = _customDestinationLatLng!.longitude;
          destName = _customDestinationName;
          courseName = 'Sprint to $destName';
          roadDistanceM = _customDestinationDistanceM;
        } else {
          final selDest = _destinationOptions[_selectedDestinationIndex];
          destLat = baseLat + (selDest['lat_offset'] as double);
          destLng = baseLng + (selDest['lng_offset'] as double);
          destName = selDest['name'] as String;
          courseName = 'Sprint to $destName';
          roadDistanceM = (selDest['distance_m'] as num).toDouble();
        }
      } else if (_selectedMode == 'distance_race') {
        destLat = baseLat;
        destLng = baseLng;
        destName = 'Distance Sprint';
        courseName = '${GeoUtils.formatDistance(_targetDistanceM.toDouble())} Distance Sprint';
      } else {
        destLat = baseLat;
        destLng = baseLng;
        destName = 'Time Challenge';
        courseName = '$_durationMinutes Min Time Challenge';
      }

      final repo = ref.read(raceRepositoryProvider);
      final isChallenge = widget.challengeUserId != null;
      final raceId = await repo.createRace(
        sport: _selectedSport,
        mode: isChallenge ? 'head_to_head' : _selectedMode,
        visibility: isChallenge ? 'invitation_only' : _visibility,
        participantLimit: isChallenge ? 2 : _participantLimit,
        routeId: _selectedRouteId,
        configuration: {
          'course_name': courseName,
          'duration_minutes': _selectedMode == 'time_trial' ? _durationMinutes : null,
          'target_distance_m': (_selectedMode == 'distance_race' || isChallenge) ? _targetDistanceM : null,
          'destination_lat': _selectedMode == 'destination_race' ? destLat : null,
          'destination_lng': _selectedMode == 'destination_race' ? destLng : null,
          'destination_name': _selectedMode == 'destination_race' ? destName : null,
          'destination_radius_m': _selectedMode == 'destination_race' ? 35 : null,
          'road_distance_m': _selectedMode == 'destination_race' ? roadDistanceM : null,
          'route_points': _selectedMode == 'destination_race' && _customRoutePoints != null
              ? _customRoutePoints!.map((p) => [p.latitude, p.longitude]).toList()
              : null,
          'challengee_id': widget.challengeUserId,
          'challengee_name': widget.challengeUserName,
        },
      );

      // If challenging a user, dispatch race_invitations record
      if (isChallenge) {
        final currentUserId = SupabaseService.currentUser?.id;
        if (currentUserId != null) {
          await SupabaseService.client.from('race_invitations').insert({
            'race_id': raceId,
            'inviter_id': currentUserId,
            'invitee_id': widget.challengeUserId,
            'status': 'pending',
          });
        }
      }

      if (mounted) {
        final query = widget.challengeUserName != null
            ? '?challengeTarget=${Uri.encodeComponent(widget.challengeUserName!)}'
            : '';
        context.go('/lobby/$raceId$query');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accentRose,
            content: Text('Failed to create race: ${e.toString().replaceAll('Exception:', '').trim()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                gradient: AppColors.greenGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_road, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              'HOST A RACE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.challengeUserName != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.5)),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sports_kabaddi, color: AppColors.primaryCyan, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DIRECT 1v1 CHALLENGE', style: TextStyle(color: AppColors.primaryCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                            Text(
                              'Versus ${widget.challengeUserName}',
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 1. Sport Selection
              _buildSectionHeader('DISCIPLINE', Icons.sports, AppColors.primaryGreen),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSportOption('running', 'Running', Icons.directions_run),
                  const SizedBox(width: 10),
                  _buildSportOption('cycling', 'Cycling', Icons.directions_bike),
                  const SizedBox(width: 10),
                  _buildSportOption('motorbike', 'Motorbike', Icons.two_wheeler),
                ],
              ),
              const SizedBox(height: 24),

              // 2. Race Mode Selection (3 Distinct Modes)
              _buildSectionHeader('RACE TYPE & VICTORY CONDITION', Icons.flag_outlined, AppColors.primaryCyan),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildModeOption('distance_race', 'Distance\nSprint', Icons.straighten),
                  const SizedBox(width: 10),
                  _buildModeOption('time_trial', 'Time\nChallenge', Icons.timer_outlined),
                  const SizedBox(width: 10),
                  _buildModeOption('destination_race', 'Destination\nRace', Icons.flag_outlined),
                ],
              ),
              const SizedBox(height: 12),

              // Mode Rule Explanation Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _selectedMode == 'distance_race'
                            ? Icons.straighten
                            : (_selectedMode == 'time_trial' ? Icons.timer : Icons.flag),
                        color: AppColors.primaryGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedMode == 'distance_race'
                            ? 'Distance Race: First racer to complete target distance wins!'
                            : (_selectedMode == 'time_trial'
                                ? 'Time Challenge: Racer who covers the most distance in the time wins!'
                                : 'Destination Race: First racer to reach destination checkpoint wins!'),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.3, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. Mode Specific Parameters
              if (_selectedMode == 'distance_race') ...[
                _buildSectionHeader('TARGET SPRINT DISTANCE', Icons.speed, AppColors.primaryGreen),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [500, 1000, 2000, 3000, 5000].map((dist) {
                      final isSel = _targetDistanceM == dist;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _targetDistanceM = dist);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primaryGreen : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? AppColors.primaryGreen : AppColors.borderSubtle,
                                width: isSel ? 1.5 : 1.0,
                              ),
                              boxShadow: isSel ? AppColors.greenGlowShadow : AppColors.cardShadow,
                            ),
                            child: Text(
                              dist < 1000 ? '${dist}m' : '${(dist / 1000).toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: isSel ? Colors.black : AppColors.textPrimary,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('SANCTIONED COURSE / TRACK', Icons.route_outlined, AppColors.textMuted),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRouteId,
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      items: _sampleRoutes.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRouteId = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else if (_selectedMode == 'time_trial') ...[
                _buildSectionHeader('TIME LIMIT (MOST DISTANCE WINS)', Icons.timer, AppColors.primaryGreen),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [3, 5, 10, 15, 30].map((mins) {
                      final isSel = _durationMinutes == mins;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _durationMinutes = mins);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primaryGreen : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? AppColors.primaryGreen : AppColors.borderSubtle,
                                width: isSel ? 1.5 : 1.0,
                              ),
                              boxShadow: isSel ? AppColors.greenGlowShadow : AppColors.cardShadow,
                            ),
                            child: Text(
                              '$mins Mins',
                              style: TextStyle(
                                color: isSel ? Colors.black : AppColors.textPrimary,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('SANCTIONED COURSE / TRACK', Icons.route_outlined, AppColors.textMuted),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRouteId,
                      dropdownColor: AppColors.surface,
                      isExpanded: true,
                      items: _sampleRoutes.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRouteId = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else if (_selectedMode == 'destination_race') ...[
                _buildSectionHeader('DESTINATION CHECKPOINT', Icons.flag, AppColors.primaryCyan),
                const SizedBox(height: 10),

                // FEATURE: Pick Custom Location from Interactive Google Map
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isCustomDestination ? AppColors.primaryGreen : AppColors.borderSubtle,
                      width: _isCustomDestination ? 2 : 1,
                    ),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryCyan.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_location_alt, color: AppColors.primaryCyan, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Custom Destination On Map',
                                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isCustomDestination
                                      ? 'Selected: $_customDestinationName (${GeoUtils.formatDistance(_customDestinationDistanceM)})'
                                      : 'Tap on Google Map to set any custom finish pin',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          gradient: _isCustomDestination ? AppColors.greenGradient : null,
                          borderRadius: BorderRadius.circular(12),
                          border: _isCustomDestination ? null : Border.all(color: AppColors.primaryCyan),
                          boxShadow: _isCustomDestination ? AppColors.greenGlowShadow : null,
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _openMapPicker,
                          icon: Icon(Icons.map, size: 18, color: _isCustomDestination ? Colors.black : AppColors.primaryCyan),
                          label: Text(
                            _isCustomDestination ? 'CHANGE PIN ON GOOGLE MAP' : '📍 TAP TO PICK ON GOOGLE MAP',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                              color: _isCustomDestination ? Colors.black : AppColors.primaryCyan,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isCustomDestination ? Colors.transparent : AppColors.surfaceElevated,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildSectionHeader('OR CHOOSE SANCTIONED CHECKPOINT', Icons.check_circle_outline, AppColors.textMuted),
                const SizedBox(height: 10),

                Column(
                  children: List.generate(_destinationOptions.length, (idx) {
                    final dest = _destinationOptions[idx];
                    final isSel = !_isCustomDestination && _selectedDestinationIndex == idx;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _isCustomDestination = false;
                            _selectedDestinationIndex = idx;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.primaryCyan.withValues(alpha: 0.08) : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSel ? AppColors.primaryCyan : AppColors.borderSubtle,
                              width: isSel ? 2 : 1,
                            ),
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSel ? Icons.check_circle : Icons.flag_circle_outlined,
                                color: isSel ? AppColors.primaryCyan : AppColors.textMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dest['name'] as String,
                                      style: TextStyle(
                                        color: isSel ? AppColors.primaryCyan : AppColors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Target: ${dest['label']} • Finish zone: 35m',
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
              ],

              // 4. Participant Limit
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader('RACER LIMIT', Icons.people_outline, AppColors.primaryGreen),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '$_participantLimit racers max',
                      style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: _participantLimit.toDouble(),
                min: 2,
                max: 12,
                divisions: 10,
                activeColor: AppColors.primaryGreen,
                inactiveColor: AppColors.borderSubtle,
                onChanged: (val) => setState(() => _participantLimit = val.toInt()),
              ),
              const SizedBox(height: 20),

              // 5. Visibility
              _buildSectionHeader('LOBBY ACCESS', Icons.visibility_outlined, AppColors.primaryCyan),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _visibility = 'public'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _visibility == 'public' ? AppColors.primaryGreen.withValues(alpha: 0.08) : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _visibility == 'public' ? AppColors.primaryGreen : AppColors.borderSubtle,
                            width: _visibility == 'public' ? 2 : 1,
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _visibility == 'public' ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: _visibility == 'public' ? AppColors.primaryGreen : AppColors.textMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text('Public Arena', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _visibility = 'invitation_only'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _visibility == 'invitation_only' ? AppColors.primaryGreen.withValues(alpha: 0.08) : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _visibility == 'invitation_only' ? AppColors.primaryGreen : AppColors.borderSubtle,
                            width: _visibility == 'invitation_only' ? 2 : 1,
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _visibility == 'invitation_only' ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: _visibility == 'invitation_only' ? AppColors.primaryGreen : AppColors.textMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text('Invite Only', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // 6. Create Action
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: AppColors.greenGradient,
                  boxShadow: AppColors.greenGlowShadow,
                ),
                child: ElevatedButton(
                  onPressed: _isCreating
                      ? null
                      : () {
                          HapticFeedback.heavyImpact();
                          _handleCreateRace();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isCreating
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch, size: 22, color: Colors.black),
                            SizedBox(width: 10),
                            Text(
                              'LAUNCH RACE LOBBY',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.black),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildSportOption(String id, String label, IconData icon) {
    final isSel = _selectedSport == id;
    Color accentColor;

    switch (id) {
      case 'running':
        accentColor = AppColors.primaryGreen;
        break;
      case 'cycling':
        accentColor = AppColors.primaryCyan;
        break;
      case 'motorbike':
      default:
        accentColor = const Color(0xFFFF6D00);
        break;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedSport = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isSel ? accentColor.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSel ? accentColor : AppColors.borderSubtle,
              width: isSel ? 2.0 : 1.0,
            ),
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppColors.cardShadow,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSel ? accentColor.withValues(alpha: 0.18) : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: isSel ? accentColor : AppColors.textSecondary, size: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSel ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSel)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(String id, String label, IconData icon) {
    final isSel = _selectedMode == id;
    const accentColor = AppColors.primaryCyan;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedMode = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: BoxDecoration(
            color: isSel ? accentColor.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSel ? accentColor : AppColors.borderSubtle,
              width: isSel ? 2.0 : 1.0,
            ),
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppColors.cardShadow,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: isSel ? accentColor.withValues(alpha: 0.18) : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 22, color: isSel ? accentColor : AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSel ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSel)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
