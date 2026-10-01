import 'package:flutter/material.dart';

/// The design system scale (§43).
///
/// Cairo is an OFL variable font, so the weight is applied through the `wght`
/// axis. [TextStyle.fontWeight] is set as well so accessibility tooling and
/// text-scaling still see the intended emphasis.
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Cairo';

  static const TextStyle _base = TextStyle(
    fontFamily: fontFamily,
    height: 1.5,
    color: Colors.black,
    decoration: TextDecoration.none,
  );

  static TextStyle _style({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
  }) {
    return _base.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
    );
  }

  /// 32 / Bold - hero numbers and empty-state headlines.
  static TextStyle get display =>
      _style(size: 32, weight: FontWeight.w700, height: 1.25);

  /// 24 / Bold - screen titles.
  static TextStyle get heading =>
      _style(size: 24, weight: FontWeight.w700, height: 1.3);

  /// 20 / Bold - section headers.
  static TextStyle get title =>
      _style(size: 20, weight: FontWeight.w700, height: 1.35);

  /// 16 / Regular - emphasised body copy and list rows.
  static TextStyle get bodyLarge => _style(size: 16, weight: FontWeight.w400);

  /// 14 / Regular - default body.
  static TextStyle get body => _style(size: 14, weight: FontWeight.w400);

  /// 13 / SemiBold - labels and chips.
  static TextStyle get label =>
      _style(size: 13, weight: FontWeight.w600, height: 1.4);

  /// 12 / Regular - supporting metadata.
  static TextStyle get caption =>
      _style(size: 12, weight: FontWeight.w400, height: 1.4);

  /// 11 / Regular - timestamps and legal text.
  static TextStyle get captionSmall =>
      _style(size: 11, weight: FontWeight.w400, height: 1.4);

  /// Bold variant of [label] for buttons and tab titles.
  static TextStyle get labelStrong =>
      _style(size: 13, weight: FontWeight.w700, height: 1.3);

  /// Tabular figures for money so digits do not jitter between values.
  static TextStyle get numeric =>
      _style(size: 16, weight: FontWeight.w700, height: 1.3);
}
