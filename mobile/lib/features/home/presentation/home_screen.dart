import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/features/ads/widgets/ad_banner_widget.dart';
import 'package:racezone/features/discovery/data/discovery_repository.dart';
import 'package:racezone/features/discovery/domain/player_model.dart';
import 'package:racezone/features/races/data/race_repository.dart';
import 'package:racezone/features/races/domain/race_model.dart';

class DisciplineItem {
  final String id;
  final String title;
  final String category;
  final IconData icon;
  final LinearGradient activeGradient;
  final Color accentColor;
  final bool isCustom;

  const DisciplineItem({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    required this.activeGradient,
    required this.accentColor,
    this.isCustom = false,
  });
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  Position? _currentPosition;
  String _selectedSport = 'running';
  int _searchRadiusM = 1000; // 1km default radius for practical discovery
  List<NearbyPlayer> _nearbyPlayers = [];
  List<RaceModel> _openRaces = [];
  RaceModel? _myActiveLobby;
  bool _isLoading = false;
  String? _locationStatusMessage;
  bool _isLocationError = false;
  Timer? _refreshTimer;
  StreamSubscription<Position>? _positionStreamSub;
  late TabController _tabController;
  late AnimationController _sweepController;
  late AnimationController _pulseController;

  int _radarSubTab = 0; // 0: Nearby Racers, 1: Hosted Rooms
  RealtimeChannel? _invitationsChannel;
  String? _lastDismissedInviteId;
  bool _isShowingChallengeDialog = false;

