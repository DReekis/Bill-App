import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StitchColors {
  static const primary = Color(0xFF2E3192);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFE1E0FF);
  static const onPrimaryContainer = Color(0xFF17175F);

  static const success = Color(0xFF059669);
  static const onSuccess = Color(0xFFFFFFFF);
  static const successSoft = Color(0xFFE7F5EF);

  static const warning = Color(0xFFF59E0B);
  static const onWarning = Color(0xFFFFFFFF);
  static const warningSoft = Color(0xFFFEF3E2);

  static const error = Color(0xFFDC2626);
  static const onError = Color(0xFFFFFFFF);
  static const errorSoft = Color(0xFFFCEBEB);

  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF8FAFC);
  static const surfaceVariant = Color(0xFFEFF4FF);
  static const outline = Color(0xFFE2E8F0);
  static const outlineStrong = Color(0xFFCBD5E1);

  static const textPrimary = Color(0xFF0F1C3E);
  static const textSecondary = Color(0xFF64748B);
  static const textTertiary = Color(0xFF94A3B8);
}

ThemeData buildStitchTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: StitchColors.primary,
      onPrimary: StitchColors.onPrimary,
      primaryContainer: StitchColors.primaryContainer,
      onPrimaryContainer: StitchColors.onPrimaryContainer,
      secondary: StitchColors.success,
      onSecondary: StitchColors.onSuccess,
      secondaryContainer: StitchColors.successSoft,
      onSecondaryContainer: StitchColors.success,
      error: StitchColors.error,
      onError: StitchColors.onError,
      errorContainer: StitchColors.errorSoft,
      onErrorContainer: StitchColors.error,
      surface: StitchColors.surface,
      onSurface: StitchColors.textPrimary,
      outline: StitchColors.outlineStrong,
      outlineVariant: StitchColors.outline,
    ),
    scaffoldBackgroundColor: StitchColors.surface,
    fontFamily: 'Inter',
    textTheme: GoogleFonts.interTextTheme().apply(
      bodyColor: StitchColors.textPrimary,
      displayColor: StitchColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StitchColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: StitchColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: StitchColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: StitchColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StitchColors.primary,
        foregroundColor: StitchColors.onPrimary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: StitchColors.background,
        foregroundColor: StitchColors.primary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: StitchColors.outline),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StitchColors.primary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: StitchColors.outlineStrong),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: StitchColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: StitchColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: StitchColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: StitchColors.primary, width: 1.6),
      ),
      labelStyle: const TextStyle(color: StitchColors.textSecondary),
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w400,
        fontSize: 14,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: StitchColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: const DividerThemeData(color: StitchColors.outline),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: StitchColors.background,
      indicatorColor: StitchColors.primaryContainer,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StitchColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: StitchColors.primary,
      foregroundColor: StitchColors.onPrimary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: StitchColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
  return base;
}