import 'package:home_services_app/app/theme/app_colors.dart';
import 'package:home_services_app/app/theme/app_radius.dart';
import 'package:home_services_app/app/theme/app_shadows.dart';
import 'package:home_services_app/app/theme/app_spacing.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/app/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('design tokens', () {
    test('both themes build and expose the colour extension', () {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        expect(theme.extension<AppColors>(), isNotNull);
        expect(theme.extension<AppGradients>(), isNotNull);
      }
    });

    test(
      'light and dark backgrounds are distinct palettes, not inversions',
      () {
        expect(AppColors.light.background, isNot(AppColors.dark.background));
        expect(AppColors.light.surface, const Color(0xFFFFFFFF));
        expect(AppColors.dark.surface, const Color(0xFF101C30));
      },
    );

    test('primary gradient has the specified middle stop', () {
      final stops = AppTheme.primaryGradient.stops;
      expect(stops, isNotNull);
      expect(stops!.last, 1.0);
      expect(stops.reduce((double a, double b) => a < b ? a : b), 0.0);
      expect(stops.any((double s) => (s - 0.58).abs() < 0.01), isTrue);
    });

    test('typography uses Cairo on every named style', () {
      final styles = <TextStyle>[
        AppTypography.display,
        AppTypography.heading,
        AppTypography.title,
        AppTypography.bodyLarge,
        AppTypography.body,
        AppTypography.label,
        AppTypography.caption,
      ];
      for (final style in styles) {
        expect(style.fontFamily, AppTypography.fontFamily);
        expect(style.fontSize, isNotNull);
      }
      expect(AppTypography.display.fontSize, 32);
      expect(AppTypography.heading.fontSize, 24);
      expect(AppTypography.title.fontSize, 20);
      expect(AppTypography.bodyLarge.fontSize, 16);
      expect(AppTypography.body.fontSize, 14);
      expect(AppTypography.label.fontSize, 13);
    });

    test('spacing and radius match the design frame', () {
      expect(AppSpacing.screenHorizontal, 18);
      expect(AppSpacing.vertical, 15);
      expect(AppRadius.screen, 34);
      expect(AppRadius.cta, 19);
    });

    test('glass elevation switches with the active palette', () {
      expect(
        identical(AppShadows.glass(AppColors.light), AppShadows.lightGlass),
        isTrue,
      );
      expect(
        identical(AppShadows.glass(AppColors.dark), AppShadows.darkGlass),
        isTrue,
      );
    });

    test('glass shadows are drawn down, not up', () {
      // A negative spread keeps the blur from ringing the top edge.
      for (final shadow in <BoxShadow>[
        ...AppShadows.lightGlass,
        ...AppShadows.darkGlass,
        ...AppShadows.hero,
        ...AppShadows.cta,
      ]) {
        expect(shadow.offset.dy, greaterThan(0));
        expect(shadow.spreadRadius, lessThan(0));
      }
    });

    test('soft elevation derives from the palette it is given', () {
      final light = AppShadows.soft(AppColors.light);
      final dark = AppShadows.soft(AppColors.dark);

      expect(light.single.color, isNot(dark.single.color));
      expect(light.single.color.a, closeTo(0.05, 0.001));
    });

    test('glassmorphism constants stay within the documented bounds', () {
      expect(AppShadows.glassOpacity, inInclusiveRange(0.8, 0.95));
      expect(AppShadows.glassBorderOpacity, inInclusiveRange(0.6, 0.85));
      expect(AppShadows.glassBlur, inInclusiveRange(12, 24));
    });
  });
}