  final List<int> _radii = [100, 250, 500, 1000, 2500, 5000, 10000];
  late List<DisciplineItem> _disciplines;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _disciplines = [
      const DisciplineItem(
        id: 'all',
        title: 'ALL ARENA',
        category: 'OMNI RADAR',
        icon: Icons.explore,
        activeGradient: AppColors.purpleGradient,
        accentColor: AppColors.accentPurple,
      ),
      const DisciplineItem(
        id: 'running',
        title: 'STREET SPRINT',
        category: '0-30 KM/H',
        icon: Icons.directions_run,
        activeGradient: AppColors.greenGradient,
        accentColor: AppColors.primaryGreen,
      ),
      const DisciplineItem(
        id: 'cycling',
        title: 'VELOCITY TOUR',
        category: '0-60 KM/H',
        icon: Icons.directions_bike,
        activeGradient: AppColors.cyanGradient,
        accentColor: AppColors.primaryCyan,
      ),
      const DisciplineItem(
        id: 'motorbike',
        title: 'HYPER SPEEDWAY',
        category: 'NITRO CLASS',
        icon: Icons.two_wheeler,
        activeGradient: AppColors.orangeGradient,
        accentColor: AppColors.sportMotorbike,
      ),
    ];
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _initLocationAndFetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshData());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocationAndFetch();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _positionStreamSub?.cancel();
    _invitationsChannel?.unsubscribe();
    _tabController.dispose();
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startQuickSprint() async {
    HapticFeedback.heavyImpact();
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(raceRepositoryProvider);
      final sport = (_selectedSport == 'all') ? 'running' : _selectedSport;
      final raceId = await repo.createRace(
        sport: sport,
        mode: 'distance_race',
        participantLimit: 4,
        configuration: {
          'target_distance_m': 1000,
          'course_name': 'Instant Sprint Circuit (1.0 km)',
        },
      );
      if (!mounted) return;
      context.push('/lobby/$raceId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quick match note: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Verifies location service and prompts for permissions if not granted
  Future<bool> _checkAndRequestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationStatusMessage = 'Location Service is off. Tap here to enable GPS.';
            _isLocationError = true;
          });
        }
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationStatusMessage = 'Location permission is denied. Tap to grant access.';
              _isLocationError = true;
            });
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationStatusMessage = 'Location permission permanently denied. Tap to open Settings.';
            _isLocationError = true;
          });
        }
        return false;
      }

      if (mounted) {
        setState(() {
          _locationStatusMessage = null;
          _isLocationError = false;
        });
      }
      return true;
    } catch (e) {
      debugPrint('[Location] Permission check note: $e');
      return false;
    }
  }

  /// Listens continuously to device position changes
  void _startPositionStream() {
    _positionStreamSub?.cancel();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Triggers every 5 meters
    );

    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        if (!mounted) return;
        final wasNull = _currentPosition == null;
        setState(() {
          _currentPosition = position;
          _locationStatusMessage = null;
          _isLocationError = false;
        });
        if (wasNull) {
          _refreshData();
        }
      },
      onError: (e) {
        debugPrint('[Location] Stream error: $e');
      },
    );
  }

  Future<void> _initLocationAndFetch() async {
    setState(() => _isLoading = true);
    try {
      final hasPermission = await _checkAndRequestLocationPermission();

      if (hasPermission) {
        _startPositionStream();

        // 1. Instant fix from cached last known position
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null && mounted) {
          setState(() {
            _currentPosition = cached;
            _locationStatusMessage = null;
            _isLocationError = false;
          });
          await _refreshData();
        }

        // 2. Fresh high-accuracy satellite fix
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8),
          );
          if (mounted) {
            setState(() {
              _currentPosition = pos;
              _locationStatusMessage = null;
              _isLocationError = false;
            });
          }
        } catch (posErr) {
          debugPrint('High accuracy GPS timeout/fallback note: $posErr');
        }
      }

      _setupInvitationListener();
      await _refreshData();
    } catch (e) {
      debugPrint('Location initialization note: $e');
      await _refreshData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupInvitationListener() {
    final currentUserId = SupabaseService.currentUser?.id;
    if (currentUserId == null) return;

    _invitationsChannel?.unsubscribe();
    _invitationsChannel = SupabaseService.client
        .channel('public:race_invitations:$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invitee_id',
            value: currentUserId,
          ),
          callback: (payload) {
            debugPrint('[Duel] Received invitation realtime event: ${payload.eventType}');
            _checkPendingInvitations();
          },
        )
        .subscribe();
  }

  Future<void> _checkPendingInvitations() async {
    if (_isShowingChallengeDialog || !mounted) return;
    final currentUserId = SupabaseService.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final list = await SupabaseService.client
          .from('race_invitations')
          .select('*, profiles:inviter_id(display_name), races:race_id(sport, mode, status, configuration)')
          .eq('invitee_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);

      if (list.isNotEmpty && mounted && !_isShowingChallengeDialog) {
        final inv = list.first;
        final inviteId = inv['id'] as String;
        if (_lastDismissedInviteId == inviteId) return;

        _showIncomingDuelDialog(inv);
      }
    } catch (e) {
      debugPrint('[Duel] Check invitations note: $e');
    }
  }

  void _showIncomingDuelDialog(Map<String, dynamic> inv) {
    if (_isShowingChallengeDialog || !mounted) return;
    _isShowingChallengeDialog = true;
    HapticFeedback.heavyImpact();

    final inviteId = inv['id'] as String;
    final raceId = inv['race_id'] as String;
    final inviterProfile = inv['profiles'] as Map<String, dynamic>?;
    final inviterName = inviterProfile?['display_name'] ?? 'Nearby Racer';
    final raceData = inv['races'] as Map<String, dynamic>?;
    final raceConfig = raceData?['configuration'] as Map<String, dynamic>?;
    final distM = (raceConfig?['target_distance_m'] as num?)?.toInt() ?? 500;
    final distLabel = distM < 1000 ? '${distM}m' : '${(distM / 1000).toStringAsFixed(1)}km';
    final sport = (raceData?['sport'] as String?)?.toUpperCase() ?? 'SPRINT';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.primaryGreen, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryGreen, width: 2),
                  ),
                  child: const Icon(Icons.flash_on, color: AppColors.primaryGreen, size: 36),
                ),
                const SizedBox(height: 16),
                const Text(
                  '⚡ DUEL CHALLENGE RECEIVED!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                    children: [
                      TextSpan(
                        text: inviterName,
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const TextSpan(text: ' has challenged you to an instant '),
                      TextSpan(
                        text: '$distLabel $sport DUEL',
                        style: const TextStyle(
                          color: AppColors.primaryCyan,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const TextSpan(text: '!\nDo you accept the challenge?'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          Navigator.of(dialogCtx).pop();
                          _lastDismissedInviteId = inviteId;
                          _isShowingChallengeDialog = false;
                          try {
                            await SupabaseService.client
                                .from('race_invitations')
                                .update({'status': 'declined'})
                                .eq('id', inviteId);
                          } catch (_) {}
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('DECLINE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.greenGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.greenGlowShadow,
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            HapticFeedback.heavyImpact();
                            Navigator.of(dialogCtx).pop();
                            _lastDismissedInviteId = inviteId;
                            _isShowingChallengeDialog = false;
                            try {
                              await SupabaseService.client
                                  .from('race_invitations')
                                  .update({'status': 'accepted'})
                                  .eq('id', inviteId);
                              final raceRepo = ref.read(raceRepositoryProvider);
                              await raceRepo.joinRace(raceId);
                              if (mounted) {
                                context.push('/lobby/$raceId');
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to join duel: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sports_score, size: 18, color: Colors.black),
                              SizedBox(width: 6),
                              Text(
                                'ACCEPT & RACE!',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isShowingChallengeDialog = false;
    });
  }

  Future<void> _showDuelChallengeSheet(NearbyPlayer player) async {
    HapticFeedback.heavyImpact();
    int selectedDistanceM = 500;
    final sport = (player.sport.isNotEmpty && player.sport != 'all')
        ? player.sport
        : (_selectedSport == 'all' ? 'running' : _selectedSport);
    bool isDispatching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Challenge Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.flash_on, color: AppColors.primaryGreen, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INSTANT SPRINT DUEL',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '1v1 Head-to-Head Live GPS Challenge',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Competitor Summary Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                          child: Text(
                            player.displayName.isNotEmpty ? player.displayName.substring(0, 1).toUpperCase() : 'R',
                            style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.displayName,
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${player.approxDistanceM <= 10 ? "< 10m away" : "~${player.approxDistanceM}m away"} • Rating ${player.rating}',
                                style: const TextStyle(color: AppColors.primaryGreen, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sport.toUpperCase(),
                            style: const TextStyle(color: AppColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Distance Selector Label
                  const Text(
                    'TARGET DUEL DISTANCE',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 10),

                  // Distance Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [100, 250, 500, 1000, 2500, 5000].map((d) {
                      final isSel = selectedDistanceM == d;
                      final label = d < 1000 ? '${d}m' : '${(d / 1000).toStringAsFixed(d % 1000 == 0 ? 0 : 1)}km';
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSel,
                        selectedColor: AppColors.primaryGreen,
                        backgroundColor: AppColors.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedDistanceM = d);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),

                  // CTA Button
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.greenGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppColors.greenGlowShadow,
                    ),
                    child: ElevatedButton(
                      onPressed: isDispatching
                          ? null
                          : () async {
                              setSheetState(() => isDispatching = true);
                              try {
                                if (SupabaseService.currentUser == null) {
                                  await SupabaseService.ensureAuthenticatedSession();
                                }
                                final inviterId = SupabaseService.currentUser?.id;
                                if (inviterId == null) {
                                  throw Exception('User authentication failed');
                                }
                                final inviterName = SupabaseService.currentUser?.userMetadata?['display_name'] ?? 'Racer Pilot';
                                final distLabel = selectedDistanceM < 1000
                                    ? '${selectedDistanceM}m'
                                    : '${(selectedDistanceM / 1000).toStringAsFixed(selectedDistanceM % 1000 == 0 ? 0 : 1)}km';

                                final raceRepo = ref.read(raceRepositoryProvider);
                                // 1. Create head_to_head race
                                final raceId = await raceRepo.createRace(
                                  sport: sport,
                                  mode: 'head_to_head',
                                  participantLimit: 2,
                                  visibility: 'public',
                                  configuration: {
                                    'course_name': '$distLabel Street Duel',
                                    'target_distance_m': selectedDistanceM,
                                    'challengee_id': player.userId,
                                    'challengee_name': player.displayName,
                                    'inviter_id': inviterId,
                                    'inviter_name': inviterName,
                                  },
                                );

                                // 2. Dispatch invitation
                                await SupabaseService.client.from('race_invitations').insert({
                                  'race_id': raceId,
                                  'inviter_id': inviterId,
                                  'invitee_id': player.userId,
                                  'status': 'pending',
                                });

                                if (mounted) {
                                  Navigator.of(sheetContext).pop();
                                  context.push('/lobby/$raceId?challengeTarget=${Uri.encodeComponent(player.displayName)}');
                                }
                              } catch (e) {
                                if (mounted) {
                                  setSheetState(() => isDispatching = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(backgroundColor: AppColors.accentRose, content: Text('Failed to send challenge: $e')),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isDispatching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.flash_on, color: Colors.black, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  '⚡ ISSUE DUEL CHALLENGE',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refreshData() async {
    final discRepo = ref.read(discoveryRepositoryProvider);
    final raceRepo = ref.read(raceRepositoryProvider);

    try {
      // Re-verify location if currently null
      if (_currentPosition == null) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          final perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
            Position? pos = await Geolocator.getLastKnownPosition();
            if (pos == null) {
              try {
                pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.medium,
                  timeLimit: const Duration(seconds: 4),
                );
              } catch (_) {}
            }
            if (pos != null && mounted) {
              setState(() {
                _currentPosition = pos;
                _locationStatusMessage = null;
                _isLocationError = false;
              });
            }
          }
        }
      }

      final lat = _currentPosition?.latitude ?? 13.0827;
      final lng = _currentPosition?.longitude ?? 80.2707;

      if (_currentPosition != null) {
        // Heartbeat update with valid sport enum
        final validSport = (_selectedSport == 'all') ? 'running' : _selectedSport;
        await discRepo.updatePresence(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          sport: validSport,
          isAvailable: true,
        );
      }

      // Fetch nearby competitors (send null if 'all' to discover every sport discipline)
      final players = await discRepo.getNearbyPlayers(
        latitude: lat,
        longitude: lng,
        radiusM: _searchRadiusM,
        sport: _selectedSport == 'all' ? null : _selectedSport,
      );
      if (mounted) setState(() => _nearbyPlayers = players);

      // Fetch open race lobbies & active user lobby
      final openLobbies = await raceRepo.getOpenRaces(sport: _selectedSport);
      final active = await raceRepo.getMyActiveLobby();

      if (mounted) {
        setState(() {
          _openRaces = openLobbies;
          _myActiveLobby = active;
        });
      }

      // Check incoming duel challenge invitations
      _checkPendingInvitations();
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(62),
        child: SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                // Compass Navigation Icon in Vibrant Green Circle (Tap to Share App)
                GestureDetector(
                  onTap: _showShareAppDialog,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: 0.785, // 45 degrees
                      child: const Icon(Icons.navigation, color: Colors.white, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // RaceZone Dynamic Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Race',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                                letterSpacing: -0.5,
                              ),
                            ),
                            TextSpan(
                              text: 'Zone',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'GPS Racing • Real Streets',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // RP Trophy Pill
                GestureDetector(
                  onTap: () => context.push('/leaderboards'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events, color: Color(0xFFD97706), size: 13),
                        SizedBox(width: 4),
                        Text(
                          '1,480 RP',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 7),

                // Circular Notification Bell with Unread Red Dot
                GestureDetector(
                  onTap: () => context.push('/notifications'),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.notifications_none, color: Color(0xFF0F172A), size: 19),
                      ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),

                // Circular Profile Avatar Button
                GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.person_outline, color: Color(0xFF0F172A), size: 19),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Dynamic Tab Views: Arena (Main Showcase) vs Radar (Tactical Discovery)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // TAB 1: ARENA (Matches reference UI exactly)
                _buildArenaView(),

                // TAB 2: RADAR & NEARBY RACERS
                _buildNearbyRacersTab(),
              ],
            ),
          ),

          // Safe Non-Disruptive Banner Ad Space
          const SafeArea(
            top: false,
            child: SafeAdBannerWidget(screenName: 'home'),
          ),
        ],
      ),
      bottomNavigationBar: _buildTacticalGamingDock(),
    );
  }

  // TAB 1: Unified Arena View (Matching exact user reference UI)
  Widget _buildArenaView() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF10B981),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Persistent Active Lobby Alert (Re-entry banner)
          if (_myActiveLobby != null) ...[
            GestureDetector(
              onTap: () => context.push('/lobby/${_myActiveLobby!.id}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryGreen, width: 1.5),
                  boxShadow: AppColors.greenGlowShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        gradient: AppColors.greenGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flash_on, color: Colors.black, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text(
                                'ACTIVE RACE LOBBY OPEN',
                                style: TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_myActiveLobby!.sport.toUpperCase()} • ${_myActiveLobby!.participants.length}/${_myActiveLobby!.participantLimit} Racers Grid',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await context.push('/lobby/${_myActiveLobby!.id}');
                        _refreshData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                      child: const Text('RE-ENTER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            title: const Text('Cancel Race Room?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            content: const Text('Do you want to stop and disband this race lobby?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('KEEP OPEN', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentRose,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('DISBAND', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && mounted) {
                          final lobbyId = _myActiveLobby!.id;
                          setState(() => _myActiveLobby = null);
                          final repo = ref.read(raceRepositoryProvider);
                          await repo.cancelRace(lobbyId);
                          if (mounted) _refreshData();
                        }
                      },
                      icon: const Icon(Icons.close, color: AppColors.accentRose, size: 20),
                      tooltip: 'Cancel & Disband Room',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Actionable Location / GPS Alert Bar
          if (_isLocationError && _locationStatusMessage != null) ...[
            GestureDetector(
              onTap: () async {
                final perm = await Geolocator.checkPermission();
                if (perm == LocationPermission.deniedForever) {
                  await Geolocator.openAppSettings();
                } else {
                  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
                  if (!serviceEnabled) {
                    await Geolocator.openLocationSettings();
                  } else {
                    await _checkAndRequestLocationPermission();
                  }
                }
                _initLocationAndFetch();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accentRose.withValues(alpha: 0.6), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentRose.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accentRose.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_off, color: AppColors.accentRose, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationStatusMessage!,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accentRose,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('ENABLE GPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // 1. Race Mode Section
          _buildRaceModeSection(),
          const SizedBox(height: 20),

          // 2. Race Distance Section
          _buildRaceDistanceSection(),
          const SizedBox(height: 20),

          // 3. Street Race Arena Card
          _buildStreetRaceArenaCard(),
          const SizedBox(height: 22),

          // 4. Active Race Rooms Section
          _buildActiveRaceRoomsSection(),
        ],
      ),
    );
  }

  // Section 1: Race Mode with 4 Cards
  Widget _buildRaceModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: Color(0xFF10B981), size: 19),
                SizedBox(width: 8),
                Text(
                  'Race Mode',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            Text(
              'Choose your race type',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildModeCard(
                id: 'running',
                title: 'Sprint',
                speedRange: '0–30 km/h',
                icon: Icons.directions_run,
                color: const Color(0xFF10B981),
                isSelected: _selectedSport == 'running',
                showSpeedLines: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModeCard(
                id: 'cycling',
                title: 'Velocity',
                speedRange: '0–60 km/h',
                icon: Icons.directions_bike,
                color: const Color(0xFF3B82F6),
                isSelected: _selectedSport == 'cycling',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModeCard(
                id: 'motorbike',
                title: 'Hyper',
                speedRange: 'Nitro Class',
                icon: Icons.two_wheeler,
                color: const Color(0xFFF97316),
                isSelected: _selectedSport == 'motorbike',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModeCard(
                id: 'custom',
                title: 'Custom',
                speedRange: 'Add Sport',
                icon: Icons.add_circle_outline,
                color: const Color(0xFF8B5CF6),
                isSelected: _selectedSport != 'running' && _selectedSport != 'cycling' && _selectedSport != 'motorbike',
                isCustomAction: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String id,
    required String title,
    required String speedRange,
    required IconData icon,
    required Color color,
    required bool isSelected,
    bool showSpeedLines = false,
    bool isCustomAction = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (isCustomAction) {
          _showCustomDisciplineDialog();
        } else {
          setState(() => _selectedSport = id);
          _refreshData();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 110,
        decoration: BoxDecoration(
          color: isSelected ? null : Colors.white,
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFFF1F5F9),
            width: 1.2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.38),
                blurRadius: 14,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Stack(
          children: [
            if (isSelected)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Color(0xFF16A34A)),
                ),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showSpeedLines && isSelected)
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(width: 8, height: 1.5, color: Colors.white.withValues(alpha: 0.7)),
                              const SizedBox(height: 3),
                              Container(width: 5, height: 1.5, color: Colors.white.withValues(alpha: 0.7)),
                            ],
                          ),
                        ),
                        Icon(icon, color: Colors.white, size: 28),
                      ],
                    )
                  else
                    Icon(
                      icon,
                      color: isSelected ? Colors.white : color,
                      size: 28,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    speedRange,
                    style: TextStyle(
                      color: isSelected ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Section 2: Race Distance
  Widget _buildRaceDistanceSection() {
    final distances = [100, 250, 500, 1000, 2500, 5000];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_outlined, color: Color(0xFF10B981), size: 19),
                SizedBox(width: 8),
                Text(
                  'Race Distance',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            Text(
              'Select distance',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: distances.map((d) {
            final isSelected = _searchRadiusM == d;
            final label = d < 1000 ? '${d}m' : '${(d / 1000).toString().replaceAll('.0', '')} km';

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _searchRadiusM = d);
                _refreshData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF16A34A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Full-width Custom Distance button
        GestureDetector(
          onTap: _showCustomRangeDialog,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune, color: Color(0xFF16A34A), size: 18),
                SizedBox(width: 8),
                Text(
                  'Custom Distance',
                  style: TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Section 3: Street Race Arena Card
  Widget _buildStreetRaceArenaCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white,
            Color(0xFFF0FDF4),
          ],
          stops: [0.65, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Street Race Arena',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Real-time GPS races with friends or the community.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 60,
                child: CustomPaint(
                  painter: _StreetRaceArenaGraphicPainter(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // Host a Sprint
              Expanded(
                flex: 6,
                child: GestureDetector(
                  onTap: _isLoading ? null : _startQuickSprint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flash_on, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Host a Sprint',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Radar Shortcut
              Expanded(
                flex: 4,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _tabController.animateTo(1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.track_changes, color: Color(0xFF16A34A), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Radar',
                          style: TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Section 4: Active Race Rooms
  Widget _buildActiveRaceRoomsSection() {
    final sportName = _selectedSport == 'running'
        ? 'Running'
        : (_selectedSport == 'cycling' ? 'Cycling' : (_selectedSport == 'motorbike' ? 'Moto' : _selectedSport.toUpperCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.group, color: Color(0xFF10B981), size: 19),
                SizedBox(width: 8),
                Text(
                  'Active Race Rooms',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _tabController.animateTo(1);
              },
              child: const Text(
                'View Nearby →',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_openRaces.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 160,
                  height: 70,
                  child: CustomPaint(
                    painter: _EmptyRoomsGraphicPainter(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No $sportName Rooms',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Host a sprint or check nearby racers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          ..._openRaces.map((race) => _buildLiveRaceCard(race)),
      ],
    );
  }

  Widget _buildLiveRaceCard(RaceModel race) {
    final spotsLeft = race.participantLimit - race.participants.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      race.sport.toUpperCase(),
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      race.mode.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: spotsLeft > 0 ? const Color(0xFF0284C7).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${race.participants.length} / ${race.participantLimit} RACERS',
                  style: TextStyle(
                    color: spotsLeft > 0 ? const Color(0xFF0284C7) : const Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            race.configuration['course_name'] ?? 'Sprint Circuit (1.0 km)',
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Host: ${race.participants.firstOrNull?.displayName ?? "Racer"} • Waiting for competitors',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (race.creatorId == SupabaseService.currentUser?.id)
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        await context.push('/lobby/${race.id}');
                        if (mounted) _refreshData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'ENTER LOBBY',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: const Text('Disband Race Room?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        content: const Text('Do you want to cancel and delete this race room?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('KEEP', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentRose,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('DISBAND', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      final repo = ref.read(raceRepositoryProvider);
                      await repo.cancelRace(race.id);
                      if (mounted) _refreshData();
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: AppColors.accentRose, size: 22),
                  tooltip: 'Disband Room',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accentRose.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  try {
                    final repo = ref.read(raceRepositoryProvider);
                    await repo.joinRace(race.id);
                    if (!mounted) return;
                    await context.push('/lobby/${race.id}');
                    if (mounted) {
                      _refreshData();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Join note: $e')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'JOIN THIS RACE LOBBY',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // TAB 2: Radar & Nearby Racers
  Widget _buildNearbyRacersTab() {
    return RefreshIndicator(
      onRefresh: _initLocationAndFetch,
      color: AppColors.primaryGreen,
      backgroundColor: AppColors.surfaceElevated,
      child: Column(
        children: [
          // Tactical Sci-Fi Radar View (Embedded Console)
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF070B14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_sweepController, _pulseController]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _RadarGridPainter(
                            sweepAngle: _sweepController.value * 2 * math.pi,
                            pulseValue: _pulseController.value,
                            playerCount: _nearbyPlayers.length,
                            players: _nearbyPlayers,
                            openRaces: _openRaces,
                            searchRadiusM: _searchRadiusM,
                          ),
                        );
                      },
                    ),
                  ),

                // Top Left: GPS Lock Status HUD
                Positioned(
                  top: 12,
                  left: 12,
                  child: GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      if (_isLocationError) {
                        final perm = await Geolocator.checkPermission();
                        if (perm == LocationPermission.deniedForever) {
                          await Geolocator.openAppSettings();
                        } else {
                          final serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            await Geolocator.openLocationSettings();
                          } else {
                            await _checkAndRequestLocationPermission();
                          }
                        }
                      }
                      _initLocationAndFetch();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1829).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isLocationError ? AppColors.accentRose : AppColors.primaryCyan.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPosition != null
                                  ? AppColors.statusOnline
                                  : (_isLocationError ? AppColors.accentRose : Colors.amber),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _currentPosition != null
                                ? 'GPS LOCKED (±${_currentPosition!.accuracy.toStringAsFixed(0)}m)'
                                : (_isLocationError ? 'LOCATION OFF (TAP TO FIX)' : 'ACQUIRING SATELLITES...'),
                            style: TextStyle(
                              color: _isLocationError ? AppColors.accentRose : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Top Right: Range HUD Tag
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0D1829),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radar, size: 12, color: AppColors.primaryGreen),
                        const SizedBox(width: 4),
                        Text(
                          'RANGE: ${_searchRadiusM < 1000 ? "${_searchRadiusM}m" : "${(_searchRadiusM / 1000).toStringAsFixed(0)}km"}',
                          style: const TextStyle(color: AppColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Left: Live Scanning Airwaves Beacon
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0D1829),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primaryCyan.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'AIRWAVES LIVE',
                          style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Right: Host Sprint Shortcut
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/create-race');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryGreen.withValues(alpha: 0.25),
                            AppColors.primaryCyan.withValues(alpha: 0.25),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.8)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryGreen.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 13, color: AppColors.primaryGreen),
                          SizedBox(width: 4),
                          Text(
                            'HOST SPRINT',
                            style: TextStyle(color: AppColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

          // Nearby Racers & Active Rooms Console with Segmented Switch
          Expanded(
            flex: 1,
            child: Container(
              color: AppColors.surface,
              child: Column(
                children: [
                  // Segmented Switch Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        // Sub-Tab 0: Nearby Racers
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _radarSubTab = 0);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _radarSubTab == 0
                                    ? AppColors.primaryGreen.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _radarSubTab == 0 ? AppColors.primaryGreen : AppColors.borderSubtle,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_pin_circle_outlined,
                                    size: 15,
                                    color: _radarSubTab == 0 ? AppColors.primaryGreen : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'RACERS (${_nearbyPlayers.length})',
                                    style: TextStyle(
                                      color: _radarSubTab == 0 ? AppColors.primaryGreen : AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Sub-Tab 1: Active Rooms
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _radarSubTab = 1);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _radarSubTab == 1
                                    ? AppColors.primaryCyan.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _radarSubTab == 1 ? AppColors.primaryCyan : AppColors.borderSubtle,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flag_outlined,
                                    size: 15,
                                    color: _radarSubTab == 1 ? AppColors.primaryCyan : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ROOMS (${_openRaces.length})',
                                    style: TextStyle(
                                      color: _radarSubTab == 1 ? AppColors.primaryCyan : AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Scan Refresh Button
                        if (_isLoading)
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: IconButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _initLocationAndFetch();
                              },
                              icon: const Icon(Icons.refresh, size: 18, color: AppColors.primaryGreen),
                              tooltip: 'Scan Now',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.borderSubtle, height: 1),

                  // Body Content: Racers or Rooms
                  Expanded(
                    child: _radarSubTab == 0
                        ? (_nearbyPlayers.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.radar, size: 36, color: AppColors.primaryCyan.withValues(alpha: 0.45)),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Scanning Surrounding Airwaves...',
                                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'No active racers currently broadcasting in your ${_searchRadiusM < 1000 ? "${_searchRadiusM}m" : "${(_searchRadiusM / 1000).toStringAsFixed(_searchRadiusM % 1000 == 0 ? 0 : 1)}km"} zone.\nExpand your radar range or host a room!',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: AppColors.greenGradient,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: AppColors.greenGlowShadow,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            HapticFeedback.mediumImpact();
                                            context.push('/create-race');
                                          },
                                          icon: const Icon(Icons.flash_on, size: 16, color: Colors.black),
                                          label: const Text(
                                            '⚡ HOST A SPRINT LOBBY',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.black),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: _nearbyPlayers.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final player = _nearbyPlayers[index];

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.primaryGreen.withValues(alpha: 0.4),
                                      ),
                                      boxShadow: AppColors.cardShadow,
                                    ),
                                    child: Row(
                                      children: [
                                        // Avatar with Glow Ring
                                        Stack(
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.primaryGreen,
                                                  width: 1.5,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                player.displayName.isNotEmpty
                                                    ? player.displayName.substring(0, 1).toUpperCase()
                                                    : 'R',
                                                style: const TextStyle(
                                                  color: AppColors.primaryGreen,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryGreen,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: AppColors.surfaceElevated, width: 2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),

                                        // Racer Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      player.displayName,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: AppColors.textPrimary,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primaryGreen.withValues(alpha: 0.18),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      player.sport.toUpperCase(),
                                                      style: const TextStyle(
                                                        color: AppColors.primaryGreen,
                                                        fontSize: 8,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(
                                                    player.approxDistanceM <= 10 ? '< 10m away' : '~${player.approxDistanceM}m away',
                                                    style: const TextStyle(
                                                      color: AppColors.primaryGreen,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                                                  Text(
                                                    'Rating ${player.rating}',
                                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Direct Duel Challenge Button
                                        ElevatedButton(
                                          onPressed: () => _showDuelChallengeSheet(player),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primaryGreen,
                                            foregroundColor: AppColors.textInverse,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 2,
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.flash_on, size: 14),
                                              SizedBox(width: 2),
                                              Text('DUEL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ))
                        : (_openRaces.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.meeting_room_outlined, size: 36, color: AppColors.primaryCyan.withValues(alpha: 0.5)),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'No Open Race Rooms',
                                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Host a room to invite nearby competitors or friends!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: AppColors.greenGradient,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: AppColors.greenGlowShadow,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            HapticFeedback.mediumImpact();
                                            context.push('/create-race');
                                          },
                                          icon: const Icon(Icons.add_road, size: 16, color: Colors.black),
                                          label: const Text(
                                            '⚡ HOST A ROOM',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.black),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: _openRaces.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final race = _openRaces[index];
                                  return _buildLiveRaceCard(race);
                                },
                              )),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomRangeDialog() {
    HapticFeedback.mediumImpact();
    double tempRadius = _searchRadiusM.toDouble().clamp(50.0, 20000.0);
    final textController = TextEditingController(text: _searchRadiusM.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final formatted = tempRadius < 1000
                ? '${tempRadius.round()}m'
                : '${(tempRadius / 1000).toStringAsFixed(1)}km';

            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.radar, color: AppColors.primaryGreen, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUSTOM RADAR RANGE',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Set your GPS street scanner radius',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Current display badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: AppColors.greenGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppColors.greenGlowShadow,
                      ),
                      child: Text(
                        formatted,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quick presets
                  const Text(
                    'QUICK PRESETS',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [150, 300, 750, 1500, 2500, 3000, 5000, 10000].map((preset) {
                      final isSelected = tempRadius.round() == preset;
                      final label = preset < 1000 ? '${preset}m' : '${(preset / 1000).toStringAsFixed(preset % 1000 == 0 ? 0 : 1)}km';
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                        backgroundColor: AppColors.surfaceElevated,
                        side: BorderSide(
                          color: isSelected ? AppColors.primaryGreen : AppColors.borderSubtle,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primaryGreen : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 12,
                        ),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setSheetState(() {
                            tempRadius = preset.toDouble();
                            textController.text = preset.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Slider
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50m', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('20km', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primaryGreen,
                      inactiveTrackColor: AppColors.borderSubtle,
                      thumbColor: AppColors.primaryGreen,
                      overlayColor: AppColors.primaryGreen.withValues(alpha: 0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: tempRadius,
                      min: 50.0,
                      max: 20000.0,
                      divisions: 199,
                      onChanged: (val) {
                        setSheetState(() {
                          tempRadius = (val / 50).round() * 50.0;
                          textController.text = tempRadius.round().toString();
                        });
                      },
                    ),
                  ),

                  // Manual numeric text input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Exact Distance (Meters)',
                            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            suffixText: 'm',
                            prefixIcon: const Icon(Icons.edit_road, color: AppColors.primaryCyan, size: 18),
                            filled: true,
                            fillColor: AppColors.surfaceElevated,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.borderSubtle),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                            ),
                          ),
                          onChanged: (txt) {
                            final parsed = int.tryParse(txt);
                            if (parsed != null && parsed >= 50 && parsed <= 50000) {
                              setSheetState(() {
                                tempRadius = parsed.toDouble().clamp(50.0, 20000.0);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        final val = int.tryParse(textController.text) ?? tempRadius.round();
                        final safeRadius = val.clamp(50, 50000);
                        setState(() {
                          if (!_radii.contains(safeRadius)) {
                            _radii.add(safeRadius);
                            _radii.sort();
                          }
                          _searchRadiusM = safeRadius;
                        });
                        Navigator.pop(ctx);
                        _refreshData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text(
                        'APPLY RADAR RANGE',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCustomDisciplineDialog() {
    HapticFeedback.mediumImpact();
    final nameController = TextEditingController();
    final categoryController = TextEditingController(text: 'CUSTOM SPEED');
    IconData selectedIcon = Icons.sports_score;
    Color selectedColor = AppColors.primaryCyan;

    final List<IconData> iconOptions = [
      Icons.sports_score,
      Icons.skateboarding,
      Icons.roller_skating,
      Icons.electric_scooter,
      Icons.directions_walk,
      Icons.fitness_center,
      Icons.flag,
      Icons.timer,
    ];

    final List<Color> colorOptions = [
      AppColors.primaryCyan,
      AppColors.accentPurple,
      AppColors.accentAmber,
      AppColors.accentRose,
      AppColors.gold,
      AppColors.primaryGreen,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(selectedIcon, color: selectedColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ADD CUSTOM DISCIPLINE',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Create a custom racing or workout sport',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Name Field
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Sport / Mode Name (e.g. Skating, Trail Run)',
                      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: selectedColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Category / Speed tag
                  TextField(
                    controller: categoryController,
                    decoration: InputDecoration(
                      labelText: 'Speed or Bracket Tag (e.g. 0-25 KM/H, PRO)',
                      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: selectedColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Icon Picker
                  const Text('CHOOSE ICON', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: iconOptions.map((icon) {
                      final isSel = selectedIcon == icon;
                      return InkWell(
                        onTap: () => setSheetState(() => selectedIcon = icon),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSel ? selectedColor.withValues(alpha: 0.2) : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSel ? selectedColor : AppColors.borderSubtle, width: isSel ? 2 : 1),
                          ),
                          child: Icon(icon, color: isSel ? selectedColor : AppColors.textSecondary, size: 20),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Color Picker
                  const Text('CHOOSE THEME COLOR', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: colorOptions.map((color) {
                      final isSel = selectedColor == color;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = color),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSel ? Border.all(color: AppColors.textPrimary, width: 2.5) : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;
                        HapticFeedback.mediumImpact();
                        final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                        final cat = categoryController.text.trim().isNotEmpty ? categoryController.text.trim().toUpperCase() : 'CUSTOM';
                        setState(() {
                          _disciplines.add(
                            DisciplineItem(
                              id: id,
                              title: name.toUpperCase(),
                              category: cat,
                              icon: selectedIcon,
                              activeGradient: LinearGradient(
                                colors: [selectedColor, selectedColor.withValues(alpha: 0.8)],
                              ),
                              accentColor: selectedColor,
                              isCustom: true,
                            ),
                          );
                          _selectedSport = id;
                        });
                        Navigator.pop(ctx);
                        _refreshData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'ACTIVATE CUSTOM SPORT',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showShareAppDialog() {
    HapticFeedback.mediumImpact();
    const downloadUrl = 'http://10.35.51.56:8080/install.html';
    const shareMessage = '⚡ Race with me on RaceZone GPS Speedway! Download & install directly: $downloadUrl';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppColors.cyanGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.share, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHARE WITH OTHER MOBILES',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        'Install RaceZone on nearby phones to duel',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Wi-Fi instructions HUD Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi, color: AppColors.primaryGreen, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Direct Wi-Fi APK Download Link',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const SelectableText(
                        downloadUrl,
                        style: TextStyle(
                          color: AppColors.primaryCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Open this link in Chrome or any browser on the other phone while connected to the same Wi-Fi to install instantly.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: shareMessage));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.primaryGreen,
                            content: Text('Download link & invite message copied!'),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text(
                        'COPY LINK',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: shareMessage));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.primaryCyan,
                            content: Text('Share invite copied! Paste into WhatsApp or messages.'),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryCyan,
                        side: const BorderSide(color: AppColors.primaryCyan, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text(
                        'INVITE RACER',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTacticalGamingDock() {
    final currentIndex = _tabController.index;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 8,
        left: 12,
        right: 12,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Item 1: Arena
              _buildDockItem(
                icon: Icons.flag,
                label: 'Arena',
                isActive: currentIndex == 0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _tabController.animateTo(0);
                },
              ),

              // Item 2: Radar
              _buildDockItem(
                icon: Icons.track_changes,
                label: 'Radar',
                isActive: currentIndex == 1,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _tabController.animateTo(1);
                },
              ),

              // Center Spacer for elevated circular Race Now button
              const SizedBox(width: 64),

              // Item 4: Ranks (Podium & Leaderboard)
              _buildDockItem(
                icon: Icons.emoji_events_outlined,
                label: 'Ranks',
                isActive: false,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/leaderboards');
                },
              ),

              // Item 5: Garage / Profile
              _buildDockItem(
                icon: Icons.directions_car_outlined,
                label: 'Garage',
                isActive: false,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/profile');
                },
              ),
            ],
          ),

          // Center Prominent Elevated Circular "Race Now" Button
          Positioned(
            top: -20,
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.heavyImpact();
                await context.push('/create-race');
                _refreshData();
              },
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, color: Colors.white, size: 26),
                    Text(
                      'Race Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF10B981) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for Street Race Arena curved waypoint track and destination pin
class _StreetRaceArenaGraphicPainter extends CustomPainter {
  const _StreetRaceArenaGraphicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Soft green ambient glow behind destination
    final glowPaint = Paint()
      ..color = const Color(0xFFDCFCE7).withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.35), 24, glowPaint);

    // 2. Curved green race track bezier path
    final path = Path()
      ..moveTo(0, size.height * 0.78)
      ..cubicTo(
        size.width * 0.35, size.height * 0.78,
        size.width * 0.45, size.height * 0.52,
        size.width * 0.78, size.height * 0.42,
      );

    // Glowing track halo
    final trackHaloPaint = Paint()
      ..color = const Color(0xFF86EFAC).withValues(alpha: 0.6)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, trackHaloPaint);

    // Core vibrant track line
    final trackLinePaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, trackLinePaint);

    // Waypoint dots
    final dotPaint = Paint()..color = const Color(0xFF16A34A);
    canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.68), 3.5, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.76, size.height * 0.43), 3.0, dotPaint);

    // Destination Pin
    final pinCenter = Offset(size.width * 0.78, size.height * 0.30);
    // Pin shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(pinCenter.dx, pinCenter.dy + 12), width: 14, height: 5),
      Paint()..color = const Color(0x20000000),
    );
    // Pin head
    final pinPaint = Paint()..color = const Color(0xFF10B981);
    final pinPath = Path()
      ..moveTo(pinCenter.dx, pinCenter.dy + 11)
      ..cubicTo(
        pinCenter.dx - 9, pinCenter.dy + 2,
        pinCenter.dx - 9, pinCenter.dy - 10,
        pinCenter.dx, pinCenter.dy - 10,
      )
      ..cubicTo(
        pinCenter.dx + 9, pinCenter.dy - 10,
        pinCenter.dx + 9, pinCenter.dy + 2,
        pinCenter.dx, pinCenter.dy + 11,
      )
      ..close();
    canvas.drawPath(pinPath, pinPaint);
    // Pin inner circle
    canvas.drawCircle(Offset(pinCenter.dx, pinCenter.dy - 3), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for empty race rooms with concentric radar ripples and pin with play triangle
class _EmptyRoomsGraphicPainter extends CustomPainter {
  const _EmptyRoomsGraphicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.62);

    // Soft clouds/hills silhouette
    final hillPaint = Paint()..color = const Color(0xFFF0FDF4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.28, size.height * 0.42), width: 54, height: 24),
      hillPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.74, size.height * 0.38), width: 62, height: 26),
      hillPaint,
    );

    // Concentric ground ripples (ellipses)
    final ripplePaint = Paint()
      ..color = const Color(0xFFDCFCE7).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawOval(Rect.fromCenter(center: center, width: 130, height: 42), ripplePaint);
    canvas.drawOval(Rect.fromCenter(center: center, width: 90, height: 30), ripplePaint);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 54, height: 18),
      Paint()..color = const Color(0xFFBBF7D0).withValues(alpha: 0.4)..style = PaintingStyle.fill,
    );

    // Destination Pin with Play Triangle
    final pinCenter = Offset(center.dx, center.dy - 20);
    final pinPaint = Paint()..color = const Color(0xFF10B981);
    final pinPath = Path()
      ..moveTo(pinCenter.dx, pinCenter.dy + 14)
      ..cubicTo(
        pinCenter.dx - 12, pinCenter.dy + 3,
        pinCenter.dx - 12, pinCenter.dy - 12,
        pinCenter.dx, pinCenter.dy - 12,
      )
      ..cubicTo(
        pinCenter.dx + 12, pinCenter.dy - 12,
        pinCenter.dx + 12, pinCenter.dy + 3,
        pinCenter.dx, pinCenter.dy + 14,
      )
      ..close();
    canvas.drawPath(pinPath, pinPaint);

    // White play triangle inside pin
    final playPath = Path()
      ..moveTo(pinCenter.dx - 2.5, pinCenter.dy - 6.5)
      ..lineTo(pinCenter.dx + 4.5, pinCenter.dy - 2)
      ..lineTo(pinCenter.dx - 2.5, pinCenter.dy + 2.5)
      ..close();
    canvas.drawPath(playPath, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Tactical Radar Canvas Painter with Sweep Animation & Ping Flares
class _RadarGridPainter extends CustomPainter {
  final double sweepAngle;
  final double pulseValue;
  final int playerCount;
  final List<NearbyPlayer> players;
  final List<RaceModel> openRaces;
  final int searchRadiusM;

  _RadarGridPainter({
    required this.sweepAngle,
    required this.pulseValue,
    required this.playerCount,
    required this.players,
    this.openRaces = const [],
    required this.searchRadiusM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Adjusted maxRadius scale (0.35) so North chevron, 'N', 'S', 'E', 'W' labels, and outer bezel rings fit with zero clipping
    final maxRadius = math.min(size.width, size.height) * 0.35;

    // 1. Tactical Radar Background Radial Gradient
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [
          Color(0xFF0F1E36),
          Color(0xFF09101D),
          Color(0xFF060A12),
        ],
        stops: [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, bgPaint);

    // 2. Tactical Concentric Range Rings
    final ringPaint = Paint()
      ..color = const Color(0xFF1E355B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final outerRingPaint = Paint()
      ..color = AppColors.primaryCyan.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (int i = 1; i <= 3; i++) {
      final r = maxRadius * (i / 3);
      canvas.drawCircle(center, r, i == 3 ? outerRingPaint : ringPaint);
    }

    // 3. Compass Cardinal Ticks & Labels (N, E, S, W)
    final tickPaint = Paint()
      ..color = AppColors.primaryCyan.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Outer perimeter 36-tick ring (every 10 degrees)
    for (int deg = 0; deg < 360; deg += 10) {
      final rad = deg * math.pi / 180;
      final isMajor = (deg % 30 == 0);
      final tickLen = isMajor ? 7.0 : 3.5;
      final p1 = Offset(center.dx + (maxRadius - tickLen) * math.cos(rad), center.dy + (maxRadius - tickLen) * math.sin(rad));
      final p2 = Offset(center.dx + maxRadius * math.cos(rad), center.dy + maxRadius * math.sin(rad));
      canvas.drawLine(p1, p2, tickPaint);
    }

    // North Indicator Chevron and Text
    final northPaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(center.dx, center.dy - maxRadius - 10)
      ..lineTo(center.dx - 5, center.dy - maxRadius - 3)
      ..lineTo(center.dx + 5, center.dy - maxRadius - 3)
      ..close();
    canvas.drawPath(path, northPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawHudText(String text, Offset pos, Color color, {double fontSize = 10, bool bold = true}) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal, letterSpacing: 0.8),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2));
    }

    drawHudText('N', Offset(center.dx, center.dy - maxRadius - 17), AppColors.primaryGreen, fontSize: 10);
    drawHudText('S', Offset(center.dx, center.dy + maxRadius + 12), AppColors.textMuted, fontSize: 9);
    drawHudText('E', Offset(center.dx + maxRadius + 12, center.dy), AppColors.textMuted, fontSize: 9);
    drawHudText('W', Offset(center.dx - maxRadius - 12, center.dy), AppColors.textMuted, fontSize: 9);

    // Range Labels along 45 degree axis
    final r1 = maxRadius / 3;
    final r2 = maxRadius * 2 / 3;
    const rad45 = -math.pi / 4;
    final dist1 = searchRadiusM ~/ 3;
    final dist2 = (searchRadiusM * 2) ~/ 3;
    final dist3 = searchRadiusM;
    drawHudText('${dist1}m', Offset(center.dx + r1 * math.cos(rad45), center.dy + r1 * math.sin(rad45) - 6), AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 8);
    drawHudText('${dist2}m', Offset(center.dx + r2 * math.cos(rad45), center.dy + r2 * math.sin(rad45) - 6), AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 8);
    drawHudText(dist3 < 1000 ? '${dist3}m' : '${(dist3 / 1000).toStringAsFixed(1)}km', Offset(center.dx + maxRadius * math.cos(rad45), center.dy + maxRadius * math.sin(rad45) - 6), AppColors.primaryCyan.withValues(alpha: 0.8), fontSize: 8);

    // 4. Crosshairs with broken center
    final crossPaint = Paint()
      ..color = const Color(0xFF1E355B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    // Top
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy - 16), crossPaint);
    // Bottom
    canvas.drawLine(Offset(center.dx, center.dy + 16), Offset(center.dx, center.dy + maxRadius), crossPaint);
    // Left
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx - 16, center.dy), crossPaint);
    // Right
    canvas.drawLine(Offset(center.dx + 16, center.dy), Offset(center.dx + maxRadius, center.dy), crossPaint);

    // 5. Sonar Expanding Ripple Waves (Animated)
    for (int ring = 0; ring < 2; ring++) {
      final ringProgress = (pulseValue + ring * 0.5) % 1.0;
      final waveRadius = maxRadius * ringProgress;
      final waveAlpha = (1.0 - ringProgress).clamp(0.0, 1.0) * 0.45;
      final wavePaint = Paint()
        ..color = AppColors.primaryGreen.withValues(alpha: waveAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // 6. Rotating Radar Sweeper Beam & Wedge Arc (Animated)
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi / 4, // 45 degree sector
      colors: [
        Colors.transparent,
        AppColors.primaryGreen.withValues(alpha: 0.05),
        AppColors.primaryGreen.withValues(alpha: 0.35),
      ],
      stops: const [0.0, 0.4, 1.0],
      transform: GradientRotation(sweepAngle - math.pi / 4),
    );

    final sweepWedgePaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipPath(Path()..addOval(sweepRect));
    canvas.drawArc(sweepRect, sweepAngle - math.pi / 4, math.pi / 4, true, sweepWedgePaint);
    canvas.restore();

    // Leading Sweep Ray Line
    final rayEnd = Offset(center.dx + maxRadius * math.cos(sweepAngle), center.dy + maxRadius * math.sin(sweepAngle));
    final rayGlowPaint = Paint()
      ..color = AppColors.primaryGreen.withValues(alpha: 0.5)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, rayEnd, rayGlowPaint);

    final rayCorePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, rayEnd, rayCorePaint);

    // 7. Outer Dial Bezel Accents (Smooth Circular Arcs, No Sharp Square Corners)
    final bezelArcPaint = Paint()
      ..color = AppColors.primaryCyan.withValues(alpha: 0.25)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final bezelRadius = maxRadius + 5;
    // Four smooth quadrant accent arcs instead of sharp square corner brackets
    for (int i = 0; i < 4; i++) {
      final start = (i * math.pi / 2) + math.pi / 12;
      const sweep = math.pi / 3;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: bezelRadius),
        start,
        sweep,
        false,
        bezelArcPaint,
      );
    }

    // 8. Competitor Blips & Ping Flares
    final blipCount = math.max(playerCount, players.length);
    for (int i = 0; i < blipCount; i++) {
      final angle = (i * 2.399) + 0.6;
      final distFrac = 0.28 + ((i * 7) % 11) * 0.06;
      final r = maxRadius * distFrac.clamp(0.25, 0.92);
      final blipOffset = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));

      // Calculate angular delta between sweep beam and this blip
      final normalizedBlipAngle = (angle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
      final normalizedSweepAngle = (sweepAngle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
      double angleDelta = (normalizedSweepAngle - normalizedBlipAngle).abs();
      if (angleDelta > math.pi) angleDelta = 2 * math.pi - angleDelta;

      final isSweepingOver = angleDelta < 0.28;
      const blipColor = AppColors.primaryGreen;

      if (isSweepingOver) {
        // High-Energy Ping Flare!
        canvas.drawCircle(blipOffset, 14, Paint()..color = blipColor.withValues(alpha: 0.5));
        canvas.drawCircle(blipOffset, 7, Paint()..color = Colors.white);
        canvas.drawCircle(blipOffset, 18, Paint()..color = blipColor.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.5);

        final approxDist = (distFrac * searchRadiusM).round();
        drawHudText('${approxDist}m', Offset(blipOffset.dx, blipOffset.dy - 14), Colors.white, fontSize: 8);
      } else {
        // Standard Luminous Blip
        canvas.drawCircle(blipOffset, 7, Paint()..color = blipColor.withValues(alpha: 0.25));
        canvas.drawCircle(blipOffset, 4, Paint()..color = blipColor);
        canvas.drawCircle(blipOffset, 1.5, Paint()..color = Colors.white);
      }
    }

    // 8.B Hosted Active Room Beacon Markers on Radar Scope
    for (int i = 0; i < openRaces.length; i++) {
      final race = openRaces[i];
      final angle = (i * 2.1) + 1.1;
      final distFrac = 0.42 + ((i * 5) % 6) * 0.09;
      final r = maxRadius * distFrac.clamp(0.35, 0.88);
      final roomOffset = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));

      final normalizedRoomAngle = (angle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
      final normalizedSweepAngle = (sweepAngle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
      double angleDelta = (normalizedSweepAngle - normalizedRoomAngle).abs();
      if (angleDelta > math.pi) angleDelta = 2 * math.pi - angleDelta;

      final isSweepingOver = angleDelta < 0.28;
      const roomColor = Color(0xFF00E5FF); // Vibrant Cyan Diamond

      final diamondPath = Path()
        ..moveTo(roomOffset.dx, roomOffset.dy - 6)
        ..lineTo(roomOffset.dx + 5, roomOffset.dy)
        ..lineTo(roomOffset.dx, roomOffset.dy + 6)
        ..lineTo(roomOffset.dx - 5, roomOffset.dy)
        ..close();

      if (isSweepingOver) {
        canvas.drawCircle(roomOffset, 14, Paint()..color = roomColor.withValues(alpha: 0.4));
        canvas.drawPath(diamondPath, Paint()..color = Colors.white);
        drawHudText('ROOM (${race.participants.length}/${race.participantLimit})', Offset(roomOffset.dx, roomOffset.dy - 14), Colors.white, fontSize: 8);
      } else {
        canvas.drawCircle(roomOffset, 7, Paint()..color = roomColor.withValues(alpha: 0.25));
        canvas.drawPath(diamondPath, Paint()..color = roomColor);
        canvas.drawCircle(roomOffset, 1.5, Paint()..color = Colors.white);
        drawHudText('ROOM', Offset(roomOffset.dx, roomOffset.dy + 10), roomColor, fontSize: 7, bold: true);
      }
    }

    // 9. Center Player Origin Beacon
    final centerPulse = (pulseValue * 12).clamp(4.0, 14.0);
    canvas.drawCircle(center, centerPulse, Paint()..color = AppColors.primaryGreen.withValues(alpha: (1.0 - pulseValue).clamp(0.0, 0.5))..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawCircle(center, 8, Paint()..color = AppColors.primaryGreen.withValues(alpha: 0.35));
    canvas.drawCircle(center, 5, Paint()..color = AppColors.primaryGreen);
    canvas.drawCircle(center, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RadarGridPainter oldDelegate) {
    return true; // Continuously animated by controllers
  }
}

