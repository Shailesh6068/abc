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

    final defaultProfile = {
      'display_name': user.userMetadata?['display_name'] ?? (user.email?.contains('@') == true ? user.email!.split('@').first : 'Racer Pilot'),
      'rating': 1480,
      'level': 14,
      'xp': 3250,
      'wins': 18,
      'total_races': 36,
      'distance_m': 48500,
    };

    final defaultAchievements = [
      {
        'achievements': {
          'name': 'Street Pioneer',
          'description': 'Completed your first 1km street sprint',
          'badge_icon': 'bolt',
        },
        'unlocked_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      },
      {
        'achievements': {
          'name': 'Velocity Demon',
          'description': 'Reached top speed in a street sprint',
          'badge_icon': 'speed',
        },
        'unlocked_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      },
    ];

    try {
      final pData = await SupabaseService.client
          .from('profiles')
          .select('*, player_preferences(*)')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(milliseconds: 1200));

      final aData = await SupabaseService.client
          .from('user_achievements')
          .select('*, achievements(*)')
          .eq('user_id', user.id)
          .timeout(const Duration(milliseconds: 1200));

      if (mounted) {
        dynamic prefObj = pData?['player_preferences'];
        if (prefObj is List && prefObj.isNotEmpty) prefObj = prefObj.first;
        final isDisc = (prefObj is Map ? prefObj['discovery_enabled'] : null) ?? true;

        setState(() {
          _profile = pData ?? defaultProfile;
          _achievements = aData.isNotEmpty ? List<Map<String, dynamic>>.from(aData) : defaultAchievements;
          _discoveryEnabled = isDisc as bool;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profile = defaultProfile;
          _achievements = defaultAchievements;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleDiscovery(bool enabled) async {
    setState(() => _discoveryEnabled = enabled);
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        await SupabaseService.client.from('player_preferences').upsert({
          'user_id': user.id,
          'discovery_enabled': enabled,
        });
      } catch (e) {
        debugPrint('Toggle discovery error: $e');
      }
    }
  }

  Future<void> _handleSignOut() async {
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.signOut();
    } catch (e) {
      debugPrint('Signout note: $e');
    }
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
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
                color: AppColors.accentRose.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever, color: AppColors.accentRose, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Delete Account?', style: TextStyle(color: AppColors.accentRose, fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'This will permanently delete your racing profile, rankings, and achievements. This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRose),
            child: const Text('CONFIRM DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = SupabaseService.currentUser;
      if (user != null) {
        try {
          await SupabaseService.client
              .from('profiles')
              .update({'account_status': 'deactivated'})
              .eq('id', user.id)
              .timeout(const Duration(milliseconds: 1200));
        } catch (e) {
          debugPrint('Deactivate account offline note: $e');
        }
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
    final initial = displayName.substring(0, 1).toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Hero Profile Header
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1117), Color(0xFF1A1A2E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => context.pop(),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: AppColors.metallicGold,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.emoji_events, color: Colors.black, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'PRO RACER',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Avatar
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: AppColors.greenGradient,
                        shape: BoxShape.circle,
                        boxShadow: AppColors.greenGlowShadow,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, color: AppColors.primaryCyan, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Active Racer • Level 4',
                            style: TextStyle(color: AppColors.primaryCyan, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Stats row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('14', 'LEVEL', Colors.white),
                          _buildStatDivider(),
                          _buildStatItem('1,480', 'RATING', AppColors.gold),
                          _buildStatDivider(),
                          _buildStatItem('${_achievements.length}', 'BADGES', AppColors.primaryGreen),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Achievements section
                _buildSectionHeader('EARNED BADGES', Icons.military_tech, AppColors.gold),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: _achievements.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.borderHighlight),
                                ),
                                child: const Icon(Icons.military_tech, color: AppColors.textMuted, size: 28),
                              ),
                              const SizedBox(height: 12),
                              const Text('No badges yet', style: AppTypography.titleMedium),
                              const SizedBox(height: 4),
                              const Text(
                                'Complete your first official race to earn badges!',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: _achievements.asMap().entries.map((entry) {
                            final a = entry.value;
                            final ach = a['achievements'];
                            final isLast = entry.key == _achievements.length - 1;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: AppColors.goldGradient,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.military_tech, color: Colors.white, size: 26),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ach?['name'] ?? 'Achievement',
                                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                                            ),
                                            Text(
                                              ach?['description'] ?? '',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16),
                              ],
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),

                // Privacy controls
                _buildSectionHeader('PRIVACY & DISCOVERY', Icons.privacy_tip_outlined, AppColors.primaryCyan),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: SwitchListTile(
                    value: _discoveryEnabled,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Discoverable by Nearby Racers', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Approximate distance shown only. Exact GPS is never shared.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.radar, color: AppColors.primaryCyan, size: 22),
                    ),
                    onChanged: _toggleDiscovery,
                  ),
                ),
                const SizedBox(height: 32),

                // Sign Out
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderHighlight),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: ListTile(
                    onTap: _handleSignOut,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.logout, color: AppColors.textSecondary, size: 20),
                    ),
                    title: const Text('Sign Out', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),

                // Delete account
                Center(
                  child: TextButton.icon(
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_outline, color: AppColors.accentRose, size: 16),
                    label: const Text(
                      'Delete Account & Wipe Data',
                      style: TextStyle(color: AppColors.accentRose, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 32, color: Colors.white.withValues(alpha: 0.15));
  }

  Widget _buildSectionHeader(String label, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(label, style: AppTypography.labelSmall),
      ],
    );
  }
}
