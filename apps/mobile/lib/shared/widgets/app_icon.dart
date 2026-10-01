import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bundled SVG icon.
///
/// Icons come from `assets/icons/` and inherit colour from `currentColor`, so
/// a theme change never needs a second asset set and no emoji are used
/// anywhere in the product (§49).
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.asset, {
    this.size = 24,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
