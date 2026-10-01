import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Elevation tokens (§46, §47, §48).
///
/// Shadows are semantic, not arbitrary: `card` for resting surfaces, `glass`
/// for the frosted premium surface, `hero` for the primary gradient and `cta`
/// for the primary button.
abstract final class AppShadows {
  /// Glass card: light #17315D at ~10%, offset 0,10, blur 28, spread -5.
  static const List<BoxShadow> lightGlass = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A17315D),
      blurRadius: 28,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
  ];

  /// Glass card: black at ~26%, offset 0,10, blur 28, spread -5.
  static const List<BoxShadow> darkGlass = <BoxShadow>[
    BoxShadow(
      color: Color(0x42000000),
      blurRadius: 28,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
  ];

  /// Primary hero: primary colour at ~25%, offset 0,15, blur 34, spread -7.
  static const List<BoxShadow> hero = <BoxShadow>[
    BoxShadow(
      color: Color(0x402557D6),
      blurRadius: 34,
      offset: Offset(0, 15),
      spreadRadius: -7,
    ),
  ];

  /// Primary CTA: primary colour at ~22%, offset 0,10, blur 24, spread -5.
  static const List<BoxShadow> cta = <BoxShadow>[
    BoxShadow(
      color: Color(0x382557D6),
      blurRadius: 24,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
  ];

  /// Low resting elevation for list rows and chips.
  static List<BoxShadow> soft(AppColors colors) => <BoxShadow>[
    BoxShadow(
      color: colors.textPrimary.withValues(alpha: 0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: -4,
    ),
  ];

  static List<BoxShadow> glass(AppColors colors) =>
      colors == AppColors.dark ? darkGlass : lightGlass;

  /// Glassmorphism is used selectively (§46). Callers must not wrap large
  /// scrolling subtrees in this: blur is expensive and it must never be applied
  /// to hundreds of elements at once.
  static const double glassOpacity = 0.86;

  /// Border opacity for glass surfaces.
  static const double glassBorderOpacity = 0.72;

  /// Background blur sigma.
  static const double glassBlur = 18;
}
