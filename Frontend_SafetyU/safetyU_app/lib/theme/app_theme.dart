import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Centralized color palette matching the SafetyU design
/// (navy primary, red/coral accent for alerts and emergency actions).
///
/// Every color below is a *getter*, not a const — it checks
/// [ThemeController.instance.isDark] on every read and returns the light or
/// dark value. That means every screen that already writes `AppColors.card`
/// etc. automatically re-colors itself when dark mode toggles; nothing else
/// needs to change per-screen.
class AppColors {
  AppColors._();

  static bool get _dark => ThemeController.instance.isDark;

  static Color get navy =>
      _dark ? const Color(0xFF3A4472) : const Color(0xFF1C2340);
  static Color get navyDark =>
      _dark ? const Color(0xFF0E1226) : const Color(0xFF141935);
  static Color get danger =>
      _dark ? const Color(0xFFFF7A72) : const Color(0xFFE4574F);
  static Color get dangerLight =>
      _dark ? const Color(0xFF3A2224) : const Color(0xFFFDEDEC);
  static Color get background =>
      _dark ? const Color(0xFF11131C) : const Color(0xFFF7F8FC);
  static Color get card =>
      _dark ? const Color(0xFF1B1E2A) : const Color(0xFFFFFFFF);
  static Color get border =>
      _dark ? const Color(0xFF2E3242) : const Color(0xFFE7E9F3);
  static Color get textPrimary =>
      _dark ? const Color(0xFFF1F2F7) : const Color(0xFF1B1D29);
  static Color get textSecondary =>
      _dark ? const Color(0xFFB7BACB) : const Color(0xFF7C7F93);
  static Color get textMuted =>
      _dark ? const Color(0xFF7A7E93) : const Color(0xFFA6A9BC);
  static Color get success =>
      _dark ? const Color(0xFF4FD584) : const Color(0xFF2FAE60);
}

/// App-wide ThemeData: shared button, input, and typography styling
/// so every screen looks consistent without repeating style code.
class AppTheme {
  AppTheme._();

  /// Rebuilt fresh every time it's requested (see main.dart), so it always
  /// reflects the current ThemeController state.
  static ThemeData get current {
    final brightness =
        ThemeController.instance.isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        brightness: brightness,
        primary: AppColors.navy,
        secondary: AppColors.danger,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.navy, width: 1.6),
        ),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textPrimary,
        ),
      ),
    );
  }
}
