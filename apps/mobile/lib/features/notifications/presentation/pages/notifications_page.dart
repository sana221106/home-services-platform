import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/notification_models.dart';
import '../controllers/notifications_controller.dart';
import '../widgets/notification_widgets.dart';

/// The notification inbox.
///
/// Opening a row marks it read and, where the event points somewhere, takes the
/// customer there: the request for most events, the rate form for a rating
/// reminder, and the support tab for a complaint update.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(notificationsProvider.notifier).load(),
    );
  }

  void _open(AppNotification notification) {
    if (!notification.isRead) {
      ref.read(notificationsProvider.notifier).markRead(notification);
    }
    if (!notification.hasRequest) return;

    final String requestId = notification.requestId!;
    switch (notification.type) {
      case NotificationType.ratingReminder:
        context.pushNamed(
          AppRoute.rateService.name,
          pathParameters: <String, String>{'requestId': requestId},
        );
        return;
      case NotificationType.complaintUpdate:
        context.goNamed(AppRoute.support.name);
        return;
      default:
        context.pushNamed(
          AppRoute.requestDetail.name,
          pathParameters: <String, String>{'requestId': requestId},
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final NotificationsState state = ref.watch(notificationsProvider);
    final bool hasUnread = state.notifications.any(
      (AppNotification n) => !n.isRead,
    );

    return AppPageScaffold(
      title: l10n.profileNotifications,
      onBack: () => Navigator.of(context).maybePop(),
      actions: <Widget>[
        if (hasUnread)
          TextButton(
            key: const Key('notifications-mark-all-read'),
            onPressed: state.isMarkingAll
                ? null
                : () => ref.read(notificationsProvider.notifier).markAllRead(),
            child: Text(l10n.notificationsMarkAllRead),
          ),
      ],
      body: switch (state.status) {
        NotificationsStatus.initial || NotificationsStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        NotificationsStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () => ref.read(notificationsProvider.notifier).load(),
        ),
        NotificationsStatus.ready => _NotificationList(
          state: state,
          onOpen: _open,
        ),
      },
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({required this.state, required this.onOpen});

  final NotificationsState state;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    if (state.isEmpty) {
      return EmptyState(
        title: l10n.notificationsEmptyTitle,
        body: l10n.notificationsEmptyBody,
        icon: 'assets/icons/bell.svg',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).load(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          // The endpoint pages by row count, not offsets, so there is nothing to
          // prefetch until the customer nears the end of the current window.
          if (notification.metrics.extentAfter < 320) {
            ref.read(notificationsProvider.notifier).loadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.xxl,
          ),
          itemCount: state.notifications.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) {
            if (index >= state.notifications.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          l10n.commonLoading,
                          style: context.text.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                ),
              );
            }
            final AppNotification notification = state.notifications[index];
            return NotificationTile(
              notification: notification,
              onTap: () => onOpen(notification),
            );
          },
        ),
      ),
    );
  }
}
