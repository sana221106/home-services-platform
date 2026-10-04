import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_style.dart';
import '../../app/localization/app_localizations.dart';
import 'app_icon.dart';

/// Standard page chrome: title, optional back affordance and subtitle.
///
/// Every one of the twenty screens (§40) reuses this so padding, type scale
/// and the RTL back-button position stay identical across the product.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.onBack,
    this.body,
    this.bottomBar,
    this.floatingActionButton,
    this.padded = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Null hides the back button. The app bar is leading on start and trailing
  /// on end, so the arrow mirrors correctly in RTL without extra logic.
  final VoidCallback? onBack;
  final Widget? body;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: context.text.title),
            if (subtitle != null)
              Text(
                subtitle!,
                style: context.text.caption.copyWith(
                  color: Theme.of(
                    context,
                  ).extension<AppColors>()!.textSecondary,
                ),
              ),
          ],
        ),
        actions: actions,
        leading: onBack == null
            ? null
            : IconButton(
                onPressed: onBack,
                icon: AppIcon(
                  'assets/icons/back.svg',
                  size: 22,
                  color: Theme.of(context).extension<AppColors>()!.textPrimary,
                ),
                tooltip: context.l10n.commonBack,
              ),
      ),
      body: body,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Frosted surface used for cards that sit on the gradient background (§46).
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderRadius,
    this.border = true,
    this.accent,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool border;

  /// Tints the leading accent bar, used to carry status colour.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(AppRadius.lg);

    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: AppShadows.glassOpacity),
        borderRadius: radius,
        border: border
            ? Border.all(
                color: colors.border.withValues(
                  alpha: AppShadows.glassBorderOpacity,
                ),
              )
            : null,
        boxShadow: AppShadows.glass(colors),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: surface),
    );
  }
}

/// Plain card for dense lists, where glass blur over many rows would be
/// expensive (§46 forbids glass on large scrolling subtrees).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.accent,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;

    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
        boxShadow: AppShadows.soft(colors),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Padding(padding: padding, child: child),
              ),
            ),
    );

    if (accent == null) return surface;
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(AppRadius.lg),
            ),
          ),
        ),
        Expanded(child: surface),
      ],
    );
  }
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: context.text.title)),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: colors.primary),
              child: Text(actionLabel!, style: context.text.label),
            ),
        ],
      ),
    );
  }
}

/// Small rounded label. Carries status colour rather than a random hue (§117).
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    this.icon,
    this.color,
    this.background,
    super.key,
  });

  final String label;
  final String? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final Color fg = color ?? colors.textSecondary;
    final Color bg = background ?? fg.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            AppIcon(icon!, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(label, style: context.text.caption.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Empty state: icon, message and an optional call to action.
///
/// Used instead of an empty box so a customer always learns why a list is empty
/// and what to do next (§116 forbids placeholder UI).
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.body,
    this.icon = 'assets/icons/doc.svg',
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? body;
  final String icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: AppIcon(icon, size: 32, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: context.text.title, textAlign: TextAlign.center),
            if (body != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                body!,
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error with a retry affordance, shown when a screen load fails.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: message,
      icon: 'assets/icons/alert.svg',
      actionLabel: onRetry == null ? null : context.l10n.commonRetry,
      onAction: onRetry,
    );
  }
}

/// Label/value row used across detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    this.valueWidget,
    super.key,
  });

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child:
                valueWidget ??
                Text(value, style: context.text.body, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Sticky footer holding the primary action of a wizard step.
class StickyFooter extends StatelessWidget {
  const StickyFooter({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.md,
          ),
          // Every child of a `Row` must be flexed: a non-flexed child is laid
          // out with an unbounded main axis, which a full-width button cannot
          // accept. Wizard footers therefore wrap their buttons in `Expanded`.
          child: Row(children: children),
        ),
      ),
    );
  }
}
