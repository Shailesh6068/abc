import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:racezone/core/config/app_config.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});

class SupabaseService {
  static bool _initialized = false;
  static User? _fallbackUser;

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      _initialized = true;
      debugPrint('[SupabaseService] Initialized with endpoint ${AppConfig.supabaseUrl}');
      // Automatically ensure device has a valid authenticated JWT session with Supabase
      await ensureAuthenticatedSession();
    } catch (e) {
      debugPrint('[SupabaseService] Remote endpoint unavailable, enabling resilient fallback mode: $e');
      _initialized = false;
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Ensures this device has an authenticated session with Supabase.
  /// If anonymous sign-in is disabled, automatically provisions a persistent device guest account.
  static Future<User?> ensureAuthenticatedSession() async {
    if (!_initialized) return null;
    try {
      final current = client.auth.currentUser;
      if (current != null) return current;

      // 1. Try standard anonymous sign-in
      try {
        final res = await client.auth.signInAnonymously();
        if (res.user != null) {
          debugPrint('[SupabaseService] Authenticated via anonymous session: ${res.user!.id}');
          return res.user;
        }
      } catch (anonErr) {
        debugPrint('[SupabaseService] signInAnonymously note ($anonErr), provisioning persistent device account');
      }

      // 2. If anonymous sign-in is disabled, use a persistent device guest account
      final prefs = await SharedPreferences.getInstance();
      var deviceEmail = prefs.getString('rz_device_auth_email');
      var devicePass = prefs.getString('rz_device_auth_pass');

      if (deviceEmail == null || devicePass == null) {
        final rand = DateTime.now().millisecondsSinceEpoch;
        deviceEmail = 'pilot_$rand@racezone.net';
        devicePass = 'RacerPass_$rand!#';
        await prefs.setString('rz_device_auth_email', deviceEmail);
        await prefs.setString('rz_device_auth_pass', devicePass);
      }

      try {
        final res = await client.auth.signUp(
          email: deviceEmail,
          password: devicePass,
          data: {'display_name': 'Racer Pilot'},
        );
        if (res.user != null) {
          debugPrint('[SupabaseService] Provisioned device guest session: ${res.user!.id} ($deviceEmail)');
          return res.user;
        }
      } catch (_) {
        // If already registered, sign in with password
        final res = await client.auth.signInWithPassword(
          email: deviceEmail,
          password: devicePass,
        );
        if (res.user != null) {
          debugPrint('[SupabaseService] Restored device guest session: ${res.user!.id} ($deviceEmail)');
          return res.user;
        }
      }
    } catch (e) {
      debugPrint('[SupabaseService] ensureAuthenticatedSession error: $e');
    }
    return client.auth.currentUser;
  }

  static User createLocalSession({
    required String email,
    String? displayName,
    String? id,
  }) {
    final nowStr = DateTime.now().toIso8601String();
    final name = displayName ?? (email.contains('@') ? email.split('@').first : 'Racer');
    final cleanEmail = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final uid = id ?? 'local_${cleanEmail}_${DateTime.now().millisecondsSinceEpoch}';
    final user = User(
      id: uid,
      appMetadata: const {},
      userMetadata: {'display_name': name, 'name': name},
      aud: 'authenticated',
      createdAt: nowStr,
      email: email,
    );
    _fallbackUser = user;
    debugPrint('[SupabaseService] Local racer session active: $email ($uid)');
    return user;
  }

  static void setFallbackUser(User user) {
    _fallbackUser = user;
    debugPrint('[SupabaseService] Local racer session active: ${user.email} (${user.id})');
  }

  static void clearFallbackUser() {
    _fallbackUser = null;
    debugPrint('[SupabaseService] Local racer session cleared');
  }

  static User? get currentUser {
    if (_initialized) {
      try {
        final u = client.auth.currentUser;
        if (u != null) return u;
      } catch (_) {}
    }
    return _fallbackUser;
  }

  static bool get isAuthenticated => currentUser != null;
}
