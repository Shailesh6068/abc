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
    var user = SupabaseService.currentUser ?? _client.auth.currentUser;
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
    // Always ensure session is active before querying
    var user = SupabaseService.currentUser ?? _client.auth.currentUser;
    if (user == null) {
      user = await SupabaseService.ensureAuthenticatedSession();
      if (user == null) {
        debugPrint('[Discovery] getNearbyPlayers: User not authenticated');
        return [];
      }
    }

    // Always ensure discovery_enabled = true for this user so they appear on others' radars
    try {
      await _client.from('player_preferences').upsert({
        'user_id': user.id,
        'discovery_enabled': true,
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[Discovery] Could not ensure discovery_enabled: $e');
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
      debugPrint('[Discovery] get_nearby_players raw response count: ${response is List ? response.length : 0}');

      if (response is List && response.isNotEmpty) {
        // Use the actual auth user ID (not fallback) for self-exclusion since SQL already excludes by auth.uid()
        // But also filter client-side in case of session mismatch
        final currentUserId = user.id;

        final realPlayers = response
            .map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              return NearbyPlayer.fromJson(map, isBot: false);
            })
            // Client-side self-exclusion guard (SQL already handles this, belt-and-suspenders)
            .where((p) => p.userId != currentUserId)
            .toList();

        // Deduplicate strictly by user_id only (don't filter by name — same names can be different people)
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
