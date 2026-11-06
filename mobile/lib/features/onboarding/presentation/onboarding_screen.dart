import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_strings.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/network/supabase_client.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final Set<String> _selectedSports = {'running'};
  bool _discoveryEnabled = true;
  int _searchRadiusM = 500;
  bool _safetyAgreed = false;
  bool _isSaving = false;

  Future<void> _requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      await Permission.locationAlways.request();
    }
  }

  Future<void> _completeOnboarding() async {
    if (!_safetyAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Please acknowledge the mandatory safety agreement below.')),
            ],
          ),
          backgroundColor: AppColors.accentRose,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Save preferences locally so onboarding NEVER blocks offline or during DNS failure
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('preferred_sports', _selectedSports.toList());
        await prefs.setBool('discovery_enabled', _discoveryEnabled);
        await prefs.setInt('preferred_radius_m', _searchRadiusM);
        await prefs.setBool('onboarding_completed', true);
      } catch (prefError) {
        debugPrint('[Onboarding] Local prefs save note: $prefError');
      }

      // 2. Best-effort Supabase sync with fast timeout (swallows offline/DNS socket exceptions)
      try {
        final user = SupabaseService.currentUser;
        if (user != null) {
          await SupabaseService.client.from('player_preferences').upsert({
            'user_id': user.id,
            'preferred_sports': _selectedSports.toList(),
            'discovery_enabled': _discoveryEnabled,
            'preferred_radius_m': _searchRadiusM,
            'privacy_settings': {
              'hide_exact_location': true,
              'allow_race_invites_from': 'everyone',
            },
          }).timeout(const Duration(milliseconds: 1200));
        }
      } catch (remoteError) {
        debugPrint('[Onboarding] Supabase offline/unreachable ($remoteError). Proceeding with local profile.');
      }

      // 3. Request location permission
      try {
        await _requestLocationPermission();
      } catch (permError) {
        debugPrint('[Onboarding] Permission request note: $permError');
      }

      // 4. Smoothly enter the main game hub
      if (mounted) {
        context.go('/home');
      }
    } catch (unexpectedError) {
      debugPrint('[Onboarding] Unexpected error: $unexpectedError');
      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Dark game-style hero header
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 24,
                left: 24,
                right: 24,
                bottom: 28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1117), Color(0xFF16213E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.greenGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.tune, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Racer Setup',
                            style: AppTypography.titleLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Customize your racing profile',
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildHeaderStep(1, 'Sport', true),
                      _buildStepDivider(),
                      _buildHeaderStep(2, 'Discovery', true),
                      _buildStepDivider(),
                      _buildHeaderStep(3, 'Safety', _safetyAgreed),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Section: Select Sports
                _buildSectionHeader('YOUR DISCIPLINES', Icons.sports, AppColors.primaryGreen),
                const SizedBox(height: 12),
                _buildSportCard('running', AppStrings.sportRunning, Icons.directions_run, AppColors.sportRunning),
                const SizedBox(height: 10),
                _buildSportCard('cycling', AppStrings.sportCycling, Icons.directions_bike, AppColors.sportCycling),
                const SizedBox(height: 10),
                _buildSportCard('motorbike', AppStrings.sportMotorbike, Icons.two_wheeler, AppColors.sportMotorbike),
                const SizedBox(height: 28),

                // Discovery Toggle
                _buildSectionHeader('DISCOVERY SETTINGS', Icons.radar, AppColors.primaryCyan),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _discoveryEnabled,
                        onChanged: (val) => setState(() => _discoveryEnabled = val),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Nearby Competitor Discovery', style: AppTypography.titleMedium),
                        subtitle: const Text(
                          'Allow nearby racers to find and challenge you.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        secondary: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryCyan.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.radar, color: AppColors.primaryCyan, size: 22),
                        ),
                      ),
                      if (_discoveryEnabled) ...[
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Search Radius:', style: TextStyle(color: AppColors.textSecondary)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: AppColors.cyanGradient,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _searchRadiusM < 1000 ? '$_searchRadiusM m' : '${(_searchRadiusM / 1000).toStringAsFixed(1)} km',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Slider(
                            value: _searchRadiusM.toDouble(),
                            min: 100,
                            max: 3000,
                            divisions: 29,
                            onChanged: (val) => setState(() => _searchRadiusM = val.toInt()),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Safety Card
                _buildSectionHeader('SAFETY AGREEMENT', Icons.shield_outlined, AppColors.accentRose),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _safetyAgreed ? AppColors.accentRose.withValues(alpha: 0.5) : AppColors.accentRose.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accentRose.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.warning_amber_rounded, color: AppColors.accentRose, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'MANDATORY SAFETY POLICY',
                            style: TextStyle(
                              color: AppColors.accentRose,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.accentRose.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          AppStrings.safetyWarningBody,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => setState(() => _safetyAgreed = !_safetyAgreed),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _safetyAgreed ? AppColors.accentRose : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _safetyAgreed ? AppColors.accentRose : AppColors.borderHighlight,
                                  width: 2,
                                ),
                              ),
                              child: _safetyAgreed
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'I agree to follow all road safety laws and never operate my device while moving.',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // CTA button
                Container(
                  decoration: BoxDecoration(
                    gradient: _safetyAgreed ? AppColors.greenGradient : null,
                    color: _safetyAgreed ? null : AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _safetyAgreed ? AppColors.greenGlowShadow : null,
                  ),
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _completeOnboarding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: _safetyAgreed ? Colors.white : AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSaving
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.rocket_launch, size: 22),
                              SizedBox(width: 10),
                              Text(
                                'ENTER RACEZONE',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStep(int step, String label, bool active) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryGreen : Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$step',
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 20,
        height: 1.5,
        color: Colors.white.withValues(alpha: 0.2),
      ),
    );
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

  Widget _buildSportCard(String id, String label, IconData icon, Color color) {
    final isSelected = _selectedSports.contains(id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            if (_selectedSports.length > 1) _selectedSports.remove(id);
          } else {
            _selectedSports.add(id);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.07) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.borderSubtle,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))]
              : AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(colors: [color.withValues(alpha: 0.8), color])
                    : null,
                color: isSelected ? null : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : AppColors.textMuted, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  if (isSelected)
                    Text(
                      'SELECTED',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : AppColors.borderHighlight,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 15)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
