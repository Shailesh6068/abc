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
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('race_invitations')
          .select('*, profiles:inviter_id(display_name), races:race_id(sport, mode, status)')
          .eq('invitee_id', user.id)
          .eq('status', 'pending')
          .order('created_at', {ascending: false});

      if (mounted) {
        setState(() {
          _invitations = List<Map<String, dynamic>>.from(data ?? []);
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
        title: const Text('Race Invitations', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _invitations.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mail_outline, size: 48, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No pending race invites', style: TextStyle(color: AppColors.textSecondary)),
                        SizedBox(height: 4),
                        Text('Nearby challenges will appear here.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _invitations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final inv = _invitations[index];
                      final inviter = inv['profiles']?['display_name'] ?? 'A nearby racer';
                      final race = inv['races'];
                      final sport = race?['sport'] ?? 'running';
                      final raceId = inv['race_id'] as String;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primaryGreen.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.flash_on, color: AppColors.primaryGreen, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  '$inviter challenged you!',
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Discipline: ${sport.toString().toUpperCase()} • Head-to-Head',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _respondInvitation(inv['id'], raceId, false),
                                  child: const Text('DECLINE', style: TextStyle(color: AppColors.textMuted)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _respondInvitation(inv['id'], raceId, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryGreen,
                                    foregroundColor: AppColors.textInverse,
                                  ),
                                  child: const Text('ACCEPT & JOIN', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
