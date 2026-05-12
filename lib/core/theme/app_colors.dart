import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Changing this one constant swaps the entire accent palette.
  // Teal:  Color(0xFF1EC8B0), Amber: Color(0xFFE8A020)
  static const accentBase = Color(0xFF1EC8B0);

  // All accent-derived colors computed from accentBase.
  // Accent is const so `const Icon(color: AppColors.accent)` still compiles.
  // Only accentLight/accentDark/accentGlow are getters, not const.
  static const accent = accentBase;
  static Color get accentLight => Color.lerp(accentBase, Colors.white, 0.20)!;
  static Color get accentDark => Color.lerp(accentBase, Colors.black, 0.30)!;
  static Color get accentGlow => accentBase.withValues(alpha: 0.20);
  static Color get glassOrb1 => accentBase.withValues(alpha: 0.13);
  static Color get glassOrb2 => accentBase.withValues(alpha: 0.08);
  static Color get micGlow => accentBase.withValues(alpha: 0.27);

  // Backgrounds
  static const background = Color(0xFF0B0B0D);
  static const surface = Color(0xFF111114);
  static const surfaceVariant = Color(0xFF18181C);
  static const cardBackground = Color(0xFF111114);

  // Text
  static const textPrimary = Color(0xFFF2F2F0);
  static const textSecondary = Color(0xFFB0B0B8);
  static const textTertiary = Color(0xFF7A7A82);
  static const textDisabled = Color(0xFF4A4A52);

  // Status
  static const error = Color(0xFFF06060);
  static const errorSurface = Color(0xFF2A1515);
  static const success = Color(0xFF3DD68C);
  static const warning = Color(0xFFFFAA44);

  // Dividers / borders
  static const divider = Color(0xFF1E1E22);
  static const border = Color(0xFF242428);

  // Glass morphism (white-based — not accent-derived, stay const)
  static const deepBackground = Color(0xFF0B0B0D);
  static const glassWhiteFill = Color(0x0AFFFFFF);
  static const glassBorderLight = Color(0x14FFFFFF);
  static const glassBorderDim = Color(0x0DFFFFFF);
  static const glassHighlight = Color(0x06FFFFFF);

  // Mic states
  static const micIdle = accentBase;
  static const micListening = Color(0xFF44BBFF);
  static const micProcessing = Color(0xFFFFAA44);
}
