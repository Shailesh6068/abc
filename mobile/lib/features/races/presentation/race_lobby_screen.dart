import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/races/data/race_repository.dart';
import 'package:racezone/features/races/domain/race_model.dart';

class RaceLobbyScreen extends ConsumerStatefulWidget {
  final String raceId;

  const RaceLobbyScreen({super.key, required this.raceId});

  @override
  ConsumerState<RaceLobbyScreen> createState() => _RaceLobbyScreenState();
}

class _RaceLobbyScreenState extends ConsumerState<RaceLobbyScreen> {
  RaceModel? _race;
  bool _isLoading = true;
  bool _isTogglingReady = false;
  bool _isPerformingHostAction = false;
  RealtimeChannel? _realtimeChannel;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;
  Timer? _pollingTimer;
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    _loadRaceAndSubscribe();
  }

  @override
  void dispose() {
    _hasNavigatedAway = true;
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadRaceAndSubscribe() async {
    final repo = ref.read(raceRepositoryProvider);
    try {
      final race = await repo.getRaceDetails(widget.raceId);
      if (mounted) {
        setState(() {
          _race = race;
          _isLoading = false;
        });
        _checkStateTransitions(race);
      }

      // Realtime subscription
      _realtimeChannel = repo.subscribeToRace(widget.raceId, (updatedRace) {
        if (mounted) {
          setState(() => _race = updatedRace);
          _checkStateTransitions(updatedRace);
        }
      });

      // Periodic polling fallback (every 2s) to guarantee opponent acceptance & join sync
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted || _hasNavigatedAway) return;
        try {
          final updated = await repo.getRaceDetails(widget.raceId);
          if (mounted && !_hasNavigatedAway) {
            setState(() => _race = updated);
            _checkStateTransitions(updated);
          }
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _checkStateTransitions(RaceModel race) {
    if (_hasNavigatedAway || !mounted) return;

    if (race.status == 'COUNTDOWN') {
      _startCountdown();
    } else if (race.status == 'IN_PROGRESS') {
      _hasNavigatedAway = true;
      _countdownTimer?.cancel();
      context.go('/live-race/${widget.raceId}');
    } else if (race.status == 'CANCELLED') {
      _hasNavigatedAway = true;
      _countdownTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This race lobby was cancelled by the host.')),
      );
      context.go('/home');
    }
  }

  void _startCountdown() {
    if (_hasNavigatedAway || (_countdownTimer != null && _countdownTimer!.isActive)) return;
    _countdownSeconds = 5;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _hasNavigatedAway) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        if (mounted && !_hasNavigatedAway) {
          _hasNavigatedAway = true;
          final isHost = _race?.creatorId == SupabaseService.currentUser?.id;
          if (isHost) {
            // Trigger authoritative state machine transition to IN_PROGRESS
            ref.read(raceRepositoryProvider).transitionRaceState(widget.raceId, 'IN_PROGRESS').catchError((err) {
              debugPrint('Countdown transition note: $err');
              return 'IN_PROGRESS';
            });
          }
          context.go('/live-race/${widget.raceId}');
        }
      }
    });
  }

  Future<void> _toggleReady() async {
    final currentUserId = SupabaseService.currentUser?.id;
    if (_race == null || currentUserId == null) return;

    final myPart = _race!.participants.firstWhere(
      (p) => p.userId == currentUserId,
      orElse: () => RaceParticipant(
        userId: currentUserId,
        displayName: 'You',
        status: 'joined',
        joinedAt: DateTime.now(),
      ),
    );

    final nextReady = myPart.status != 'ready';

    setState(() => _isTogglingReady = true);
    try {
      final repo = ref.read(raceRepositoryProvider);
      await repo.setReady(widget.raceId, nextReady);
      final updated = await repo.getRaceDetails(widget.raceId);
      if (mounted) {
        setState(() => _race = updated);
        _checkStateTransitions(updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating readiness: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingReady = false);
    }
  }

  Future<void> _handleStartRaceNow() async {
    setState(() => _isPerformingHostAction = true);
    try {
      final repo = ref.read(raceRepositoryProvider);
      await repo.startRaceNow(widget.raceId);
      final updated = await repo.getRaceDetails(widget.raceId);
      if (mounted) {
        setState(() => _race = updated);
        _checkStateTransitions(updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start race: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingHostAction = false);
    }
  }

  void _handleShareRoomCode() {
    Clipboard.setData(ClipboardData(text: widget.raceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.primaryGreen,
        content: Text('Room ID copied to clipboard! Share with racers to join.'),
      ),
    );
  }

  Future<void> _handleBackAttempt() async {
    final currentUserId = SupabaseService.currentUser?.id;
    final isHost = _race != null && (_race!.creatorId == currentUserId || _race!.participants.firstOrNull?.userId == currentUserId);

    if (isHost) {
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.settings, color: AppColors.primaryGreen, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Race Lobby Options',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'You are the host of this race room.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Option 1: Keep Lobby Open & Go to Home
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primaryGreen, width: 1.2),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.home_outlined, color: AppColors.primaryGreen, size: 22),
                      ),
                      title: const Text(
                        'Leave & Keep Race Open',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Your race room stays open for players. You can return anytime via the home screen banner.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.go('/home');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Option 2: Cancel Race
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.accentRose.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accentRose, width: 1.2),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.accentRose.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cancel_outlined, color: AppColors.accentRose, size: 22),
                      ),
                      title: const Text(
                        'Cancel & Disband Race',
                        style: TextStyle(color: AppColors.accentRose, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Permanently delete this race room for all participants.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          final repo = ref.read(raceRepositoryProvider);
                          await repo.cancelRace(widget.raceId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Race lobby cancelled.')),
                            );
                            context.go('/home');
                          }
                        } catch (e) {
                          if (mounted) context.go('/home');
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Stay in Lobby
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Stay in Lobby', style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // Non-host participant
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Leave Race Lobby?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: const Text(
            'You will leave this race room and return to the main radar screen.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('STAY', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRose, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('LEAVE', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        try {
          final repo = ref.read(raceRepositoryProvider);
          await repo.leaveRace(widget.raceId);
        } catch (_) {}
        if (mounted) {
          context.go('/home');
        }
      }
    }
  }

  IconData _sportIcon(String sport) {
    switch (sport.toLowerCase()) {
      case 'cycling':
        return Icons.directions_bike;
      case 'motorbike':
        return Icons.two_wheeler;
      default:
        return Icons.directions_run;
    }
  }

  Color _sportColor(String sport) {
    switch (sport.toLowerCase()) {
      case 'cycling':
        return AppColors.primaryCyan;
      case 'motorbike':
        return const Color(0xFFFF6D00);
      default:
        return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _race == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final currentUserId = SupabaseService.currentUser?.id;
    final isHost = _race!.creatorId == currentUserId || _race!.participants.firstOrNull?.userId == currentUserId;
    final myPart = _race!.participants.where((p) => p.userId == currentUserId).firstOrNull;
    final isReady = myPart?.status == 'ready';
    final isCountdown = _race!.status == 'COUNTDOWN';
    final sportColor = _sportColor(_race!.sport);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackAttempt();
        }
      },
      child: Scaffold(
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
                child: const Icon(Icons.flash_on, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                '${_race!.sport.toUpperCase()} SPEEDWAY',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back / Exit Lobby',
            onPressed: _handleBackAttempt,
          ),
          actions: [
            if (isHost)
              Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.metallicGold,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, color: Colors.black, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'HOST',
                      style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Race Info Card — white card with green left accent border
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.borderSubtle),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left green accent bar
                            Container(
                              width: 5,
                              decoration: const BoxDecoration(
                                gradient: AppColors.greenGradient,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  bottomLeft: Radius.circular(18),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Sport icon in colored circle
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: sportColor.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: sportColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Icon(_sportIcon(_race!.sport), color: sportColor, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  _race!.mode.toUpperCase().replaceAll('_', ' '),
                                                  style: const TextStyle(
                                                    color: AppColors.primaryGreen,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 10,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryCyan.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  '${_race!.participants.length}/${_race!.participantLimit} RACERS',
                                                  style: const TextStyle(
                                                    color: AppColors.primaryCyan,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _race!.configuration['course_name'] ?? 'Sanctioned GPS Speedway Circuit',
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _race!.mode == 'distance_race'
                                                ? '⚡ First racer to cross the target distance claims victory!'
                                                : (_race!.mode == 'time_trial'
                                                    ? '⚡ Cover maximum distance before timer expires!'
                                                    : '⚡ First racer to reach destination checkpoint wins!'),
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // GRID LINEUP section header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 3,
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: AppColors.greenGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'GRID LINEUP',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        if (isHost && _race!.participants.length < _race!.participantLimit)
                          InkWell(
                            onTap: _handleShareRoomCode,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.primaryGreen),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.copy, color: AppColors.primaryGreen, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Share Room ID',
                                    style: TextStyle(color: AppColors.primaryGreen, fontSize: 11, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Builder(
                      builder: (context) {
                        final isWaitingOpponent = _race!.mode == 'head_to_head' && _race!.participants.length == 1;
                        final challengeeName = (_race!.configuration['challengee_name'] as String?) ?? 'Opponent';
                        final totalItems = isWaitingOpponent ? 2 : _race!.participants.length;

                        return Expanded(
                          child: ListView.separated(
                            itemCount: totalItems,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (isWaitingOpponent && index == 1) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.amber.withValues(alpha: 0.6),
                                      width: 1.5,
                                    ),
                                    boxShadow: AppColors.cardShadow,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.amber.withValues(alpha: 0.15),
                                        child: const Icon(Icons.hourglass_top, color: Colors.amber, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              challengeeName,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            const Text(
                                              'Challenge sent • Waiting for opponent to accept...',
                                              style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                                      ),
                                    ],
                                  ),
                                );
                              }
                          final p = _race!.participants[index];
                          final pReady = p.status == 'ready';
                          final isMe = p.userId == currentUserId;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: pReady ? AppColors.primaryGreen : AppColors.borderSubtle,
                                width: pReady ? 1.8 : 1.0,
                              ),
                              boxShadow: pReady
                                  ? AppColors.greenGlowShadow
                                  : AppColors.cardShadow,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.15),
                                  child: Text(
                                    p.displayName.isNotEmpty ? p.displayName.substring(0, 1).toUpperCase() : 'R',
                                    style: const TextStyle(
                                      color: AppColors.primaryGreen,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              p.displayName + (isMe ? ' (You)' : ''),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          if (index == 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                gradient: AppColors.metallicGold,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'HOST',
                                                style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      // Status pill
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: pReady
                                              ? AppColors.primaryGreen.withValues(alpha: 0.12)
                                              : AppColors.accentAmber.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              pReady ? Icons.check_circle : Icons.hourglass_top,
                                              color: pReady ? AppColors.primaryGreen : AppColors.accentAmber,
                                              size: 11,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              pReady ? 'READY TO SPRINT ⚡' : 'Waiting...',
                                              style: TextStyle(
                                                color: pReady ? AppColors.primaryGreen : AppColors.accentAmber,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),

                    const SizedBox(height: 12),

                    // Host Action Bar — START RACE gradient button with glow
                    if (isHost) ...[
                      Builder(
                        builder: (context) {
                          final isWaitingOpponent = _race!.mode == 'head_to_head' && _race!.participants.length == 1;
                          final challengeeName = (_race!.configuration['challengee_name'] as String?) ?? 'OPPONENT';

                          return Container(
                            decoration: BoxDecoration(
                              gradient: isWaitingOpponent
                                  ? const LinearGradient(colors: [Color(0xFF64748B), Color(0xFF475569)])
                                  : AppColors.greenGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: isWaitingOpponent ? null : AppColors.greenGlowShadow,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: (_isPerformingHostAction || isCountdown || isWaitingOpponent) ? null : _handleStartRaceNow,
                              icon: isWaitingOpponent
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.flash_on, size: 20, color: Colors.black),
                              label: Text(
                                isWaitingOpponent
                                    ? 'AWAITING ${challengeeName.toUpperCase()} TO ACCEPT...'
                                    : 'IGNITE ENGINES • START RACE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: isWaitingOpponent ? Colors.white : Colors.black,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: isWaitingOpponent ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    // READY toggle button
                    if (!isReady)
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.greenGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.greenGlowShadow,
                        ),
                        child: ElevatedButton(
                          onPressed: (_isTogglingReady || isCountdown) ? null : _toggleReady,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isTogglingReady
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text(
                                  'I AM READY ⚡',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.black),
                                ),
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: (_isTogglingReady || isCountdown) ? null : _toggleReady,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accentRose,
                          side: const BorderSide(color: AppColors.accentRose, width: 1.8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: AppColors.accentRose.withValues(alpha: 0.06),
                        ),
                        child: _isTogglingReady
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text(
                                'CANCEL READY',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                      ),
                  ],
                ),
              ),

              // Server-Authoritative Countdown Overlay
              if (isCountdown)
                Container(
                  color: Colors.black.withValues(alpha: 0.88),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'RACE STARTING IN',
                          style: TextStyle(
                            color: AppColors.accentAmber,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primaryGreen, width: 3),
                            boxShadow: AppColors.greenGlowShadow,
                            color: Colors.black,
                          ),
                          child: Center(
                            child: Text(
                              '$_countdownSeconds',
                              style: const TextStyle(
                                fontSize: 96,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryGreen,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Prepare to sprint! GPS location tracking active.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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
}
