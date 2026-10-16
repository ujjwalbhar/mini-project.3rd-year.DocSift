import 'package:flutter/material.dart';

/// DocSift Design Tokens — from design.md
class AppColors {
  AppColors._();

  // ─── Core Brand ───────────────────────────────────────────────────────────
  /// Primary Navy — app bars, lock screen backdrop, active nav, headings
  static const Color primaryNavy = Color(0xFF2B3C5A);

  /// Accent Emerald — CTAs, active PIN, FAB, verified badges, chat bubbles
  static const Color accentEmerald = Color(0xFF27AE60);
  static const Color accentEmeraldLight = Color(0xFFD4EFDF);
  static const Color accentEmeraldDark = Color(0xFF1E8449);

  // ─── Surface / Background ─────────────────────────────────────────────────
  /// Surface Neutral — global background canvas, search fill, borders
  static const Color surfaceNeutral = Color(0xFFF0F3F2);

  /// Card Canvas — elevated surfaces, item containers
  static const Color cardCanvas = Color(0xFFFFFFFF);

  // ─── Accent Colors per Category ───────────────────────────────────────────
  static const Color categoryPasswordsColor = Color(0xFF3B5BDB); // Blue
  static const Color categoryPasswordsBg = Color(0xFFE8EDFF);

  static const Color categoryIdentityColor = Color(0xFF27AE60); // Emerald
  static const Color categoryIdentityBg = Color(0xFFD4EFDF);

  static const Color categoryCardsColor = Color(0xFFF39C12);   // Amber
  static const Color categoryCardsBg = Color(0xFFFEF9E7);

  static const Color categoryNotesColor = Color(0xFFE67E22);   // Orange
  static const Color categoryNotesBg = Color(0xFFFDF2E9);

  static const Color categoryDocumentsColor = Color(0xFFE91E8C); // Pink
  static const Color categoryDocumentsBg = Color(0xFFFCE4F3);

  static const Color categoryMediaColor = Color(0xFF8E44AD);   // Purple
  static const Color categoryMediaBg = Color(0xFFF5EEF8);

  // ─── Utility ──────────────────────────────────────────────────────────────
  static const Color peachAccent = Color(0xFFFF8A8A);
  static const Color destructiveRed = Color(0xFFFF6B6B);
  static const Color destructiveRedBg = Color(0xFFFFEBEB);

  // ─── Text ─────────────────────────────────────────────────────────────────
  /// #1A202C — high-contrast body text, primary item titles
  static const Color textPrimary = Color(0xFF1A202C);

  /// #718096 — metadata, timestamps, file sizes, placeholders
  static const Color textMuted = Color(0xFF718096);

  /// White for dark backgrounds
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted = Color(0xFFB0BEC5);

  // ─── Lock Screen Specific ─────────────────────────────────────────────────
  static const Color lockScreenBg = Color(0xFF2B3C5A);
  static const Color lockKeypadButton = Color(0xFF384D70);
  static const Color lockKeypadButtonPressed = Color(0xFF4A6290);
  static const Color pinUnfilled = Color(0xFFCBD5E0);

  // ─── Border & Divider ─────────────────────────────────────────────────────
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF0F3F2);

  // ─── Verified badge ───────────────────────────────────────────────────────
  static const Color verifiedGreen = Color(0xFF27AE60);
  static const Color verifiedGreenBg = Color(0xFFD4EFDF);

  // ─── Shadows ──────────────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF2B3C5A).withValues(alpha: 0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> fabShadow = [
    BoxShadow(
      color: const Color(0xFF27AE60).withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> bottomBarShadow = [
    BoxShadow(
      color: const Color(0xFF2B3C5A).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, -4),
    ),
  ];
}
