import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
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
  RealtimeChannel? _realtimeChannel;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadRaceAndSubscribe();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
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
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _checkStateTransitions(RaceModel race) {
    if (race.status == 'COUNTDOWN') {
      _startCountdown();
    } else if (race.status == 'IN_PROGRESS') {
      _countdownTimer?.cancel();
      context.go('/live-race/${widget.raceId}');
    } else if (race.status == 'CANCELLED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This race was cancelled by the host.')),
      );
      context.go('/home');
    }
  }

  void _startCountdown() {
    if (_countdownTimer != null && _countdownTimer!.isActive) return;
    _countdownSeconds = 10;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        // Server transitions to IN_PROGRESS, redirecting participants
        context.go('/live-race/${widget.raceId}');
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _race == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final currentUserId = SupabaseService.currentUser?.id;
    final myPart = _race!.participants.where((p) => p.userId == currentUserId).firstOrNull;
    final isReady = myPart?.status == 'ready';
    final isCountdown = _race!.status == 'COUNTDOWN';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        title: Text('${_race!.sport.toUpperCase()} LOBBY', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Race Status Badge & Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _race!.mode.toUpperCase().replaceAll('_', ' '),
                                style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            Text(
                              '${_race!.participants.length} / ${_race!.participantLimit} RACERS',
                              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Sanctioned Course:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const Text('Marina Beach Sprint Circuit (1.0 km)', style: AppTypography.titleMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Participants List
                  const Text('RACERS IN LOBBY', style: AppTypography.labelSmall),
                  const SizedBox(height: 10),

                  Expanded(
                    child: ListView.separated(
                      itemCount: _race!.participants.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final p = _race!.participants[index];
                        final pReady = p.status == 'ready';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: pReady ? AppColors.primaryGreen : AppColors.borderSubtle,
                              width: pReady ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.surface,
                                child: Text(
                                  p.displayName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.displayName + (p.userId == currentUserId ? ' (You)' : ''),
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      pReady ? 'READY TO SPRINT' : 'Waiting in lobby...',
                                      style: TextStyle(
                                        color: pReady ? AppColors.primaryGreen : AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                pReady ? Icons.check_circle : Icons.hourglass_top,
                                color: pReady ? AppColors.primaryGreen : AppColors.accentAmber,
                                size: 24,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Readiness Action Button
                  ElevatedButton(
                    onPressed: (_isTogglingReady || isCountdown) ? null : _toggleReady,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isReady ? AppColors.accentRose : AppColors.primaryGreen,
                      foregroundColor: AppColors.textInverse,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isTogglingReady
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            isReady ? 'CANCEL READY' : 'I AM READY',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                  ),
                ],
              ),
            ),

            // Server-Authoritative Countdown Overlay
            if (isCountdown)
              Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'RACE STARTING IN',
                        style: TextStyle(color: AppColors.accentAmber, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.w900,
                          color: AppColors.timerGlow,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Prepare to move! Maintain safety at all times.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
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
