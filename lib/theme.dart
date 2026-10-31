import 'package:flutter/material.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────

/// The colours that change between dark and light themes.
class AppPalette {
  final Color bgPrimary, bgSecondary, bgCard, bgCardAlt, bgHover, bgActive, bgInput;
  final Color textPrimary, textSecondary, textMuted, textBright;
  final Color border, borderLight;

  /// The accent used until the user picks their own.
  final Color accent;

  /// Bars and meters.
  final Color chart;

  /// A newer version than the one installed, and nothing else.
  final Color newVersion, onNewVersion;

  final Color danger;
  final Color statusUnplayed, statusPlaying, statusUpdated, statusOnHold;
  final Color statusCompleted, statusSkimmed, statusAbandoned;

  const AppPalette({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgCard,
    required this.bgCardAlt,
    required this.bgHover,
    required this.bgActive,
    required this.bgInput,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textBright,
    required this.border,
    required this.borderLight,
    required this.accent,
    required this.chart,
    required this.newVersion,
    required this.onNewVersion,
    required this.danger,
    required this.statusUnplayed,
    required this.statusPlaying,
    required this.statusUpdated,
    required this.statusOnHold,
    required this.statusCompleted,
    required this.statusSkimmed,
    required this.statusAbandoned,
  });

  /// Midnight Edition.
  static const dark = AppPalette(
    bgPrimary: Color(0xFF0D1017),
    bgSecondary: Color(0xFF090B10),
    bgCard: Color(0xFF151925),
    bgCardAlt: Color(0xFF191E2B),
    bgHover: Color(0xFF1D2230),
    bgActive: Color(0xFF2A3044),
    bgInput: Color(0xFF090B10),
    textPrimary: Color(0xFFE8EBF1),
    textSecondary: Color(0xFFB2BAC6),
    textMuted: Color(0xFF8E98A8),
    textBright: Color(0xFFFFFFFF),
    border: Color(0xFF252B3A),
    borderLight: Color(0xFF333B4E),
    accent: Color(0xFF4FD1A5),
    chart: Color(0xFF27A37D),
    newVersion: Color(0xFFFFC857),
    onNewVersion: Color(0xFF2A1B00),
    danger: Color(0xFFF28B8B),
    statusUnplayed: Color(0xFF8E98A8),
    statusPlaying: Color(0xFF5BD6A0),
    statusUpdated: Color(0xFF6CB8FF),
    statusOnHold: Color(0xFFE0B878),
    statusCompleted: Color(0xFFC6CFDB),
    statusSkimmed: Color(0xFFBBA2FF),
    statusAbandoned: Color(0xFFF28B8B),
  );

  /// Paperback.
  static const light = AppPalette(
    bgPrimary: Color(0xFFEEF0EC),
    bgSecondary: Color(0xFFE3E6E1),
    bgCard: Color(0xFFFFFFFF),
    bgCardAlt: Color(0xFFF6F7F4),
    bgHover: Color(0xFFE6E9E4),
    bgActive: Color(0xFFD8DCD6),
    bgInput: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF171B1F),
    textSecondary: Color(0xFF454D55),
    textMuted: Color(0xFF5D656E),
    textBright: Color(0xFF0E1114),
    border: Color(0xFFCFD3CD),
    borderLight: Color(0xFFBFC4BD),
    accent: Color(0xFF096F55),
    chart: Color(0xFF0B7A5E),
    newVersion: Color(0xFFFFC857),
    onNewVersion: Color(0xFF2A1B00),
    danger: Color(0xFFB3302F),
    statusUnplayed: Color(0xFF5D656E),
    statusPlaying: Color(0xFF0B7A5E),
    statusUpdated: Color(0xFF1B66B3),
    statusOnHold: Color(0xFF855A0F),
    statusCompleted: Color(0xFF47525E),
    statusSkimmed: Color(0xFF6A47C2),
    statusAbandoned: Color(0xFFB3302F),
  );
}

/// Colours are read when widgets build, so [apply] followed by a rebuild
/// recolours the whole app. See VNPathfinderApp.
class AppColors {
  /// The saved value that means "the theme's own accent". Earlier builds saved
  /// their default the same way, so it also reads as unset.
  static const defaultAccentHex = '#4fd1a5';
  static const _oldDefaultAccentHex = '#4a9e6e';

