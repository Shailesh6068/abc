import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/core/utils/geo_utils.dart';
import 'package:racezone/features/ads/widgets/ad_banner_widget.dart';

class RaceResultsScreen extends ConsumerStatefulWidget {
  final String raceId;

  const RaceResultsScreen({super.key, required this.raceId});

  @override
  ConsumerState<RaceResultsScreen> createState() => _RaceResultsScreenState();
}

class _RaceResultsScreenState extends ConsumerState<RaceResultsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _userResult;

  @override
  void initState() {
    super.initState();
    _fetchOfficialResults();
  }

  Future<void> _fetchOfficialResults() async {
    try {
      final data = await SupabaseService.client
          .from('race_results')
          .select('*, profiles(display_name, avatar_url)')
          .eq('race_id', widget.raceId)
          .order('rank', {ascending: true});

      final currentUserId = SupabaseService.currentUser?.id;
      final resultsList = List<Map<String, dynamic>>.from(data);
      final myRes = resultsList.where((r) => r['user_id'] == currentUserId).firstOrNull;

      if (mounted) {
        setState(() {
          _results = resultsList;
          _userResult = myRes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDisputeDialog() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Dispute Result', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If you noticed GPS spoofing or foul play, submit a report for review by our moderation panel.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Describe the issue...',
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isNotEmpty) {
                await SupabaseService.client.from('moderation_reports').insert({
                  'reporter_id': SupabaseService.currentUser?.id,
                  'race_id': widget.raceId,
                  'category': 'suspicious_results',
                  'description': reasonController.text.trim(),
                  'status': 'OPEN',
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dispute submitted for admin review.')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: const Text('SUBMIT DISPUTE', style: TextStyle(color: AppColors.textInverse)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final myRank = _userResult?['rank'] ?? 1;
    final isPodium = myRank <= 3;
    final xpEarned = myRank == 1 ? 100 : (myRank == 2 ? 60 : (myRank == 3 ? 40 : 20));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Podium Banner Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isPodium ? AppColors.primaryGreen.withOpacity(0.15) : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isPodium ? AppColors.primaryGreen : AppColors.borderHighlight,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isPodium ? Icons.emoji_events : Icons.sports_score,
                        color: isPodium ? AppColors.primaryGreen : AppColors.textSecondary,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      myRank == 1 ? 'VICTORY!' : 'RACE COMPLETE',
                      style: AppTypography.displayLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Official Verified Standings • Stage $myRank${myRank == 1 ? "st" : (myRank == 2 ? "nd" : (myRank == 3 ? "rd" : "th"))} Place',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // User Summary Card (XP & Distance)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('XP EARNED', style: AppTypography.labelSmall),
                              const SizedBox(height: 4),
                              Text('+$xpEarned XP', style: const TextStyle(color: AppColors.primaryGreen, fontSize: 22, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(width: 1, height: 40, color: AppColors.borderSubtle),
                          Column(
                            children: [
                              const Text('VERIFIED DISTANCE', style: AppTypography.labelSmall),
                              const SizedBox(height: 4),
                              Text(
                                GeoUtils.formatDistance((_userResult?['verified_distance_m'] as num?)?.toDouble() ?? 1000.0),
                                style: const TextStyle(color: AppColors.primaryCyan, fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Full Standings Table
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('OFFICIAL RESULTS TABLE', style: AppTypography.labelSmall),
                    ),
                    const SizedBox(height: 10),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final r = _results[index];
                        final rank = r['rank'] as int? ?? (index + 1);
                        final name = r['profiles']?['display_name'] ?? 'Racer';
                        final elapsedMs = r['elapsed_ms'] as int? ?? 0;
                        final duration = Duration(milliseconds: elapsedMs);

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: rank == 1 ? AppColors.primaryGreen : AppColors.borderSubtle,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: rank == 1
                                      ? AppColors.primaryGreen
                                      : (rank == 2 ? AppColors.primaryCyan : AppColors.surface),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$rank',
                                  style: TextStyle(
                                    color: rank <= 2 ? AppColors.textInverse : AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              Text(
                                GeoUtils.formatDuration(duration),
                                style: const TextStyle(
                                  color: AppColors.timerGlow,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Dispute action
                    TextButton.icon(
                      onPressed: _showDisputeDialog,
                      icon: const Icon(Icons.flag_outlined, color: AppColors.textMuted, size: 18),
                      label: const Text('Dispute Result / Report Cheating', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),

            // Safe Banner Ad below results (Post-race only!)
            const SafeAdBannerWidget(
              screenName: 'results',
              isLiveRacing: false,
            ),

            // Bottom Return Button
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.textInverse,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('RETURN TO HOME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
