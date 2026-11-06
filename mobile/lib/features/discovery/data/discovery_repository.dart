import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    var user = _client.auth.currentUser;
    if (user == null) {
      user = await SupabaseService.ensureAuthenticatedSession();
      if (user == null) {
        debugPrint('[Discovery] updatePresence skipped: User is not authenticated');
        return;
      }
    }

    // Clean up any stale presence from this device's previous account/session
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUserId = prefs.getString('rz_last_presence_user_id');
      if (lastUserId != null && lastUserId != user.id) {
        await _client.from('player_presence').delete().eq('user_id', lastUserId);
        debugPrint('[Discovery] Removed previous ghost account presence: $lastUserId');
      }
      await prefs.setString('rz_last_presence_user_id', user.id);
    } catch (_) {}

    // Sport must be one of the enum values: 'running', 'cycling', 'motorbike'
    final validSport = (sport == 'all' || !['running', 'cycling', 'motorbike'].contains(sport))
        ? 'running'
        : sport;

    try {
      await _client.rpc('update_player_presence', params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_sport': validSport,
        'p_is_available': isAvailable,
      });
      debugPrint('[Discovery] Presence updated at ($latitude, $longitude) for $validSport (user: ${user.id})');
    } catch (e) {
      debugPrint('[Discovery] Failed to update presence: $e');
    }
  }

  /// Search for nearby players using PostGIS ST_DWithin
  Future<List<NearbyPlayer>> getNearbyPlayers({
    required double latitude,
    required double longitude,
    required int radiusM,
    String? sport,
    int limit = 30,
  }) async {
    var user = _client.auth.currentUser;
    if (user == null) {
      user = await SupabaseService.ensureAuthenticatedSession();
      if (user == null) {
        debugPrint('[Discovery] getNearbyPlayers: User not authenticated');
        return [];
      }
    }

    try {
      final Map<String, dynamic> params = {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_radius_m': radiusM,
        'p_limit': limit,
      };

      // Only pass p_sport if non-null and not 'all' to let PostgreSQL use DEFAULT NULL
      if (sport != null && sport.isNotEmpty && sport != 'all') {
        params['p_sport'] = sport;
      }

      final response = await _client.rpc('get_nearby_players', params: params);

      if (response is List && response.isNotEmpty) {
        final currentUserId = _client.auth.currentUser?.id;
        final realPlayers = response
            .map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              return NearbyPlayer.fromJson(map, isBot: false);
            })
            // 1. Strictly exclude current user's own device
            .where((p) => p.userId != currentUserId)
            .toList();

        // 2. Strictly deduplicate by user_id so no player ever appears twice
        final seenUserIds = <String>{};
        final uniquePlayers = <NearbyPlayer>[];
        for (final p in realPlayers) {
          if (seenUserIds.add(p.userId)) {
            uniquePlayers.add(p);
          }
        }

        debugPrint('[Discovery] Found ${uniquePlayers.length} unique nearby competitors within ${radiusM}m (self excluded)');
        return uniquePlayers;
      } else {
        debugPrint('[Discovery] 0 real competitors found within ${radiusM}m at ($latitude, $longitude)');
      }
    } catch (e, stack) {
      debugPrint('[Discovery] Error calling get_nearby_players RPC: $e\n$stack');
    }

    return [];
  }
}
