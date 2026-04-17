import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────

class AppColors {
  static const bgPrimary    = Color(0xFF1A1D23);
  static const bgSecondary  = Color(0xFF13151A);
  static const bgCard       = Color(0xFF1E2128);
  static const bgCardAlt    = Color(0xFF22252D);
  static const bgHover      = Color(0xFF262B33);
  static const bgActive     = Color(0xFF2C323C);
  static const bgInput      = Color(0xFF14161B);

  static const accent       = Color(0xFF4A9E6E);
  static const accentLight  = Color(0xFF5CB87E);
  static const accentDim    = Color(0xFF3A7D58);
  static const accentGlow   = Color(0x4D4A9E6E);
  static const accentSilver = Color(0xFFA8B4C0);
  static const accentSilverDim = Color(0xFF7A8894);

  static const playGreen    = Color(0xFF5BA32B);
  static const playGreenHover = Color(0xFF6DBF35);
  static const installBlue  = Color(0xFF4A90D9);

  static const textPrimary  = Color(0xFFD0D5DC);
  static const textSecondary = Color(0xFF8A919A);
  static const textMuted    = Color(0xFF525A65);
  static const textBright   = Color(0xFFE8ECF0);

  static const danger       = Color(0xFFC94040);
  static const dangerDim    = Color(0xFFA03333);
  static const warning      = Color(0xFFD4943A);
  static const success      = Color(0xFF4A9E6E);

  static const border       = Color(0xFF2A2E36);
  static const borderLight  = Color(0xFF353A45);
  static const borderAccent = Color(0x664A9E6E);
}

// ── Layout Constants ──────────────────────────────────────────────────────────

class AppLayout {
  static const navbarHeight   = 40.0;
  static const statusbarHeight = 32.0;
  static const sidebarWidth   = 280.0;
  static const heroHeight     = 400.0;
}

// ── Radius Constants ──────────────────────────────────────────────────────────

class AppRadius {
  static const xs = Radius.circular(3);
  static const sm = Radius.circular(4);
  static const md = Radius.circular(8);
  static const lg = Radius.circular(12);
  static const xl = Radius.circular(16);

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
    Color accent = AppColors.accent,
    double fontSize = 13.0,
    bool dark = true,
  }) {
    final base = dark ? ThemeData.dark() : ThemeData.light();
    final bg = dark ? AppColors.bgCard : const Color(0xFFF2F4F7);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      bodyMedium: GoogleFonts.inter(fontSize: fontSize,
          color: dark ? AppColors.textPrimary : const Color(0xFF1A1D23)),
      bodySmall: GoogleFonts.inter(fontSize: fontSize - 2,
          color: dark ? AppColors.textSecondary : const Color(0xFF525A65)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? AppColors.bgPrimary : const Color(0xFFEEF0F5),
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: accent,
        secondary: Color.fromARGB(255,
          (accent.r * 1.1).clamp(0, 255).round(),
          (accent.g * 1.1).clamp(0, 255).round(),
          (accent.b * 1.1).clamp(0, 255).round(),
        ),
        surface: bg,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: dark ? AppColors.textPrimary : const Color(0xFF1A1D23),
        onError: Colors.white,
      ),
      textTheme: textTheme,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(
          color: AppColors.border, thickness: 1, space: 0),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.border),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(3),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: AppRadius.borderSm,
        ),
        textStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.textPrimary),
        waitDuration: const Duration(milliseconds: 600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderSm,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  // Convenience getter for the default dark theme
  static ThemeData get dark => build();

  // Mono text style for paths, stats, etc.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    color: AppColors.textPrimary,
  );

  static TextStyle monoSm({Color color = AppColors.textMuted}) =>
      GoogleFonts.jetBrainsMono(fontSize: 10, color: color);
}
