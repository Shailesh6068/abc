import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:racezone/app/app.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/ads/services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase Backend
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase initial setup note: $e');
  }

  // 2. Initialize Google Mobile Ads SDK (AdMob)
  try {
    await AdService.initialize();
  } catch (e) {
    debugPrint('AdMob initial setup note: $e');
  }

  runApp(
    const ProviderScope(
      child: RaceZoneApp(),
    ),
  );
}
