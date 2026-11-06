import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchInvitations();
  }

  Future<void> _fetchInvitations() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await SupabaseService.client
          .from('race_invitations')
          .select('*, profiles:inviter_id(display_name), races:race_id(sport, mode, status)')
          .eq('invitee_id', user.id)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .timeout(const Duration(milliseconds: 1200));

      if (mounted) {
        setState(() {
          _invitations = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _respondInvitation(String inviteId, String raceId, bool accept) async {
    try {
      await SupabaseService.client
          .from('race_invitations')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', inviteId);

      if (accept) {
        await SupabaseService.client.rpc('join_race_secure', params: {'p_race_id': raceId});
        if (mounted) context.push('/lobby/$raceId');
      } else {
        _fetchInvitations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.notifications_active, color: AppColors.primaryGreen, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Race Invitations', style: AppTypography.titleLarge),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_invitations.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentRose,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_invitations.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _invitations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.borderHighlight),
                          ),
                          child: const Icon(Icons.mail_outline, size: 36, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 20),
                        const Text('No Pending Invites', style: AppTypography.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          'Race challenges from nearby racers\nwill appear here.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _fetchInvitations,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                            side: const BorderSide(color: AppColors.primaryGreen),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchInvitations,
                    color: AppColors.primaryGreen,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _invitations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final inv = _invitations[index];
                        String inviter = 'A nearby racer';
                        final prof = inv['profiles'];
                        if (prof is Map) {
                          inviter = prof['display_name'] as String? ?? 'A nearby racer';
                        } else if (prof is List && prof.isNotEmpty && prof.first is Map) {
                          inviter = (prof.first as Map)['display_name'] as String? ?? 'A nearby racer';
                        }

                        final r = inv['races'];
                        final race = r is Map ? r : (r is List && r.isNotEmpty && r.first is Map ? r.first as Map : null);
                        final sport = race?['sport'] ?? 'running';
                        final raceId = inv['race_id'] as String;

                        Color sportColor;
                        IconData sportIcon;
                        switch (sport.toString()) {
                          case 'cycling':
                            sportColor = AppColors.primaryCyan;
                            sportIcon = Icons.directions_bike;
                            break;
                          case 'motorbike':
                            sportColor = AppColors.accentAmber;
                            sportIcon = Icons.two_wheeler;
                            break;
                          default:
                            sportColor = AppColors.primaryGreen;
                            sportIcon = Icons.directions_run;
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.25)),
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: Column(
                            children: [
                              // Header with sport color
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: sportColor.withValues(alpha: 0.07),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                  ),
                                  border: Border(bottom: BorderSide(color: sportColor.withValues(alpha: 0.15))),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: sportColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(sportIcon, color: sportColor, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '⚡ $inviter challenged you!',
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            '${sport.toString().toUpperCase()} • Head-to-Head Race',
                                            style: TextStyle(color: sportColor, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'PENDING',
                                        style: TextStyle(
                                          color: AppColors.primaryGreen,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Action buttons
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _respondInvitation(inv['id'], raceId, false),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.textSecondary,
                                          side: const BorderSide(color: AppColors.borderHighlight),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: const Text('DECLINE', style: TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: AppColors.greenGradient,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: AppColors.greenGlowShadow,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: () => _respondInvitation(inv['id'], raceId, true),
                                          icon: const Icon(Icons.flash_on, size: 16),
                                          label: const Text('ACCEPT & JOIN', style: TextStyle(fontWeight: FontWeight.w900)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
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
                  ),
      ),
    );
  }
}
