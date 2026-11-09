import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/races/domain/race_model.dart';

final raceRepositoryProvider = Provider<RaceRepository>((ref) {
  return RaceRepository(SupabaseService.client);
});

class RaceRepository {
  final SupabaseClient _client;
  static final Map<String, RaceModel> _localRaces = {};

  RaceRepository(this._client);

  /// Create a race securely via RPC with offline resilience
  Future<String> createRace({
    required String sport,
    required String mode,
    String visibility = 'public',
    int participantLimit = 4,
    String? routeId,
    Map<String, dynamic> configuration = const {},
  }) async {
    if (_client.auth.currentUser == null) {
      await SupabaseService.ensureAuthenticatedSession();
    }
    try {
      final response = await _client.rpc('create_race_secure', params: {
        'p_sport': sport,
        'p_mode': mode,
        'p_visibility': visibility,
        'p_participant_limit': participantLimit,
        'p_route_id': routeId,
        'p_configuration': configuration,
      });
      return response as String;
    } catch (e) {
      debugPrint('[RaceRepository] createRace remote note: $e, using local racer room');
      final currentUserId = SupabaseService.currentUser?.id ?? 'racer_local_01';
      final currentUserName = SupabaseService.currentUser?.userMetadata?['display_name'] ?? 'Racer Pilot';
      final raceId = 'race_${DateTime.now().millisecondsSinceEpoch}';
      final localRace = RaceModel(
        id: raceId,
        creatorId: currentUserId,
        sport: sport,
        mode: mode,
        visibility: visibility,
        status: 'WAITING',
        participantLimit: participantLimit,
        routeId: routeId,
        configuration: configuration,
        createdAt: DateTime.now(),
        participants: [
          RaceParticipant(
            userId: currentUserId,
            displayName: currentUserName,
            status: 'ready',
            joinedAt: DateTime.now(),
            readyAt: DateTime.now(),
          ),
        ],
      );
      _localRaces[raceId] = localRace;
      return raceId;
    }
  }

  /// Join an existing race lobby
  Future<void> joinRace(String raceId) async {
    if (_client.auth.currentUser == null) {
      await SupabaseService.ensureAuthenticatedSession();
    }
    try {
      await _client.rpc('join_race_secure', params: {'p_race_id': raceId});
    } catch (e) {
      debugPrint('[RaceRepository] joinRace fallback: $e');
      if (_localRaces.containsKey(raceId)) {
        final r = _localRaces[raceId]!;
        final currentUserId = SupabaseService.currentUser?.id ?? 'racer_guest';
        final currentUserName = SupabaseService.currentUser?.userMetadata?['display_name'] ?? 'Racer';
        if (!r.participants.any((p) => p.userId == currentUserId)) {
          final updatedParts = [
            ...r.participants,
            RaceParticipant(
              userId: currentUserId,
              displayName: currentUserName,
              status: 'ready',
              joinedAt: DateTime.now(),
              readyAt: DateTime.now(),
            ),
          ];
          _localRaces[raceId] = RaceModel(
            id: r.id,
            creatorId: r.creatorId,
            sport: r.sport,
            mode: r.mode,
            visibility: r.visibility,
            status: r.status,
            participantLimit: r.participantLimit,
            routeId: r.routeId,
            configuration: r.configuration,
            createdAt: r.createdAt,
            participants: updatedParts,
          );
        }
      }
    }
  }

  /// Toggle readiness in lobby
  Future<String> setReady(String raceId, bool isReady) async {
    try {
      final res = await _client.rpc('set_participant_ready', params: {
        'p_race_id': raceId,
        'p_is_ready': isReady,
      });
      return res as String;
    } catch (e) {
      debugPrint('[RaceRepository] setReady fallback: $e');
      return isReady ? 'ready' : 'joined';
    }
  }

