import 'package:flutter/widgets.dart';

/// Spacing scale (§42).
///
/// The design frame is 390 x 844 with 18px side padding and 15px vertical
/// rhythm. Everything below is a multiple of that rhythm so screens stay
/// consistent, and every value is responsive rather than hardcoded per screen.
abstract final class AppSpacing {
  /// Screen side padding.
  static const double screenHorizontal = 18;

  /// Top inset below the status bar area.
  static const double screenTop = 38;

  /// Bottom safe-area padding.
  static const double screenBottom = 16;

  /// Typical vertical gap between stacked elements.
  static const double vertical = 15;

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Page padding that also respects a wide window (tablet/web).
  static EdgeInsets screen(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width > 600 ? (width - 560) / 2 : screenHorizontal;
    return EdgeInsets.fromLTRB(horizontal, screenTop, horizontal, screenBottom);
  }
}
