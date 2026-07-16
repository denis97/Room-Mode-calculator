import 'package:flutter/material.dart';

/// Design tokens for the app's dark "Studio" theme: a near-black canvas,
/// soft-bordered panel cards, a single blue accent, and the axial /
/// tangential / oblique mode colors reused across every visualization.
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0A0B0E);
  static const backgroundGlow = Color(0xFF16181F);
  static const surface = Color(0xFF161A22);
  static const surfaceAlt = Color(0xFF1A1E26);
  static const control = Color(0xFF232833);
  static const border = Color(0x12FFFFFF); // rgba(255,255,255,.07)
  static const accent = Color(0xFF4D8DFF);
  static const accentSoft = Color(0x294D8DFF); // rgba(77,141,255,.16)

  static const textPrimary = Color(0xFFEEF1F6);
  static const textSecondary = Color(0xFF8890A0);
  static const textMuted = Color(0xFF7E8595);
  static const textFaint = Color(0xFF5F6675);

  static const axial = Color(0xFFFF6B6B);
  static const tangential = Color(0xFFFFC857);
  static const oblique = Color(0xFF4ECDC4);

  /// Diverging pressure-field gradient: cool cyan (negative) through
  /// near-black (node) to warm pink-red (positive).
  static const fieldNegative = Color(0xFF29C4FF);
  static const fieldMid = Color(0xFF10131A);
  static const fieldPositive = Color(0xFFFF5E7A);
}

/// The radial background used behind the setup/viewer scaffolds, matching
/// the mockup's `radial-gradient(circle at 50% -10%, #16181f, #0a0b0e 60%)`.
const appBackgroundGradient = RadialGradient(
  center: Alignment(0, -1.2),
  radius: 1.4,
  colors: [AppColors.backgroundGlow, AppColors.background],
  stops: [0.0, 0.6],
);

/// Maps a signed pressure value in [-1, 1] to the diverging cyan → near-black
/// → pink-red gradient used across every pressure visualization (3D room
/// views, the 2D slice heatmap).
Color fieldColor(double v) {
  final t = v.clamp(-1.0, 1.0);
  final c = t >= 0
      ? Color.lerp(AppColors.fieldMid, AppColors.fieldPositive, t)!
      : Color.lerp(AppColors.fieldMid, AppColors.fieldNegative, -t)!;
  return c;
}

/// Monospace text style for numeric readouts (frequencies, dimensions,
/// counts) — mirrors the mockup's `.mono` class.
TextStyle monoStyle({
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w500,
  Color color = AppColors.textPrimary,
}) {
  return TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}

ThemeData buildAppTheme() {
  final colorScheme = const ColorScheme.dark(
    surface: AppColors.background,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    error: Color(0xFFFF6B6B),
  ).copyWith(
    onSurface: AppColors.textPrimary,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Space Grotesk',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamily: 'Space Grotesk',
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.control,
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9, elevation: 1),
      thumbColor: AppColors.background,
      overlayColor: AppColors.accentSoft,
      valueIndicatorColor: AppColors.surfaceAlt,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceAlt,
      selectedColor: AppColors.accentSoft,
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      side: const BorderSide(color: AppColors.border),
    ),
  );
}
