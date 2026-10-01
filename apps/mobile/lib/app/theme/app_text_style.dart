import 'package:flutter/material.dart';

import 'app_typography.dart';

/// Role-based access to the type scale.
///
/// Material's `TextTheme` exposes a fixed ladder of 15 slot names, while the
/// design system defines 8 roles. Widgets read `context.text.title` and
/// `context.text.body`, which keeps the mapping in one file instead of
/// scattering `titleMedium` / `bodySmall` guesses across every screen.
@immutable
class AppText {
  const AppText(this.theme);

  final TextTheme theme;

  /// 32 / Bold — hero numbers and empty-state headlines.
  TextStyle get display => theme.titleLarge ?? const TextStyle();

  /// 24 / Bold — screen titles.
  TextStyle get heading => theme.headlineSmall ?? const TextStyle();

  /// 20 / Bold — section headers.
  TextStyle get title => theme.titleMedium ?? const TextStyle();

  /// 16 / Regular — emphasised body copy and list rows.
  TextStyle get bodyLarge => theme.bodyLarge ?? const TextStyle();

  /// 14 / Regular — default body.
  TextStyle get body => theme.bodyMedium ?? const TextStyle();

  /// 13 / SemiBold — labels and chips.
  TextStyle get label => theme.labelMedium ?? const TextStyle();

  /// 13 / Bold — buttons and tab titles.
  TextStyle get labelStrong => theme.labelLarge ?? const TextStyle();

  /// 12 / Regular — supporting metadata.
  TextStyle get caption => theme.bodySmall ?? const TextStyle();

  /// The raw scale, for the rare case a widget needs Material's own slot.
  TextTheme get raw => theme;

  /// The font family, for widgets that must build a style from scratch.
  static String get fontFamily => AppTypography.fontFamily;
}

extension AppTextX on BuildContext {
  AppText get text => AppText(Theme.of(this).textTheme);
}