  static bool isDefaultAccent(String hex) {
    final h = hex.toLowerCase();
    return h == defaultAccentHex || h == _oldDefaultAccentHex;
  }

  static AppPalette _palette = AppPalette.dark;
  static Color _accent = AppPalette.dark.accent;

  static void apply({required bool dark, Color? accent}) {
    _palette = dark ? AppPalette.dark : AppPalette.light;
    _accent = accent ?? _palette.accent;
  }

  static bool get isDark => identical(_palette, AppPalette.dark);

  static Color get bgPrimary => _palette.bgPrimary;
  static Color get bgSecondary => _palette.bgSecondary;
  static Color get bgCard => _palette.bgCard;
  static Color get bgCardAlt => _palette.bgCardAlt;
  static Color get bgHover => _palette.bgHover;
  static Color get bgActive => _palette.bgActive;
  static Color get bgInput => _palette.bgInput;

  static Color get accent => _accent;
  static Color get accentLight => Color.lerp(_accent, isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000), 0.14)!;
  static Color get accentDim => Color.lerp(_accent, const Color(0xFF000000), 0.2)!;
  static Color get accentGlow => _accent.withValues(alpha: 0.3);

  /// Text and icons on an accent fill.
  static Color get onAccent => _accent.computeLuminance() > 0.3 ? const Color(0xFF06231B) : const Color(0xFFFFFFFF);

  static Color get chart => _palette.chart;
  static Color get newVersion => _palette.newVersion;
  static Color get onNewVersion => _palette.onNewVersion;

  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;
  static Color get textBright => _palette.textBright;

  static Color get danger => _palette.danger;
  static Color get warning => _palette.statusOnHold;
  static Color get success => _accent;

  static Color get statusUnplayed => _palette.statusUnplayed;
  static Color get statusPlaying => _palette.statusPlaying;
  static Color get statusUpdated => _palette.statusUpdated;
  static Color get statusOnHold => _palette.statusOnHold;
  static Color get statusCompleted => _palette.statusCompleted;
  static Color get statusSkimmed => _palette.statusSkimmed;
  static Color get statusAbandoned => _palette.statusAbandoned;

  static Color get border => _palette.border;
  static Color get borderLight => _palette.borderLight;
  static Color get borderAccent => _accent.withValues(alpha: 0.4);

  // On top of art, whatever the theme.
  static const onArt = Color(0xFFFFFFFF);
  static const onArtSoft = Color(0xFFD5DAE3);
  static const onArtMuted = Color(0xFFB8C0CC);
  static const artScrim = Color(0xFF06080D);
}

// ── Fonts ─────────────────────────────────────────────────────────────────────

/// The app's bundled fonts (assets/fonts). Nothing is fetched at runtime, so
/// Lockdown Mode covers text too.
class AppText {
  static const uiFamily = 'Inter';
  static const monoFamily = 'JetBrains Mono';

  /// Newsreader's display cut, for titles.
  static const displayFamily = 'Newsreader';

  /// Newsreader's reading cut, for blurbs and synopses.
  static const readingFamily = 'Newsreader Text';

  /// Titles can be in any script, and the bundled fonts are Latin.
  static const fallback = ['Yu Gothic UI', 'Microsoft YaHei UI', 'Malgun Gothic', 'Segoe UI'];

  // The app's type scale. Nothing is set smaller than [caption].

  /// Newsreader 34/40.
  static TextStyle title({Color? color}) =>
      display(fontSize: 34, height: 40 / 34, letterSpacing: -0.4, color: color ?? AppColors.textBright);

  /// Newsreader 20/26.
  static TextStyle heading({Color? color}) =>
      display(fontSize: 20, height: 26 / 20, color: color ?? AppColors.textPrimary);

  /// The reading cut at 15/24.
  static TextStyle blurb({Color? color}) =>
      reading(fontSize: 15, height: 24 / 15, color: color ?? AppColors.textSecondary);

  /// Inter 13/18.
  static TextStyle body({Color? color, FontWeight? fontWeight}) =>
      ui(fontSize: 13, height: 18 / 13, fontWeight: fontWeight, color: color ?? AppColors.textPrimary);

  /// Inter 12/16.
  static TextStyle meta({Color? color, FontWeight? fontWeight}) =>
      ui(fontSize: 12, height: 16 / 12, fontWeight: fontWeight, color: color ?? AppColors.textSecondary);

