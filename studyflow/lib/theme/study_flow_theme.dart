import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';

class StudyFlowTheme {
  static const Color primary = Color(0xFF4C5FD5);
  static const Color primarySoft = Color(0xFFE8EAFE);
  static const Color textPrimary = Color(0xFF20242D);
  static const Color textMuted = Color(0xFF666F7D);
  static const Color outline = Color(0xFFD7DDE8);
  static const Color card = Colors.white;
  static const Color appBackground = Color(0xFFF8F9FD);
  static const Color softSurface = Color(0xFFF1F4F9);
  static const Color success = Color(0xFF2B7A63);
  static const Color warning = Color(0xFFC24A5B);

  static ThemeData lightTheme([AppThemeAccent accent = AppThemeAccent.study]) {
    final palette = _paletteFor(accent);
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: palette.lightPrimary,
      onPrimary: Colors.white,
      secondary: palette.lightSecondary,
      onSecondary: Colors.white,
      error: warning,
      onError: Colors.white,
      surface: appBackground,
      onSurface: textPrimary,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: appBackground,
      cardColor: Colors.white,
      mutedColor: textMuted,
      accent: palette,
    );
  }

  static ThemeData darkTheme([AppThemeAccent accent = AppThemeAccent.study]) {
    final palette = _paletteFor(accent);
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.darkPrimary,
      onPrimary: const Color(0xFF0F1320),
      secondary: palette.darkSecondary,
      onSecondary: const Color(0xFF0F1320),
      error: const Color(0xFFFF97A6),
      onError: const Color(0xFF0F1320),
      surface: const Color(0xFF131A2B),
      onSurface: const Color(0xFFF7F9FF),
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0E1424),
      cardColor: const Color(0xFF182035),
      mutedColor: const Color(0xFFC0CADF),
      accent: palette,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color cardColor,
    required Color mutedColor,
    required _AccentPalette accent,
  }) {
    final textTheme = TextTheme(
      displayMedium: TextStyle(
        fontSize: 32,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
        color: mutedColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        letterSpacing: 0,
        color: mutedColor,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: colorScheme.onSurface,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      cardColor: cardColor,
      dividerColor: colorScheme.brightness == Brightness.dark
          ? const Color(0xFF35415B)
          : outline,
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.brightness == Brightness.dark
              ? accent.darkButton
              : accent.lightButton,
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size.fromHeight(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(
            color: colorScheme.brightness == Brightness.dark
                ? const Color(0xFF41506D)
                : outline,
          ),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: colorScheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.brightness == Brightness.dark
            ? const Color(0xFF202941)
            : const Color(0xFFF4F6FA),
        hintStyle: TextStyle(color: mutedColor.withValues(alpha: 0.88)),
        labelStyle: TextStyle(color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: colorScheme.brightness == Brightness.dark
                ? const Color(0xFF34415C)
                : outline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }

          return colorScheme.brightness == Brightness.dark
              ? const Color(0xFFE4E8F5)
              : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }

          return colorScheme.brightness == Brightness.dark
              ? const Color(0xFF4C546A)
              : const Color(0xFFD2D6DD);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: TextStyle(color: colorScheme.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static List<Color> backgroundGradient(
    Brightness brightness, [
    AppThemeAccent accent = AppThemeAccent.study,
  ]) {
    final palette = _paletteFor(accent);
    if (brightness == Brightness.dark) {
      return palette.darkBackgroundGradient;
    }

    return palette.lightBackgroundGradient;
  }

  static _AccentPalette _paletteFor(AppThemeAccent accent) {
    switch (accent) {
      case AppThemeAccent.study:
        return const _AccentPalette(
          lightPrimary: Color(0xFF4C5FD5),
          darkPrimary: Color(0xFF97A8FF),
          lightSecondary: Color(0xFF67748D),
          darkSecondary: Color(0xFFD4DCEC),
          lightButton: Color(0xFFE9EDF4),
          darkButton: Color(0xFF25314C),
          lightBackgroundGradient: [
            Color(0xFFF4F6FB),
            Color(0xFFFBFCFF),
            Color(0xFFF5F6FB),
          ],
          darkBackgroundGradient: [
            Color(0xFF0A1122),
            Color(0xFF10172A),
            Color(0xFF0B1020),
          ],
        );
      case AppThemeAccent.forest:
        return const _AccentPalette(
          lightPrimary: Color(0xFF2F8C72),
          darkPrimary: Color(0xFF8EE3C7),
          lightSecondary: Color(0xFF5F6F68),
          darkSecondary: Color(0xFFC9E7DD),
          lightButton: Color(0xFFE7F3EE),
          darkButton: Color(0xFF1F3A34),
          lightBackgroundGradient: [
            Color(0xFFF3F9F5),
            Color(0xFFF8FCFA),
            Color(0xFFF1F7F3),
          ],
          darkBackgroundGradient: [
            Color(0xFF0B1714),
            Color(0xFF10211D),
            Color(0xFF0D1917),
          ],
        );
      case AppThemeAccent.sunset:
        return const _AccentPalette(
          lightPrimary: Color(0xFFC95A47),
          darkPrimary: Color(0xFFFFB19F),
          lightSecondary: Color(0xFF7A6961),
          darkSecondary: Color(0xFFF0D2C9),
          lightButton: Color(0xFFF8EAE6),
          darkButton: Color(0xFF3B2725),
          lightBackgroundGradient: [
            Color(0xFFFCF4F1),
            Color(0xFFFFFBFA),
            Color(0xFFF9F0EB),
          ],
          darkBackgroundGradient: [
            Color(0xFF1A1011),
            Color(0xFF231617),
            Color(0xFF160E0E),
          ],
        );
      case AppThemeAccent.blossom:
        return const _AccentPalette(
          lightPrimary: Color(0xFFD85F95),
          darkPrimary: Color(0xFFFFA7C8),
          lightSecondary: Color(0xFF8A6678),
          darkSecondary: Color(0xFFF3D6E2),
          lightButton: Color(0xFFFBE8F1),
          darkButton: Color(0xFF412633),
          lightBackgroundGradient: [
            Color(0xFFFFF5FA),
            Color(0xFFFFFBFD),
            Color(0xFFFBEFF6),
          ],
          darkBackgroundGradient: [
            Color(0xFF180F16),
            Color(0xFF21141D),
            Color(0xFF140C13),
          ],
        );
      case AppThemeAccent.mono:
        return const _AccentPalette(
          lightPrimary: Color(0xFF111111),
          darkPrimary: Color(0xFFF5F5F5),
          lightSecondary: Color(0xFF4A4A4A),
          darkSecondary: Color(0xFFD7D7D7),
          lightButton: Color(0xFFEDEDED),
          darkButton: Color(0xFF2A2A2A),
          lightBackgroundGradient: [
            Color(0xFFF3F3F3),
            Color(0xFFFFFFFF),
            Color(0xFFEAEAEA),
          ],
          darkBackgroundGradient: [
            Color(0xFF080808),
            Color(0xFF141414),
            Color(0xFF060606),
          ],
        );
      case AppThemeAccent.passion:
        return const _AccentPalette(
          lightPrimary: Color(0xFFC43B4E),
          darkPrimary: Color(0xFFFFA4B2),
          lightSecondary: Color(0xFFA05E68),
          darkSecondary: Color(0xFFF2CCD3),
          lightButton: Color(0xFFFCE9EC),
          darkButton: Color(0xFF3F1D26),
          lightBackgroundGradient: [
            Color(0xFFFFF4F6),
            Color(0xFFFFFAFB),
            Color(0xFFFCECEE),
          ],
          darkBackgroundGradient: [
            Color(0xFF170A0E),
            Color(0xFF220F15),
            Color(0xFF12070A),
          ],
        );
    }
  }
}

class _AccentPalette {
  const _AccentPalette({
    required this.lightPrimary,
    required this.darkPrimary,
    required this.lightSecondary,
    required this.darkSecondary,
    required this.lightButton,
    required this.darkButton,
    required this.lightBackgroundGradient,
    required this.darkBackgroundGradient,
  });

  final Color lightPrimary;
  final Color darkPrimary;
  final Color lightSecondary;
  final Color darkSecondary;
  final Color lightButton;
  final Color darkButton;
  final List<Color> lightBackgroundGradient;
  final List<Color> darkBackgroundGradient;
}
