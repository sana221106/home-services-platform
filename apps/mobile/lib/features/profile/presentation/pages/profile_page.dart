import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/localization/locale_provider.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../app/theme/theme_mode_provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/models/profile_models.dart';
import '../controllers/profile_controller.dart';
import '../widgets/profile_widgets.dart';

/// The account tab: identity, counters, and the preferences that belong to the
/// customer rather than to a screen.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => ref.read(profileProvider.notifier).load());
  }

  Future<void> _pickLanguage() async {
    final AppLanguage current = ref.read(localeProvider).language;
    final AppLanguage? picked = await _pickOption<AppLanguage>(
      title: context.l10n.profileLanguageTitle,
      current: current,
      options: <AppLanguage>[
        AppLanguage.system,
        AppLanguage.arabic,
        AppLanguage.english,
      ],
      labelOf: (AppLanguage language) => switch (language) {
        AppLanguage.system => context.l10n.profileLanguageSystem,
        AppLanguage.arabic => context.l10n.profileLanguageArabic,
        AppLanguage.english => context.l10n.profileLanguageEnglish,
      },
    );
    if (picked == null) return;

    await ref.read(localeProvider.notifier).setLanguage(picked);
    // Keep the server copy in step so push copy arrives in the chosen language;
    // `system` has no server code and leaves the stored preference alone.
    final String? code = picked.backendCode;
    if (code != null && ref.read(authProvider).isAuthenticated) {
      await ref.read(profileProvider.notifier).save(preferredLanguage: code);
    }
  }

  Future<void> _pickTheme() async {
    final AppThemeMode current = ref.read(themeModeProvider).mode;
    final AppThemeMode? picked = await _pickOption<AppThemeMode>(
      title: context.l10n.profileThemeTitle,
      current: current,
      options: AppThemeMode.values,
      labelOf: (AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => context.l10n.profileThemeSystem,
        AppThemeMode.light => context.l10n.profileThemeLight,
        AppThemeMode.dark => context.l10n.profileThemeDark,
      },
    );
    if (picked == null) return;
    await ref.read(themeModeProvider.notifier).setMode(picked);
  }

  Future<void> _confirmLogout() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.profileLogoutConfirmTitle),
        content: Text(l10n.profileLogoutConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('profile-logout-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.profileLogout),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  /// Shared single-choice sheet, so language and appearance pickers are the
  /// same interaction rather than two bespoke dialogs.
  Future<T?> _pickOption<T>({
    required String title,
    required T current,
    required List<T> options,
    required String Function(T) labelOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (BuildContext context) {
        final AppColors colors = AppColors.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(title, style: context.text.title),
              ),
              for (final T option in options)
                ListTile(
                  key: Key('profile-option-$option'),
                  title: Text(labelOf(option)),
                  trailing: option == current
                      ? Icon(Icons.check, color: colors.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ProfileState state = ref.watch(profileProvider);
    final ProfileDetails? profile = state.profile;
    final AppLanguage language = ref.watch(localeProvider).language;
    final AppThemeMode theme = ref.watch(themeModeProvider).mode;

    return AppPageScaffold(
      title: l10n.profileTitle,
      body: switch (state.status) {
        ProfileStatus.initial || ProfileStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ProfileStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () => ref.read(profileProvider.notifier).load(),
        ),
        ProfileStatus.ready => RefreshIndicator(
          onRefresh: () => ref.read(profileProvider.notifier).load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.md,
              AppSpacing.screenHorizontal,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              GlassCard(
                child: Column(
                  children: <Widget>[
                    ProfileHeader(profile: profile!),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: <Widget>[
                        ProfileStat(
                          value: profile.propertiesCount,
                          label: l10n.profileStatProperties,
                        ),
                        ProfileStat(
                          value: profile.requestsCount,
                          label: l10n.profileStatRequests,
                        ),
                        ProfileStat(
                          value: profile.completedOrdersCount,
                          label: l10n.profileStatCompleted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(title: l10n.profileSectionAccount),
              ProfileMenuItem(
                icon: 'assets/icons/edit.svg',
                label: l10n.profileEdit,
                onTap: () => context.pushNamed(AppRoute.profileEdit.name),
              ),
              ProfileMenuItem(
                icon: 'assets/icons/bell.svg',
                label: l10n.profileNotifications,
                onTap: () => context.pushNamed(AppRoute.notifications.name),
              ),
              const SizedBox(height: AppSpacing.md),
              SectionHeader(title: l10n.profileSectionPreferences),
              ProfileMenuItem(
                icon: 'assets/icons/info.svg',
                label: l10n.profileLanguage,
                value: switch (language) {
                  AppLanguage.system => l10n.profileLanguageSystem,
                  AppLanguage.arabic => l10n.profileLanguageArabic,
                  AppLanguage.english => l10n.profileLanguageEnglish,
                },
                onTap: _pickLanguage,
              ),
              ProfileMenuItem(
                icon: 'assets/icons/sparkle.svg',
                label: l10n.profileTheme,
                value: switch (theme) {
                  AppThemeMode.system => l10n.profileThemeSystem,
                  AppThemeMode.light => l10n.profileThemeLight,
                  AppThemeMode.dark => l10n.profileThemeDark,
                },
                onTap: _pickTheme,
              ),
              const SizedBox(height: AppSpacing.md),
              SectionHeader(title: l10n.profileSettings),
              ProfileMenuItem(
                icon: 'assets/icons/chat.svg',
                label: l10n.profileSupport,
                onTap: () => context.goNamed(AppRoute.support.name),
              ),
              ProfileMenuItem(
                icon: 'assets/icons/logout.svg',
                label: l10n.profileLogout,
                destructive: true,
                onTap: _confirmLogout,
              ),
              if (state.errorMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  state.errorMessage!,
                  style: context.text.caption.copyWith(color: colors.danger),
                ),
              ],
            ],
          ),
        ),
      },
    );
  }
}
