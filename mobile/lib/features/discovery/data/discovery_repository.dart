import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/discovery/domain/player_model.dart';

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository(SupabaseService.client);
});

class DiscoveryRepository {
  final SupabaseClient _client;

  DiscoveryRepository(this._client);

  /// Heartbeat: updates the current player's location and presence
  Future<void> updatePresence({
    required double latitude,
    required double longitude,
    required String sport,
    bool isAvailable = true,
  }) async {
    await _client.rpc('update_player_presence', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_sport': sport,
      'p_is_available': isAvailable,
    });
  }

  /// Search for nearby players using PostGIS ST_DWithin
  Future<List<NearbyPlayer>> getNearbyPlayers({
    required double latitude,
    required double longitude,
    required int radiusM,
    String? sport,
    int limit = 30,
  }) async {
    final response = await _client.rpc('get_nearby_players', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_radius_m': radiusM,
      'p_sport': sport,
      'p_limit': limit,
    });

    if (response is List) {
      return response.map((item) => NearbyPlayer.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
