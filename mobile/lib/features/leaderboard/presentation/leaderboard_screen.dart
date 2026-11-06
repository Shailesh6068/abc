import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSport = 'running';
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoading = true;
  bool _isUsingHallOfFameFallback = false;

  final Map<String, List<Map<String, dynamic>>> _hallOfFamePresets = {
    'running': [
      {'display_name': 'Apex_Speedster', 'rating': 2840, 'wins': 154, 'xp': 8420, 'is_bot': true},
      {'display_name': 'Neon_Pacer', 'rating': 2680, 'wins': 132, 'xp': 7150, 'is_bot': true},
      {'display_name': 'Velocity_Ghost', 'rating': 2510, 'wins': 110, 'xp': 5900, 'is_bot': true},
      {'display_name': 'Shadow_Striker', 'rating': 2390, 'wins': 89, 'xp': 4800, 'is_bot': true},
      {'display_name': 'Nitro_Stride', 'rating': 2280, 'wins': 74, 'xp': 3950, 'is_bot': true},
      {'display_name': 'Cyber_Track', 'rating': 2190, 'wins': 65, 'xp': 3400, 'is_bot': true},
      {'display_name': 'Fleet_Foot', 'rating': 2080, 'wins': 52, 'xp': 2850, 'is_bot': true},
    ],
    'cycling': [
      {'display_name': 'Aero_Rocket', 'rating': 2920, 'wins': 178, 'xp': 9200, 'is_bot': true},
      {'display_name': 'Tour_Dominator', 'rating': 2750, 'wins': 145, 'xp': 7800, 'is_bot': true},
      {'display_name': 'Carbon_Storm', 'rating': 2610, 'wins': 122, 'xp': 6400, 'is_bot': true},
      {'display_name': 'Peloton_King', 'rating': 2470, 'wins': 96, 'xp': 5100, 'is_bot': true},
      {'display_name': 'Sprint_Phantom', 'rating': 2340, 'wins': 81, 'xp': 4200, 'is_bot': true},
      {'display_name': 'Crank_Master', 'rating': 2210, 'wins': 68, 'xp': 3500, 'is_bot': true},
    ],
    'motorbike': [
      {'display_name': 'Redline_Demon', 'rating': 3100, 'wins': 210, 'xp': 11400, 'is_bot': true},
      {'display_name': 'Apex_Drifter', 'rating': 2890, 'wins': 165, 'xp': 8900, 'is_bot': true},
      {'display_name': 'Thunder_Grip', 'rating': 2720, 'wins': 138, 'xp': 7300, 'is_bot': true},
      {'display_name': 'Moto_Viper', 'rating': 2580, 'wins': 104, 'xp': 5600, 'is_bot': true},
      {'display_name': 'Neon_Rider', 'rating': 2430, 'wins': 87, 'xp': 4600, 'is_bot': true},
      {'display_name': 'Torque_Phantom', 'rating': 2290, 'wins': 72, 'xp': 3800, 'is_bot': true},
    ],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      HapticFeedback.selectionClick();
      setState(() {
        _selectedSport = ['running', 'cycling', 'motorbike'][_tabController.index];
      });
      _fetchLeaderboard();
    });
    _fetchLeaderboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeaderboard() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client
          .from('leaderboard_entries')
          .select('*, profiles(display_name, avatar_url)')
          .eq('sport', _selectedSport)
          .order('rating', ascending: false)
          .limit(50)
          .timeout(const Duration(milliseconds: 1500));

      final list = List<Map<String, dynamic>>.from(data);
      if (mounted) {
        if (list.isNotEmpty) {
          setState(() {
            _leaderboard = list;
            _isUsingHallOfFameFallback = false;
            _isLoading = false;
          });
        } else {
          setState(() {
            _leaderboard = _hallOfFamePresets[_selectedSport] ?? [];
            _isUsingHallOfFameFallback = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _leaderboard = _hallOfFamePresets[_selectedSport] ?? [];
          _isUsingHallOfFameFallback = true;
          _isLoading = false;
        });
      }
    }
  }

  String _extractName(Map<String, dynamic> item) {
    if (item.containsKey('display_name')) {
      return item['display_name'] as String? ?? 'Racer';
    }
    final prof = item['profiles'];
    if (prof is Map) {
      return prof['display_name'] as String? ?? 'Racer';
    } else if (prof is List && prof.isNotEmpty && prof.first is Map) {
      return (prof.first as Map)['display_name'] as String? ?? 'Racer';
    }
    return 'Racer';
  }

  @override
  Widget build(BuildContext context) {
    final top1 = _leaderboard.isNotEmpty ? _leaderboard[0] : null;
    final top2 = _leaderboard.length > 1 ? _leaderboard[1] : null;
    final top3 = _leaderboard.length > 2 ? _leaderboard[2] : null;
    final rest = _leaderboard.length > 3 ? _leaderboard.sublist(3) : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            backgroundColor: AppColors.surface,
            expandedHeight: 180,
            floating: false,
            pinned: true,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primaryGreen),
                tooltip: 'Refresh Rankings',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _fetchLeaderboard();
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppColors.surface,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 56),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 48), // Space for back button
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: AppColors.metallicGold,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.gold.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.emoji_events, color: Colors.black, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'LEADERBOARDS',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Text(
                              'Global Race Champions',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.primaryGreen,
                  indicatorWeight: 3,
                  labelColor: AppColors.primaryGreen,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'RUNNING', icon: Icon(Icons.directions_run, size: 16)),
                    Tab(text: 'CYCLING', icon: Icon(Icons.directions_bike, size: 16)),
                    Tab(text: 'MOTO', icon: Icon(Icons.two_wheeler, size: 16)),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryGreen),
                    SizedBox(height: 16),
                    Text(
                      'Loading Global Rankings...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchLeaderboard,
                color: AppColors.primaryGreen,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Hall of fame banner
                    if (_isUsingHallOfFameFallback)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.workspace_premium, color: AppColors.gold, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'PRO LEAGUE CHAMPIONSHIPS • HALL OF FAME',
                                style: TextStyle(
                                  color: Color(0xFF7B5800),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // PODIUM
                    if (top1 != null) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D1117), Color(0xFF1A1A2E)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '🏆 PODIUM CHAMPIONS',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: top2 != null
                                      ? _buildPodiumPedestal(item: top2, rank: 2, height: 115, color: AppColors.silver, medal: '🥈')
                                      : const SizedBox(),
                                ),
                                Expanded(
                                  child: _buildPodiumPedestal(
                                    item: top1,
                                    rank: 1,
                                    height: 155,
                                    color: AppColors.gold,
                                    medal: '🥇',
                                    isChampion: true,
                                  ),
                                ),
                                Expanded(
                                  child: top3 != null
                                      ? _buildPodiumPedestal(item: top3, rank: 3, height: 95, color: AppColors.bronze, medal: '🥉')
                                      : const SizedBox(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Rankings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GLOBAL CONTENDERS',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_leaderboard.length} RANKED',
                            style: const TextStyle(color: AppColors.primaryGreen, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ...rest.asMap().entries.map((entry) {
                      final rank = entry.key + 4;
                      final item = entry.value;
                      final name = _extractName(item);
                      final rating = (item['rating'] as num?)?.toInt() ?? 1200;
                      final xp = (item['xp'] as num?)?.toInt() ?? 0;
                      final wins = (item['wins'] as num?)?.toInt() ?? 0;
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

                      // Alternate subtle row background
                      final isEven = (rank % 2 == 0);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isEven ? AppColors.surface : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderSubtle),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            // Rank number
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.borderHighlight),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '#$rank',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Avatar
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3), width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  Text(
                                    '$wins Wins • $xp XP',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$rating',
                                  style: const TextStyle(color: AppColors.primaryCyan, fontWeight: FontWeight.w900, fontSize: 18),
                                ),
                                const Text(
                                  'RATING',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: AppColors.greenGradient,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.flash_on, color: Colors.white, size: 14),
                              ),
                              tooltip: 'Challenge $name',
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                context.push('/create-race?challengeName=${Uri.encodeComponent(name)}');
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPodiumPedestal({
    required Map<String, dynamic> item,
    required int rank,
    required double height,
    required Color color,
    required String medal,
    bool isChampion = false,
  }) {
    final name = _extractName(item);
    final rating = (item['rating'] as num?)?.toInt() ?? 1200;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isChampion)
          const Icon(Icons.workspace_premium, color: AppColors.gold, size: 28)
        else
          const SizedBox(height: 8),

        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: isChampion ? 60 : 48,
              height: isChampion ? 60 : 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: isChampion ? 2.5 : 2),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: isChampion ? 16 : 8),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: isChampion ? 24 : 18,
                ),
              ),
            ),
            Positioned(
              bottom: -6,
              right: -6,
              child: Text(medal, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isChampion ? AppColors.gold : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: isChampion ? 12 : 11,
            ),
          ),
        ),
        Text(
          '$rating',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: isChampion ? 13 : 11,
          ),
        ),
        const SizedBox(height: 8),

        // Podium block
        Container(
          width: double.infinity,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: isChampion ? 0.4 : 0.25), const Color(0xFF0D1117)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              Text(
                '#$rank',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: isChampion ? 26 : 20,
                ),
              ),
              if (isChampion)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'CHAMPION',
                    style: TextStyle(color: AppColors.gold, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
