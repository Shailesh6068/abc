import 'package:flutter/material.dart';

/// Centralized Design System Colors for RaceZone — Light Gaming Theme
/// Clean white/light canvas with bold vivid neon gaming accents
class AppColors {
  // Backgrounds — Light theme
  static const Color background = Color(0xFFF5F7FA);
  static const Color backgroundSecondary = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF0F4F8);
  static const Color surfaceGlass = Color(0xE8FFFFFF);
  static const Color surfaceCard = Color(0xFFFFFFFF);

  // Brand Accents — Vivid & Saturated for Light Backgrounds
  static const Color primaryGreen = Color(0xFF00C853);   // Racing Green (vivid)
  static const Color primaryCyan = Color(0xFF0091EA);    // Velocity Blue-Cyan
  static const Color accentAmber = Color(0xFFFF6F00);    // Nitro Orange
  static const Color accentRose = Color(0xFFD50000);     // Emergency Red
  static const Color accentPurple = Color(0xFF6200EA);   // Special / XP Purple

  // Championship Metals
  static const Color gold = Color(0xFFFFB300);
  static const Color goldGlow = Color(0x44FFB300);
  static const Color silver = Color(0xFF78909C);
  static const Color bronze = Color(0xFF8D6E63);

  // Sport Theme Colors
  static const Color sportRunning = Color(0xFF00C853);
  static const Color sportCycling = Color(0xFF0091EA);
  static const Color sportMotorbike = Color(0xFFFF6F00);

  // Telemetry
  static const Color timerGlow = Color(0xFF00C853);
  static const Color speedGauge = Color(0xFF0091EA);
  static const Color paceText = Color(0xFF1A1A2E);

  // Text & Content — Dark on Light
  static const Color textPrimary = Color(0xFF0D1117);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF9AA5B4);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Borders & Dividers — Subtle on Light
  static const Color borderSubtle = Color(0xFFE2E8F0);
  static const Color borderHighlight = Color(0xFFCBD5E0);
  static const Color borderGlowGreen = Color(0x6600C853);
  static const Color borderGlowCyan = Color(0x660091EA);

  // Status Indicators
  static const Color statusOnline = Color(0xFF00C853);
  static const Color statusIdle = Color(0xFFFF8F00);
  static const Color statusOffline = Color(0xFF9AA5B4);
  static const Color statusRacing = Color(0xFF0091EA);

  // Gaming Gradients — Vivid on Light
  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF0091EA), Color(0xFF40C4FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFB300), Color(0xFFFF6F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF6F00), Color(0xFFFFAB40)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF6200EA), Color(0xFF651FFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireGradient = LinearGradient(
    colors: [Color(0xFFD50000), Color(0xFFFF6D00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient metallicGold = LinearGradient(
    colors: [Color(0xFFFFE57F), Color(0xFFFFB300), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient metallicSilver = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFCFD8DC), Color(0xFF90A4AE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Light card shadow
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0D1117).withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0xFF0D1117).withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get greenGlowShadow => [
    BoxShadow(
      color: primaryGreen.withValues(alpha: 0.35),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get cyanGlowShadow => [
    BoxShadow(
      color: primaryCyan.withValues(alpha: 0.35),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
}