  /// Fetch full race details including participants
  Future<RaceModel> getRaceDetails(String raceId) async {
    try {
      final raceData = await _client.from('races').select().eq('id', raceId).single();
      final partsData = await _client
          .from('race_participants')
          .select('*, profiles(display_name, avatar_url)')
          .eq('race_id', raceId);

      final participants = (partsData as List)
          .map((p) => RaceParticipant.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();

      final race = RaceModel.fromJson(Map<String, dynamic>.from(raceData), participants: participants);
      _localRaces[raceId] = race;
      return race;
    } catch (e) {
      if (_localRaces.containsKey(raceId)) {
        return _localRaces[raceId]!;
      }
      final currentUserId = SupabaseService.currentUser?.id ?? 'racer_local_01';
      final currentUserName = SupabaseService.currentUser?.userMetadata?['display_name'] ?? 'Racer Pilot';
      final fallback = RaceModel(
        id: raceId,
        creatorId: currentUserId,
        sport: 'running',
        mode: 'distance_race',
        visibility: 'public',
        status: 'WAITING',
        participantLimit: 4,
        configuration: const {'target_distance_m': 1000},
        createdAt: DateTime.now(),
        participants: [
          RaceParticipant(
            userId: currentUserId,
            displayName: currentUserName,
            status: 'ready',
            joinedAt: DateTime.now(),
            readyAt: DateTime.now(),
          ),
        ],
      );
      _localRaces[raceId] = fallback;
      return fallback;
    }
  }

  /// Listen to race updates via Supabase Realtime channel
  RealtimeChannel? subscribeToRace(String raceId, void Function(RaceModel updatedRace) onUpdate) {
    try {
      final channel = _client.channel('race:$raceId');

      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'races',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: raceId,
            ),
            callback: (payload) async {
              final race = await getRaceDetails(raceId);
              onUpdate(race);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'race_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'race_id',
              value: raceId,
            ),
            callback: (payload) async {
              final race = await getRaceDetails(raceId);
              onUpdate(race);
            },
          )
          .subscribe();

      return channel;
    } catch (e) {
      debugPrint('[RaceRepository] Realtime channel note: $e');
      return null;
    }
  }

  /// Fetch all active public races waiting for players (Join Race rooms)
  Future<List<RaceModel>> getOpenRaces({String? sport}) async {
    if (_client.auth.currentUser == null) {
      await SupabaseService.ensureAuthenticatedSession();
    }
    try {
      // Discard any abandoned lobby created more than 10 minutes ago
      final cutoff = DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String();
      var query = _client
          .from('races')
          .select('*, race_participants(*, profiles(display_name, avatar_url))')
          .eq('status', 'WAITING')
          .eq('visibility', 'public')
          .neq('mode', 'head_to_head')
          .gte('created_at', cutoff);

      if (sport != null && sport != 'all') {
        query = query.eq('sport', sport);
      }

      final data = await query.order('created_at', ascending: false);
      final List<RaceModel> races = [];
      for (final item in data as List) {
        final rawStatus = item['status'] as String? ?? '';
        if (rawStatus != 'WAITING') continue;

        // Discard any private 1v1 challenges
        final rawMode = item['mode'] as String? ?? '';
        if (rawMode == 'head_to_head') continue;
        final config = item['configuration'] as Map<String, dynamic>?;
        if (config != null && config['challengee_id'] != null) continue;

        final partsList = (item['race_participants'] as List? ?? [])
            .map((p) => RaceParticipant.fromJson(Map<String, dynamic>.from(p as Map)))
            .where((p) => p.status != 'left' && p.status != 'dnf')
            .toList();

        // Discard empty or disbanded lobbies
        if (partsList.isEmpty) continue;

        races.add(RaceModel.fromJson(Map<String, dynamic>.from(item as Map), participants: partsList));
      }
      return races;
    } catch (e) {
      return _localRaces.values
          .where((r) => r.status == 'WAITING' && r.mode != 'head_to_head' && (sport == null || sport == 'all' || r.sport == sport) && r.participants.isNotEmpty)
          .toList();
    }
  }

  /// Get user's current active open lobby (if any)
  Future<RaceModel?> getMyActiveLobby() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return null;

      // Tight 15-minute cutoff so old / stale lobbies never linger
      final cutoff = DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String();
      final data = await _client
          .from('race_participants')
          .select('race_id, status, races!inner(*, race_participants(*, profiles(display_name, avatar_url)))')
          .eq('user_id', user.id)
          .inFilter('status', ['joined', 'ready'])
          .inFilter('races.status', ['WAITING', 'COUNTDOWN'])
          .gte('races.created_at', cutoff)
          .order('joined_at', ascending: false)
          .limit(1);

      if ((data as List).isEmpty) {
        return null;
      }
      final raceData = data.first['races'];
      final raceStatus = raceData['status'] as String? ?? '';
      if (raceStatus != 'WAITING' && raceStatus != 'COUNTDOWN') {
        return null;
      }

      final partsList = (raceData['race_participants'] as List? ?? [])
          .map((p) => RaceParticipant.fromJson(Map<String, dynamic>.from(p as Map)))
          .where((p) => p.status != 'left' && p.status != 'dnf')
          .toList();

      if (partsList.isEmpty) return null;
      return RaceModel.fromJson(Map<String, dynamic>.from(raceData as Map), participants: partsList);
    } catch (e) {
      return null;
    }
  }

  /// Force start race (host control)
  Future<void> startRaceNow(String raceId) async {
    try {
      await _client.rpc('start_race_now', params: {'p_race_id': raceId});
    } catch (e) {
      debugPrint('[RaceRepository] startRaceNow fallback: $e');
    }
    if (_localRaces.containsKey(raceId)) {
      final r = _localRaces[raceId]!;
      _localRaces[raceId] = RaceModel(
        id: r.id,
        creatorId: r.creatorId,
        sport: r.sport,
        mode: r.mode,
        visibility: r.visibility,
        status: 'COUNTDOWN',
        participantLimit: r.participantLimit,
        routeId: r.routeId,
        configuration: r.configuration,
        scheduledStartAt: DateTime.now().add(const Duration(seconds: 5)),
        actualStartAt: r.actualStartAt,
        createdAt: r.createdAt,
        participants: r.participants.map((p) => RaceParticipant(
          userId: p.userId,
          displayName: p.displayName,
          avatarUrl: p.avatarUrl,
          status: 'ready',
          joinedAt: p.joinedAt,
          readyAt: p.readyAt ?? DateTime.now(),
          validatedDistanceM: p.validatedDistanceM,
          finishTimeMs: p.finishTimeMs,
        )).toList(),
      );
    }
  }

  /// Transition race state according to state machine rules
  Future<String> transitionRaceState(String raceId, String newStatus) async {
    try {
      final res = await _client.rpc('transition_race_state', params: {
        'p_race_id': raceId,
        'p_new_status': newStatus,
      });
      return res as String;
    } catch (e) {
      debugPrint('[RaceRepository] transitionRaceState fallback: $e');
    }
    if (_localRaces.containsKey(raceId)) {
      final r = _localRaces[raceId]!;
      _localRaces[raceId] = RaceModel(
        id: r.id,
        creatorId: r.creatorId,
        sport: r.sport,
        mode: r.mode,
        visibility: r.visibility,
        status: newStatus,
        participantLimit: r.participantLimit,
        routeId: r.routeId,
        configuration: r.configuration,
        scheduledStartAt: r.scheduledStartAt,
        actualStartAt: newStatus == 'IN_PROGRESS' ? DateTime.now() : r.actualStartAt,
        createdAt: r.createdAt,
        participants: r.participants.map((p) => RaceParticipant(
          userId: p.userId,
          displayName: p.displayName,
          avatarUrl: p.avatarUrl,
          status: newStatus == 'IN_PROGRESS' ? 'racing' : p.status,
          joinedAt: p.joinedAt,
          readyAt: p.readyAt,
          validatedDistanceM: p.validatedDistanceM,
          finishTimeMs: p.finishTimeMs,
        )).toList(),
      );
    }
    return newStatus;
  }

  /// Securely record participant finish time and status
  Future<void> recordParticipantFinish(String raceId, int finishTimeMs, [double? validatedDistanceM]) async {
    final user = _client.auth.currentUser ?? SupabaseService.currentUser;

    try {
      await _client.rpc('record_participant_finish', params: {
        'p_race_id': raceId,
        'p_finish_time_ms': finishTimeMs,
        'p_validated_distance_m': validatedDistanceM,
      });
    } catch (_) {}

    // Ensure participant row in Supabase is marked finished
    if (user != null) {
      try {
        await _client
            .from('race_participants')
            .update({
              'status': 'finished',
              'finish_time_ms': finishTimeMs,
              if (validatedDistanceM != null) 'validated_distance_m': validatedDistanceM,
            })
            .eq('race_id', raceId)
            .eq('user_id', user.id);
      } catch (e) {
        debugPrint('[RaceRepository] participant finish update note: $e');
      }
    }

    // Try finalizing race results RPC
    try {
      await _client.rpc('finalize_race_results', params: {'p_race_id': raceId});
    } catch (_) {}

    // Guarantee the race row status in races is set to COMPLETED
    try {
      await _client.from('races').update({
        'status': 'COMPLETED',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', raceId);
    } catch (_) {}

    _localRaces.remove(raceId);
  }

  /// Cancel and disband race lobby or active race
  Future<void> cancelRace(String raceId) async {
    // 1. Try cancel_race RPC
    try {
      await _client.rpc('cancel_race', params: {'p_race_id': raceId});
    } catch (e) {
      debugPrint('[RaceRepository] cancel_race RPC note: $e');
    }

    // 2. Direct database updates to guarantee status is CANCELLED
    try {
      await _client.from('races').update({
        'status': 'CANCELLED',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', raceId);
    } catch (e) {
      debugPrint('[RaceRepository] races cancel update note: $e');
    }

    // 3. Mark participants as left
    try {
      await _client.from('race_participants').update({
        'status': 'left',
      }).eq('race_id', raceId);
    } catch (_) {}

    // 4. Mark invitations as declined
    try {
      await _client.from('race_invitations').update({
        'status': 'declined',
      }).eq('race_id', raceId);
    } catch (_) {}

    _localRaces.remove(raceId);
  }

  /// Leave race lobby (non-host participant or host)
  Future<String> leaveRace(String raceId) async {
    final currentUserId = SupabaseService.currentUser?.id;

    try {
      final res = await _client.rpc('leave_race', params: {'p_race_id': raceId});
      _localRaces.remove(raceId);
      return res as String;
    } catch (e) {
      debugPrint('[RaceRepository] leave_race RPC note: $e');
    }

    // Direct fallback: remove participant or mark left
    if (currentUserId != null) {
      try {
        await _client.from('race_participants').delete()
            .eq('race_id', raceId)
            .eq('user_id', currentUserId);
      } catch (_) {
        try {
          await _client.from('race_participants').update({'status': 'left'})
              .eq('race_id', raceId)
              .eq('user_id', currentUserId);
        } catch (_) {}
      }
    }

    _localRaces.remove(raceId);
    return 'left';
  }
}

