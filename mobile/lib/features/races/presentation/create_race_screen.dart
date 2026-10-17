import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_strings.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/features/races/data/race_repository.dart';

class CreateRaceScreen extends ConsumerStatefulWidget {
  final String? challengeUserId;
  final String? challengeUserName;

  const CreateRaceScreen({
    super.key,
    this.challengeUserId,
    this.challengeUserName,
  });

  @override
  ConsumerState<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends ConsumerState<CreateRaceScreen> {
  String _selectedSport = 'running';
  String _selectedMode = 'time_trial';
  int _participantLimit = 4;
  int _durationMinutes = 10;
  int _targetDistanceM = 1000;
  String _visibility = 'public';
  bool _isCreating = false;

  final Map<String, String> _sampleRoutes = {
    '11111111-1111-1111-1111-111111111111': 'Marina Beach Sprint (1.0 km)',
    '22222222-2222-2222-2222-222222222222': 'Coastal Highway Loop (5.0 km)',
    '33333333-3333-3333-3333-333333333333': 'Apex Speedway Closed Track (3.2 km)',
  };
  late String _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _selectedRouteId = _sampleRoutes.keys.first;
    if (widget.challengeUserId != null) {
      _selectedMode = 'head_to_head';
      _participantLimit = 2;
    }
  }

  Future<void> _handleCreateRace() async {
    setState(() => _isCreating = true);
    try {
      final repo = ref.read(raceRepositoryProvider);
      final raceId = await repo.createRace(
        sport: _selectedSport,
        mode: _selectedMode,
        visibility: _visibility,
        participantLimit: _participantLimit,
        routeId: _selectedRouteId,
        configuration: {
          'duration_minutes': _selectedMode == 'time_trial' ? _durationMinutes : null,
          'target_distance_m': _selectedMode != 'time_trial' ? _targetDistanceM : null,
          'challengee_id': widget.challengeUserId,
        },
      );

      if (mounted) {
        context.go('/lobby/$raceId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create race: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create GPS Race', style: AppTypography.titleLarge),
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
              if (widget.challengeUserName != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryCyan.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_kabaddi, color: AppColors.primaryCyan),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Direct Challenge to ${widget.challengeUserName}!',
                          style: const TextStyle(color: AppColors.primaryCyan, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // Sport Selection
              const Text('DISCIPLINE', style: AppTypography.labelSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildSportOption('running', 'Running', Icons.directions_run),
                  const SizedBox(width: 8),
                  _buildSportOption('cycling', 'Cycling', Icons.directions_bike),
                  const SizedBox(width: 8),
                  _buildSportOption('motorbike', 'Motorbike', Icons.two_wheeler),
                ],
              ),
              const SizedBox(height: 24),

              // Race Mode
              const Text('RACE MODE', style: AppTypography.labelSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildModeOption('time_trial', 'Time Trial'),
                  const SizedBox(width: 8),
                  _buildModeOption('distance_race', 'Distance Sprint'),
                  const SizedBox(width: 8),
                  _buildModeOption('head_to_head', 'Head-to-Head'),
                ],
              ),
              const SizedBox(height: 24),

              // Mode Specific Parameters
              if (_selectedMode == 'time_trial') ...[
                const Text('TIME INTERVAL (SERVER-CONTROLLED)', style: AppTypography.labelSmall),
                const SizedBox(height: 8),
                Row(
                  children: [5, 10, 15, 30].map((mins) {
                    final isSel = _durationMinutes == mins;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('$mins Mins'),
                        selected: isSel,
                        selectedColor: AppColors.primaryGreen,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: isSel ? AppColors.textInverse : AppColors.textSecondary,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _durationMinutes = mins),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ] else ...[
                const Text('COURSE DISTANCE', style: AppTypography.labelSmall),
                const SizedBox(height: 8),
                Row(
                  children: [1000, 3000, 5000, 10000].map((dist) {
                    final isSel = _targetDistanceM == dist;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('${dist / 1000} km'),
                        selected: isSel,
                        selectedColor: AppColors.primaryGreen,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: isSel ? AppColors.textInverse : AppColors.textSecondary,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _targetDistanceM = dist),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Route Selection
              const Text('SANCTIONED COURSE / TRACK', style: AppTypography.labelSmall),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRouteId,
                    dropdownColor: AppColors.surfaceElevated,
                    isExpanded: true,
                    items: _sampleRoutes.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRouteId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Participant Limit
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('RACER LIMIT', style: AppTypography.labelSmall),
                  Text('$_participantLimit racers max', style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _participantLimit.toDouble(),
                min: 2,
                max: 12,
                divisions: 10,
                activeColor: AppColors.primaryGreen,
                inactiveColor: AppColors.borderSubtle,
                onChanged: (val) => setState(() => _participantLimit = val.toInt()),
              ),
              const SizedBox(height: 20),

              // Visibility
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'public',
                      groupValue: _visibility,
                      activeColor: AppColors.primaryGreen,
                      title: const Text('Public', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      onChanged: (v) => setState(() => _visibility = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'invitation_only',
                      groupValue: _visibility,
                      activeColor: AppColors.primaryGreen,
                      title: const Text('Invite Only', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      onChanged: (v) => setState(() => _visibility = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Create Action
              ElevatedButton(
                onPressed: _isCreating ? null : _handleCreateRace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.textInverse,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isCreating
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('OPEN RACE LOBBY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportOption(String id, String label, IconData icon) {
    final isSel = _selectedSport == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedSport = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? AppColors.primaryGreen.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? AppColors.primaryGreen : AppColors.borderSubtle),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSel ? AppColors.primaryGreen : AppColors.textSecondary, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSel ? AppColors.primaryGreen : AppColors.textSecondary,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(String id, String label) {
    final isSel = _selectedMode == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedMode = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? AppColors.primaryCyan.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? AppColors.primaryCyan : AppColors.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSel ? AppColors.primaryCyan : AppColors.textSecondary,
              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
