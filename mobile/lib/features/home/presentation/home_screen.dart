import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/features/ads/widgets/ad_banner_widget.dart';
import 'package:racezone/features/discovery/data/discovery_repository.dart';
import 'package:racezone/features/discovery/domain/player_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Position? _currentPosition;
  String _selectedSport = 'running';
  int _searchRadiusM = 500;
  List<NearbyPlayer> _nearbyPlayers = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  final List<int> _radii = [100, 200, 500, 1000, 2500];

  @override
  void initState() {
    super.initState();
    _initLocationAndFetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshPresence());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocationAndFetch() async {
    setState(() => _isLoading = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
      await _refreshPresence();
    } catch (e) {
      debugPrint('Location error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshPresence() async {
    if (_currentPosition == null) return;
    try {
      final repo = ref.read(discoveryRepositoryProvider);

      // Heartbeat update
      await repo.updatePresence(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        sport: _selectedSport,
        isAvailable: true,
      );

      // Fetch nearby competitors
      final players = await repo.getNearbyPlayers(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        radiusM: _searchRadiusM,
        sport: _selectedSport == 'all' ? null : _selectedSport,
      );

      if (mounted) {
        setState(() => _nearbyPlayers = players);
      }
    } catch (e) {
      debugPrint('Nearby fetch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flash_on, color: AppColors.primaryGreen, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('RaceZone', style: AppTypography.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined, color: AppColors.primaryGreen),
            tooltip: 'Leaderboards',
            onPressed: () => context.push('/leaderboards'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppColors.textPrimary),
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppColors.primaryCyan),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar (Sport & Radius)
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                // Sport Selector Tabs
                Row(
                  children: [
                    _buildSportChip('running', 'Running', Icons.directions_run),
                    const SizedBox(width: 8),
                    _buildSportChip('cycling', 'Cycling', Icons.directions_bike),
                    const SizedBox(width: 8),
                    _buildSportChip('motorbike', 'Motorbike', Icons.two_wheeler),
                  ],
                ),
                const SizedBox(height: 10),

                // Radius Selector Chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Radius:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    Row(
                      children: _radii.map((r) {
                        final isSel = _searchRadiusM == r;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6.0),
                          child: ChoiceChip(
                            label: Text(r < 1000 ? '${r}m' : '${(r / 1000).toStringAsFixed(0)}km'),
                            selected: isSel,
                            selectedColor: AppColors.primaryGreen,
                            backgroundColor: AppColors.surfaceElevated,
                            labelStyle: TextStyle(
                              color: isSel ? AppColors.textInverse : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (_) {
                              setState(() => _searchRadiusM = r);
                              _refreshPresence();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Map / Proximity Radar Section
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                // Stylized Dark Tactical Map / Radar Display
                Container(
                  color: const Color(0xFF0D131F),
                  width: double.infinity,
                  height: double.infinity,
                  child: CustomPaint(
                    painter: _RadarGridPainter(
                      playerCount: _nearbyPlayers.length,
                    ),
                  ),
                ),

                // GPS Status Badge
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGlass,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderHighlight),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.statusOnline,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentPosition != null ? 'GPS LOCKED' : 'SEARCHING GPS...',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Buttons Overlay
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () => context.push('/create-race'),
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.textInverse,
                    icon: const Icon(Icons.add_road),
                    label: const Text(
                      'CREATE RACE',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Nearby Players Drawer / Section
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'NEARBY RACERS (${_nearbyPlayers.length})',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_isLoading)
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          InkWell(
                            onTap: _refreshPresence,
                            child: const Text('Refresh', style: TextStyle(color: AppColors.primaryGreen, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.borderSubtle, height: 1),

                  Expanded(
                    child: _nearbyPlayers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.radar, color: AppColors.textMuted, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  'No ${_selectedSport} racers found within ${_searchRadiusM}m',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Expand your search radius or host a public race.',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _nearbyPlayers.length,
                            separatorBuilder: (_, __) => const Divider(color: AppColors.borderSubtle, height: 1),
                            itemBuilder: (context, index) {
                              final player = _nearbyPlayers[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.surfaceElevated,
                                  child: Text(
                                    player.displayName.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(player.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                subtitle: Row(
                                  children: [
                                    Text('Rating: ${player.rating}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Text('~${player.approxDistanceM}m away', style: const TextStyle(color: AppColors.primaryCyan, fontSize: 12)),
                                  ],
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    // Trigger race creation with direct challenge
                                    context.push('/create-race?challengeUser=${player.userId}&challengeName=${Uri.encodeComponent(player.displayName)}');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryGreen.withOpacity(0.15),
                                    foregroundColor: AppColors.primaryGreen,
                                    side: const BorderSide(color: AppColors.primaryGreen),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('CHALLENGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Safe Banner Ad container (only on Home, completely isolated from active race)
          const SafeAdBannerWidget(
            screenName: 'home',
            isLiveRacing: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSportChip(String sportId, String label, IconData icon) {
    final isSelected = _selectedSport == sportId;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedSport = sportId);
          _refreshPresence();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGreen : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? AppColors.textInverse : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.textInverse : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tactical Radar Painter for Discovery Map Background
class _RadarGridPainter extends CustomPainter {
  final int playerCount;

  _RadarGridPainter({required this.playerCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paintLine = Paint()
      ..color = const Color(0x1A00E676)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final paintCenter = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.fill;

    // Concentric discovery rings
    canvas.drawCircle(center, size.width * 0.15, paintLine);
    canvas.drawCircle(center, size.width * 0.30, paintLine);
    canvas.drawCircle(center, size.width * 0.45, paintLine);

    // Crosshairs
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paintLine);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paintLine);

    // User Center Marker
    canvas.drawCircle(center, 6, paintCenter);

    // Draw stylized nearby competitor blips
    final blipPaint = Paint()..color = AppColors.primaryCyan..style = PaintingStyle.fill;
    for (int i = 0; i < playerCount; i++) {
      final angle = (i * 2.399) % (2 * 3.14159);
      final dist = (size.width * 0.12) + (i * 28.0) % (size.width * 0.32);
      final offset = Offset(center.dx + dist * 0.8 * (i % 2 == 0 ? 1 : -1), center.dy + dist * 0.6 * (i % 3 == 0 ? 1 : -1));
      canvas.drawCircle(offset, 4.5, blipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarGridPainter oldDelegate) => oldDelegate.playerCount != playerCount;
}
