import 'package:flutter/material.dart';
import 'package:racezone/core/constants/app_colors.dart';

class AppTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.textMuted,
  );

  // Digital High-Contrast Telemetry Typography (for timer & speedometers)
  static const TextStyle telemetryGiant = TextStyle(
    fontSize: 54,
    fontWeight: FontWeight.w900,
    fontFamily: 'monospace',
    color: AppColors.timerGlow,
    letterSpacing: 1.5,
  );

  static const TextStyle telemetrySpeed = TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.w800,
    fontFamily: 'monospace',
    color: AppColors.primaryCyan,
  );
}
