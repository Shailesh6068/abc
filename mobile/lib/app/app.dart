import 'package:flutter/material.dart';
import 'package:racezone/app/app_router.dart';
import 'package:racezone/app/app_theme.dart';
import 'package:racezone/core/constants/app_strings.dart';

class RaceZoneApp extends StatelessWidget {
  const RaceZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
