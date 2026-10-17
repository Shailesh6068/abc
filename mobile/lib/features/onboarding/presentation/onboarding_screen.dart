import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
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
      // Prompt for background location if possible
      await Permission.locationAlways.request();
    }
  }

  Future<void> _completeOnboarding() async {
    if (!_safetyAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please acknowledge the safety agreement.')),
      );
      return;
    }

    setState(() => _isSaving = true);

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
        });
      }

      await _requestLocationPermission();

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving preferences: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text('Racer Setup', style: AppTypography.displayLarge),
              const SizedBox(height: 6),
              const Text(
                'Customize your preferred sports and discovery profile',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 32),

              // Sport Selection
              const Text('SELECT YOUR SPORTS', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              _buildSportCard('running', AppStrings.sportRunning, Icons.directions_run, AppColors.sportRunning),
              const SizedBox(height: 10),
              _buildSportCard('cycling', AppStrings.sportCycling, Icons.directions_bike, AppColors.sportCycling),
              const SizedBox(height: 10),
              _buildSportCard('motorbike', AppStrings.sportMotorbike, Icons.two_wheeler, AppColors.sportMotorbike),
              const SizedBox(height: 28),

              // Discovery Toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _discoveryEnabled,
                      onChanged: (val) => setState(() => _discoveryEnabled = val),
                      activeColor: AppColors.primaryGreen,
                      title: const Text('Nearby Competitor Discovery', style: AppTypography.titleMedium),
                      subtitle: const Text(
                        'Allows nearby racers to find and challenge you within your selected radius.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                    if (_discoveryEnabled) ...[
                      const Divider(color: AppColors.borderSubtle, height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Search Radius:', style: TextStyle(color: AppColors.textSecondary)),
                          Text(
                            _searchRadiusM < 1000 ? '$_searchRadiusM m' : '${(_searchRadiusM / 1000).toStringAsFixed(1)} km',
                            style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Slider(
                        value: _searchRadiusM.toDouble(),
                        min: 100,
                        max: 3000,
                        divisions: 29,
                        activeColor: AppColors.primaryGreen,
                        inactiveColor: AppColors.borderSubtle,
                        onChanged: (val) => setState(() => _searchRadiusM = val.toInt()),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Safety & Rules Notice Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accentRose.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accentRose.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.accentRose),
                        SizedBox(width: 8),
                        Text('MANDATORY SAFETY POLICY', style: TextStyle(color: AppColors.accentRose, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppStrings.safetyWarningBody,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _safetyAgreed,
                      onChanged: (val) => setState(() => _safetyAgreed = val ?? false),
                      activeColor: AppColors.accentRose,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I agree to adhere strictly to all road safety regulations, never glance at my phone while moving, and only conduct motorbike events on closed tracks.',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Finish Button
              ElevatedButton(
                onPressed: _isSaving ? null : _completeOnboarding,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.textInverse,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ENTER RACEZONE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportCard(String id, String label, IconData icon, Color color) {
    final isSelected = _selectedSports.contains(id);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            if (_selectedSports.length > 1) _selectedSports.remove(id);
          } else {
            _selectedSports.add(id);
          }
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : AppColors.borderSubtle, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : AppColors.textSecondary, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 22)
            else
              const Icon(Icons.circle_outlined, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
