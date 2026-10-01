import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Light and dark themes built from the semantic tokens (§44, §45, §47).
abstract final class AppTheme {
  static const LinearGradient primaryGradient = LinearGradient(
    colors: <Color>[Color(0xFF173E9E), Color(0xFF2557D6), Color(0xFF2F6BFF)],
    stops: <double>[0, 0.58, 1],
  );

  static const LinearGradient ctaGradient = LinearGradient(
    colors: <Color>[Color(0xFF1D46AD), Color(0xFF2F6BFF)],
  );

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: brightness,
        ).copyWith(
          primary: colors.primary,
          secondary: colors.accent,
          error: colors.danger,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          outline: colors.border,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: AppTypography.fontFamily,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: _textTheme(colors),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title.copyWith(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colors.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.border,
          disabledForegroundColor: colors.textSecondary,
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          textStyle: AppTypography.labelStrong.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cta),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: colors.border),
          textStyle: AppTypography.labelStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: AppTypography.labelStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.body.copyWith(color: colors.textSecondary),
        labelStyle: AppTypography.label.copyWith(color: colors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.danger, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSecondary,
        side: BorderSide(color: colors.border),
        labelStyle: AppTypography.label.copyWith(color: colors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: AppTypography.title.copyWith(color: colors.textPrimary),
        contentTextStyle: AppTypography.body.copyWith(
          color: colors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.textPrimary,
        contentTextStyle: AppTypography.body.copyWith(color: colors.background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primarySoft,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.label.copyWith(
            color: selected ? colors.primary : colors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? colors.primary : colors.textSecondary,
          );
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.primarySoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : colors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.border,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        AppGradients(
          primary: AppTheme.primaryGradient,
          cta: AppTheme.ctaGradient,
          shadows: AppShadows.soft(colors),
        ),
      ],
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    TextStyle c(TextStyle style) => style.copyWith(color: colors.textPrimary);
    return TextTheme(
      displayLarge: c(AppTypography.display),
      displayMedium: c(AppTypography.display),
      displaySmall: c(AppTypography.heading),
      headlineLarge: c(AppTypography.heading),
      headlineMedium: c(AppTypography.heading),
      headlineSmall: c(AppTypography.title),
      titleLarge: c(AppTypography.title),
      titleMedium: c(AppTypography.label),
      titleSmall: c(AppTypography.label),
      bodyLarge: c(AppTypography.bodyLarge),
      bodyMedium: c(AppTypography.body),
      bodySmall: c(AppTypography.caption),
      labelLarge: c(AppTypography.labelStrong),
      labelMedium: c(AppTypography.label),
      labelSmall: c(AppTypography.caption),
    );
  }
}

/// Gradients and elevation, exposed as a theme extension so widgets never reach
/// for a literal colour.
@immutable
class AppGradients extends ThemeExtension<AppGradients> {
  const AppGradients({
    required this.primary,
    required this.cta,
    required this.shadows,
  });

  final LinearGradient primary;
  final LinearGradient cta;
  final List<BoxShadow> shadows;

  @override
  AppGradients copyWith({
    LinearGradient? primary,
    LinearGradient? cta,
    List<BoxShadow>? shadows,
  }) {
    return AppGradients(
      primary: primary ?? this.primary,
      cta: cta ?? this.cta,
      shadows: shadows ?? this.shadows,
    );
  }

  @override
  AppGradients lerp(ThemeExtension<AppGradients>? other, double t) {
    if (other is! AppGradients) return this;
    return AppGradients(
      primary: LinearGradient.lerp(primary, other.primary, t)!,
      cta: LinearGradient.lerp(cta, other.cta, t)!,
      shadows: shadows,
    );
  }

  static AppGradients of(BuildContext context) =>
      Theme.of(context).extension<AppGradients>() ??
      const AppGradients(
        primary: AppTheme.primaryGradient,
        cta: AppTheme.ctaGradient,
        shadows: <BoxShadow>[],
      );
}

extension AppGradientsX on BuildContext {
  AppGradients get gradients => AppGradients.of(this);
}
