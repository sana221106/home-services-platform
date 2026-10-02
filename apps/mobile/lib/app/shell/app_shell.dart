import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_localizations.dart';
import '../../core/widgets/app_icon.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';

/// Scaffold for the five tabbed destinations.
///
/// The shell owns the bottom bar and nothing else, so switching tabs is a
/// single [GoRouter] call and each tab keeps its own navigation stack.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<({HomeTab tab, String Function(AppLocalizations) label})>
  _items = <({HomeTab tab, String Function(AppLocalizations) label})>[
    (tab: HomeTab.home, label: _home),
    (tab: HomeTab.requests, label: _requests),
    (tab: HomeTab.properties, label: _properties),
    (tab: HomeTab.support, label: _support),
    (tab: HomeTab.profile, label: _profile),
  ];

  static String _home(AppLocalizations l) => l.homeTabLabel;
  static String _requests(AppLocalizations l) => l.requestsTabLabel;
  static String _properties(AppLocalizations l) => l.propertiesTabLabel;
  static String _support(AppLocalizations l) => l.supportTabLabel;
  static String _profile(AppLocalizations l) => l.profileTabLabel;

  void _onTap(BuildContext context, int index) {
    // Tapping the active tab returns it to its root, which is the behaviour
    // customers expect from a bottom bar.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (int index) => _onTap(context, index),
            destinations: <Widget>[
              for (final item in _items)
                NavigationDestination(
                  icon: AppIcon(
                    item.tab.iconAsset,
                    color: colors.textSecondary,
                    size: 24,
                  ),
                  selectedIcon: AppIcon(
                    item.tab.iconAsset,
                    color: colors.primary,
                    size: 24,
                  ),
                  label: item.label(l10n),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen progress indicator used while the session is being restored.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}
