import 'package:flutter/material.dart';

/// Centralized Design System Colors for RaceZone
/// Follows dark navy / charcoal with electric neon accents & high-contrast telemetry
class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF090D16);
  static const Color backgroundSecondary = Color(0xFF0F172A);
  static const Color surface = Color(0xFF151D30);
  static const Color surfaceElevated = Color(0xFF1E2942);
  static const Color surfaceGlass = Color(0xCC151D30);

  // Brand Accents
  static const Color primaryGreen = Color(0xFF00E676); // Electric Sprint Green
  static const Color primaryCyan = Color(0xFF00E5FF);  // Velocity Cyan
  static const Color accentAmber = Color(0xFFFFAB00);  // Warning / Countdown
  static const Color accentRose = Color(0xFFFF1744);   // Emergency Stop / Error
  static const Color accentPurple = Color(0xFF7C4DFF); // Special events / XP

  // Sport Theme Colors
  static const Color sportRunning = Color(0xFF00E676);   // Green
  static const Color sportCycling = Color(0xFF00E5FF);   // Cyan
  static const Color sportMotorbike = Color(0xFFFF6D00); // Racing Orange

  // Telemetry High-Contrast Colors
  static const Color timerGlow = Color(0xFF00FF88);
  static const Color speedGauge = Color(0xFF00E5FF);
  static const Color paceText = Color(0xFFE2E8F0);

  // Text & Content
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textInverse = Color(0xFF090D16);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF1E293B);
  static const Color borderHighlight = Color(0xFF334155);
  static const Color borderGlowGreen = Color(0x6600E676);

  // Status Indicators
  static const Color statusOnline = Color(0xFF00E676);
  static const Color statusIdle = Color(0xFFFFB300);
  static const Color statusOffline = Color(0xFF64748B);
  static const Color statusRacing = Color(0xFF00E5FF);
}
