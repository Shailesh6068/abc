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

  Future<void> _fetchOfficialResults([int attempt = 0]) async {
    try {
      final data = await SupabaseService.client
          .from('race_results')
          .select('*, profiles(display_name, avatar_url)')
          .eq('race_id', widget.raceId)
          .order('rank', ascending: true)
          .timeout(const Duration(milliseconds: 1500));

      final currentUserId = SupabaseService.currentUser?.id;
      final resultsList = List<Map<String, dynamic>>.from(data);

      if (resultsList.isEmpty && attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          await _fetchOfficialResults(attempt + 1);
          return;
        }
      }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flag_outlined, color: AppColors.accentAmber, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Dispute Result', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If you noticed GPS spoofing or foul play, submit a report for review by our moderation panel.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: AppTypography.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Describe the issue...',
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              reasonController.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.greenGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isNotEmpty) {
                  try {
                    await SupabaseService.client.from('moderation_reports').insert({
                      'reporter_id': SupabaseService.currentUser?.id,
                      'race_id': widget.raceId,
                      'category': 'suspicious_results',
                      'description': reason,
                      'status': 'OPEN',
                    });
                    if (ctx.mounted) {
                      reasonController.dispose();
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dispute submitted for admin review.')),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      reasonController.dispose();
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not submit dispute: $e')),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('SUBMIT', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
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
    final isWinner = myRank == 1;
    final xpEarned = myRank == 1 ? 100 : (myRank == 2 ? 60 : (myRank == 3 ? 40 : 20));

    // Colors based on placement
    final rankColor = myRank == 1 ? AppColors.gold : (myRank == 2 ? AppColors.silver : (myRank == 3 ? AppColors.bronze : AppColors.primaryCyan));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Victory/Result hero banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      decoration: BoxDecoration(
                        gradient: isWinner
                            ? const LinearGradient(
                                colors: [Color(0xFF0D1117), Color(0xFF1A1A2E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF0D1117), Color(0xFF16213E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Trophy / icon
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: rankColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: rankColor, width: 2.5),
                              boxShadow: [
                                BoxShadow(color: rankColor.withValues(alpha: 0.4), blurRadius: 24),
                              ],
                            ),
                            child: Icon(
                              isPodium ? Icons.emoji_events : Icons.sports_score,
                              color: rankColor,
                              size: 46,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isWinner ? '🏆 VICTORY!' : (isPodium ? '🎉 PODIUM FINISH!' : 'RACE COMPLETE'),
                            style: AppTypography.displayLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: isWinner ? 34 : 28,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Official Verified Result • $myRank${myRank == 1 ? "st" : (myRank == 2 ? "nd" : (myRank == 3 ? "rd" : "th"))} Place',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(height: 20),

                          // XP + Distance stats
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('XP EARNED', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                      const SizedBox(height: 6),
                                      Text(
                                        '+$xpEarned XP',
                                        style: const TextStyle(color: AppColors.primaryGreen, fontSize: 22, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('DISTANCE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                      const SizedBox(height: 6),
                                      Text(
                                        GeoUtils.formatDistance((_userResult?['verified_distance_m'] as num?)?.toDouble() ?? 1000.0),
                                        style: const TextStyle(color: AppColors.primaryCyan, fontSize: 22, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Results table
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.format_list_numbered, color: AppColors.primaryGreen, size: 16),
                              ),
                              const SizedBox(width: 8),
                              const Text('OFFICIAL RESULTS', style: AppTypography.labelSmall),
                            ],
                          ),
                          const SizedBox(height: 14),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              final rank = (r['rank'] as num?)?.toInt() ?? (index + 1);
                              String name = 'Racer';
                              final prof = r['profiles'];
                              if (prof is Map) {
                                name = prof['display_name'] as String? ?? 'Racer';
                              } else if (prof is List && prof.isNotEmpty && prof.first is Map) {
                                name = (prof.first as Map)['display_name'] as String? ?? 'Racer';
                              }
                              name = name.trim().isEmpty ? 'Racer' : name;
                              final elapsedMs = (r['elapsed_ms'] as num?)?.toInt() ?? 0;
                              final duration = Duration(milliseconds: elapsedMs);
                              final isMe = r['user_id'] == SupabaseService.currentUser?.id;

                              Color podiumColor = AppColors.borderSubtle;
                              if (rank == 1) podiumColor = AppColors.gold;
                              if (rank == 2) podiumColor = AppColors.silver;
                              if (rank == 3) podiumColor = AppColors.bronze;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? AppColors.primaryGreen.withValues(alpha: 0.06)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isMe
                                        ? AppColors.primaryGreen.withValues(alpha: 0.4)
                                        : (rank <= 3 ? podiumColor.withValues(alpha: 0.4) : AppColors.borderSubtle),
                                    width: isMe ? 1.5 : 1,
                                  ),
                                  boxShadow: AppColors.cardShadow,
                                ),
                                child: Row(
                                  children: [
                                    // Rank badge
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: rank <= 3 ? podiumColor.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: rank <= 3 ? podiumColor : AppColors.borderHighlight,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$rank',
                                        style: TextStyle(
                                          color: rank <= 3 ? podiumColor : AppColors.textSecondary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: isMe ? FontWeight.w900 : FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (isMe) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primaryGreen,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'YOU',
                                                style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      GeoUtils.formatDuration(duration),
                                      style: const TextStyle(
                                        color: AppColors.primaryGreen,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (rank <= 3)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text(
                                          rank == 1 ? '🥇' : (rank == 2 ? '🥈' : '🥉'),
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Dispute
                          Center(
                            child: TextButton.icon(
                              onPressed: _showDisputeDialog,
                              icon: const Icon(Icons.flag_outlined, color: AppColors.textMuted, size: 16),
                              label: const Text(
                                'Dispute Result / Report Cheating',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Ad banner
            const SafeAdBannerWidget(screenName: 'results', isLiveRacing: false),

            // Return home button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.greenGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.greenGlowShadow,
                ),
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home, size: 20),
                  label: const Text(
                    'RETURN TO HOME',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