  /// Inter 11/14, the floor.
  static TextStyle caption({Color? color, FontWeight? fontWeight}) =>
      ui(fontSize: 11, height: 14 / 11, fontWeight: fontWeight, color: color ?? AppColors.textMuted);

  /// JetBrains Mono 12/16, for versions, sizes and counts.
  static TextStyle data({Color? color, FontWeight? fontWeight}) =>
      mono(fontSize: 12, height: 16 / 12, fontWeight: fontWeight, color: color ?? AppColors.textSecondary);

  static TextStyle _style(
    String family,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows, {
    TextDecoration? decoration,
    Color? decorationColor,
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        shadows: shadows,
        decoration: decoration,
        decorationColor: decorationColor,
      );

  static TextStyle ui({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    Color? decorationColor,
  }) =>
      _style(uiFamily, fontSize, fontWeight, color, letterSpacing, height, shadows,
          decoration: decoration, decorationColor: decorationColor);

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      _style(monoFamily, fontSize, fontWeight, color, letterSpacing, height, null);

  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) =>
      _style(displayFamily, fontSize, fontWeight, color, letterSpacing, height, shadows);

  static TextStyle reading({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) =>
      _style(readingFamily, fontSize, fontWeight, color, null, height, null);
}

// ── Layout Constants ──────────────────────────────────────────────────────────

class AppLayout {
  static const titleBarHeight = 46.0;
  static const sidebarWidth   = 320.0;

  /// Left and right page margin.
  static const gutter = 28.0;
}

/// How long things take. Everything is zero when Windows has animations off,
/// so read these through [of].
class AppMotion {
  static const hover = Duration(milliseconds: 120);
  static const select = Duration(milliseconds: 180);
  static const fade = Duration(milliseconds: 220);

  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

// ── Radius Constants ──────────────────────────────────────────────────────────

class AppRadius {
  static const xs = Radius.circular(4);
  static const sm = Radius.circular(4);
  static const md = Radius.circular(7);
  static const lg = Radius.circular(10);
  static const xl = Radius.circular(10);

  static const borderXs = BorderRadius.all(xs);
  static const borderSm = BorderRadius.all(sm);
  static const borderMd = BorderRadius.all(md);
  static const borderLg = BorderRadius.all(lg);
  static const borderXl = BorderRadius.all(xl);
}

// ── ThemeData ─────────────────────────────────────────────────────────────────

class AppTheme {
  // Build a ThemeData from persisted settings values
  static ThemeData build({
    Color? accent,
    double fontSize = 13.0,
    bool dark = true,
  }) {
    final primary = accent ?? AppColors.accent;
    final base = dark ? ThemeData.dark() : ThemeData.light();
    final textTheme = base.textTheme.apply(fontFamily: AppText.uiFamily).copyWith(
      bodyMedium: AppText.ui(fontSize: fontSize, color: AppColors.textPrimary),
      bodySmall: AppText.ui(fontSize: fontSize - 2, color: AppColors.textSecondary),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgPrimary,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: primary,
        secondary: AppColors.accentLight,
        surface: AppColors.bgCard,
        error: AppColors.danger,
        onPrimary: AppColors.onAccent,
        onSecondary: AppColors.onAccent,
        onSurface: AppColors.textPrimary,
        onError: AppColors.bgPrimary,
      ),
      textTheme: textTheme,
      dividerColor: AppColors.border,
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.bgCard,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderLg,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderLg,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: DividerThemeData(
          color: AppColors.border, thickness: 1, space: 0),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
            return primary.withValues(alpha: 0.5);
          }
          return AppColors.border.withValues(alpha: 0.5);
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
        thumbVisibility: WidgetStateProperty.all(false),
        interactive: true,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: AppRadius.borderSm,
        ),
        textStyle: AppText.ui(fontSize: 11, color: AppColors.textPrimary),
        waitDuration: const Duration(milliseconds: 600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: AppText.ui(fontSize: 12, color: AppColors.textMuted),
        labelStyle: AppText.ui(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  // Convenience getter for the default dark theme
  static ThemeData get dark => build();

  // Mono text style for paths, stats, etc.
  static TextStyle get mono => AppText.mono(
    fontSize: 12,
    color: AppColors.textPrimary,
  );

  static TextStyle monoSm({Color? color}) =>
      AppText.mono(fontSize: 10, color: color ?? AppColors.textMuted);
}
