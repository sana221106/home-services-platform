import 'package:flutter/material.dart';

/// Semantic colour tokens (§44, §45).
///
/// Dark mode is a separate palette, not an inversion, so every colour the app
/// uses must be named for its role rather than its hue.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceSecondary,
    required this.surfaceVariant,
    required this.glass,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.primary,
    required this.primaryBright,
    required this.accent,
    required this.urgent,
    required this.danger,
    required this.success,
    required this.warning,
    required this.warningSoft,
    required this.primarySoft,
    required this.accentSoft,
    required this.dangerSoft,
    required this.hairline,
  });

  final Color background;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceSecondary;

  /// Recessed fill for nested rows, placeholders and image fallbacks. Distinct
  /// from [surface] so a card on a card still reads as two layers (§45).
  final Color surfaceVariant;

  final Color glass;

  final Color textPrimary;
  final Color textSecondary;

  final Color border;
  final Color hairline;

  final Color primary;
  final Color primaryBright;
  final Color accent;
  final Color urgent;
  final Color danger;
  final Color success;

  /// Amber used for "needs attention" states. [warningSoft] is its fill.
  final Color warning;

  final Color warningSoft;
  final Color primarySoft;
  final Color accentSoft;
  final Color dangerSoft;

  static const AppColors light = AppColors(
    background: Color(0xFFF4F7FC),
    backgroundSecondary: Color(0xFFEDF3FB),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF7F9FC),
    surfaceVariant: Color(0xFFEDF1F7),
    glass: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF667085),
    border: Color(0xFFDEE6F2),
    hairline: Color(0x140F172A),
    primary: Color(0xFF2557D6),
    primaryBright: Color(0xFF2F6BFF),
    accent: Color(0xFF19B394),
    urgent: Color(0xFFFF8A3D),
    danger: Color(0xFFE84A5F),
    success: Color(0xFF2EAD6B),
    warning: Color(0xFFF2A33C),
    warningSoft: Color(0xFFFFF3E8),
    primarySoft: Color(0xFFEEF4FF),
    accentSoft: Color(0xFFE8FAF6),
    dangerSoft: Color(0xFFFFE9ED),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF08111F),
    backgroundSecondary: Color(0xFF0C172A),
    surface: Color(0xFF101C30),
    surfaceSecondary: Color(0xFF15243C),
    surfaceVariant: Color(0xFF1C2E49),
    glass: Color(0xFF14233A),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF9AA9BD),
    border: Color(0xFF233651),
    hairline: Color(0x1FF8FAFC),
    primary: Color(0xFF2557D6),
    primaryBright: Color(0xFF2F6BFF),
    accent: Color(0xFF19B394),
    urgent: Color(0xFFFF8A3D),
    danger: Color(0xFFE84A5F),
    success: Color(0xFF2EAD6B),
    warning: Color(0xFFF2A33C),
    warningSoft: Color(0xFF3A281D),
    primarySoft: Color(0xFF172D5E),
    accentSoft: Color(0xFF12372F),
    dangerSoft: Color(0xFF3B2028),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceSecondary,
    Color? surfaceVariant,
    Color? glass,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? hairline,
    Color? primary,
    Color? primaryBright,
    Color? accent,
    Color? urgent,
    Color? danger,
    Color? success,
    Color? warning,
    Color? warningSoft,
    Color? primarySoft,
    Color? accentSoft,
    Color? dangerSoft,
  }) {
    return AppColors(
      background: background ?? this.background,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      glass: glass ?? this.glass,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      hairline: hairline ?? this.hairline,
      primary: primary ?? this.primary,
      primaryBright: primaryBright ?? this.primaryBright,
      accent: accent ?? this.accent,
      urgent: urgent ?? this.urgent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      primarySoft: primarySoft ?? this.primarySoft,
      accentSoft: accentSoft ?? this.accentSoft,
      dangerSoft: dangerSoft ?? this.dangerSoft,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryBright: Color.lerp(primaryBright, other.primaryBright, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }

  /// Convenience accessor so widgets read `context.colors.primary`.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;
}

extension AppColorsX on BuildContext {
  AppColors get colors => AppColors.of(this);
}
