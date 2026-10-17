import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/auth/data/auth_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _achievements = [];
  bool _isLoading = true;
  bool _discoveryEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final pData = await SupabaseService.client
          .from('profiles')
          .select('*, player_preferences(*)')
          .eq('id', user.id)
          .maybeSingle();

      final aData = await SupabaseService.client
          .from('user_achievements')
          .select('*, achievements(*)')
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          _profile = pData;
          _achievements = List<Map<String, dynamic>>.from(aData ?? []);
          _discoveryEnabled = pData?['player_preferences']?['discovery_enabled'] ?? true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDiscovery(bool enabled) async {
    setState(() => _discoveryEnabled = enabled);
    final user = SupabaseService.currentUser;
    if (user != null) {
      await SupabaseService.client.from('player_preferences').upsert({
        'user_id': user.id,
        'discovery_enabled': enabled,
      });
    }
  }

  Future<void> _handleSignOut() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Account?', style: TextStyle(color: AppColors.accentRose)),
        content: const Text(
          'This will permanently delete your racing profile, rankings, and achievements. This action cannot be undone.',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRose),
            child: const Text('CONFIRM DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = SupabaseService.currentUser;
      if (user != null) {
        await SupabaseService.client.from('profiles').update({'account_status': 'deactivated'}).eq('id', user.id);
        await _handleSignOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final displayName = _profile?['display_name'] ?? 'Racer';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        title: const Text('Racer Profile & Safety', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Avatar & Name Card
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primaryGreen, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        displayName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(displayName, style: AppTypography.titleLarge),
                    const SizedBox(height: 4),
                    const Text('Status: Active Racer • Level 4', style: TextStyle(color: AppColors.primaryCyan, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Unlocked Achievements
              const Text('EARNED ACHIEVEMENTS', style: AppTypography.labelSmall),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: _achievements.isEmpty
                    ? const Text('Complete your first official race to unlock badges!', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                    : Column(
                        children: _achievements.map((a) {
                          final ach = a['achievements'];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              children: [
                                const Icon(Icons.military_tech, color: AppColors.primaryGreen, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ach?['name'] ?? 'Achievement', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                      Text(ach?['description'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 24),

              // Privacy & Matchmaking Controls
              const Text('PRIVACY & DISCOVERY CONTROLS', style: AppTypography.labelSmall),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _discoveryEnabled,
                      activeColor: AppColors.primaryGreen,
                      title: const Text('Discoverable by Nearby Racers', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      subtitle: const Text('Approximate distance shown only. Exact GPS is never shared.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      onChanged: _toggleDiscovery,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Sign Out Button
              OutlinedButton(
                onPressed: _handleSignOut,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderHighlight),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('SIGN OUT', style: TextStyle(color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 12),

              // Delete Account (App Store & GDPR requirement)
              TextButton(
                onPressed: _deleteAccount,
                child: const Text('Delete Account & Wipe Data', style: TextStyle(color: AppColors.accentRose, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
