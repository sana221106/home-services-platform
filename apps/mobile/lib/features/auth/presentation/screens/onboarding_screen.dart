import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_icon.dart';
import '../../presentation/controllers/auth_controller.dart';

/// Two-page value proposition shown once, before phone entry.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<String> _stepIcons = <String>[
    'assets/icons/wrench.svg',
    'assets/icons/camera.svg',
    'assets/icons/card.svg',
    'assets/icons/orders.svg',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    // Reset the session so a customer who reaches the end of onboarding always
    // lands on phone entry, never straight into a half-filled OTP screen.
    ref.read(authProvider.notifier).backToPhoneEntry();
    context.goNamed(AppRoute.phoneEntry.name);
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _page == 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _finish,
                child: Text(context.l10n.commonSkip),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (int index) => setState(() => _page = index),
                children: <Widget>[
                  const _WelcomePage(),
                  _HowItWorksPage(steps: _stepIcons),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < 2; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i
                          ? Theme.of(context).extension<AppColors>()!.primary
                          : Theme.of(context).extension<AppColors>()!.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: FilledButton(
                onPressed: () {
                  if (isLast) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: Text(
                  isLast
                      ? context.l10n.onboardingGetStarted
                      : context.l10n.commonNext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const AppIcon(
              'assets/icons/faucet.svg',
              size: 38,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.onboardingWelcomeTitle, style: context.text.display),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingWelcomeBody,
            style: context.text.bodyLarge.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final List<String> labels = <String>[
      l10n.onboardingStepChoose,
      l10n.onboardingStepDescribe,
      l10n.onboardingStepQuote,
      l10n.onboardingStepTrack,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(l10n.onboardingHowItWorksTitle, style: context.text.heading),
        const SizedBox(height: AppSpacing.lg),
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: AppIcon(steps[i], size: 22, color: colors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(labels[i], style: context.text.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
