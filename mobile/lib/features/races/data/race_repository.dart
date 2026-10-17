import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/races/domain/race_model.dart';

final raceRepositoryProvider = Provider<RaceRepository>((ref) {
  return RaceRepository(SupabaseService.client);
});

class RaceRepository {
  final SupabaseClient _client;

  RaceRepository(this._client);

  /// Create a race securely via RPC
  Future<String> createRace({
    required String sport,
    required String mode,
    String visibility = 'public',
    int participantLimit = 4,
    String? routeId,
    Map<String, dynamic> configuration = const {},
  }) async {
    final response = await _client.rpc('create_race_secure', params: {
      'p_sport': sport,
      'p_mode': mode,
      'p_visibility': visibility,
      'p_participant_limit': participantLimit,
      'p_route_id': routeId,
      'p_configuration': configuration,
    });
    return response as String;
  }

  /// Join an existing race lobby
  Future<void> joinRace(String raceId) async {
    await _client.rpc('join_race_secure', params: {'p_race_id': raceId});
  }

  /// Toggle readiness in lobby
  Future<String> setReady(String raceId, bool isReady) async {
    final res = await _client.rpc('set_participant_ready', params: {
      'p_race_id': raceId,
      'p_is_ready': isReady,
    });
    return res as String;
  }

  /// Fetch full race details including participants
  Future<RaceModel> getRaceDetails(String raceId) async {
    final raceData = await _client.from('races').select().eq('id', raceId).single();
    final partsData = await _client
        .from('race_participants')
        .select('*, profiles(display_name, avatar_url)')
        .eq('race_id', raceId);

    final participants = (partsData as List)
        .map((p) => RaceParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    return RaceModel.fromJson(raceData, participants: participants);
  }

  /// Listen to race updates via Supabase Realtime channel
  RealtimeChannel subscribeToRace(String raceId, void Function(RaceModel updatedRace) onUpdate) {
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
  }
}
