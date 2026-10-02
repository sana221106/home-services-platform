import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/notification_models.dart';

/// One notification row.
///
/// Unread rows carry a colored icon and a dot; read rows recede. The server owns
/// the title and body copy, so the row renders exactly what it was sent.
class NotificationTile extends StatelessWidget {
  const NotificationTile({required this.notification, this.onTap, super.key});

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final bool unread = !notification.isRead;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: unread ? colors.primarySoft : colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: AppIcon(
              notification.type.iconAsset,
              size: 20,
              color: unread ? colors.primary : colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  notification.title,
                  style: unread ? context.text.labelStrong : context.text.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  notification.body,
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Text(
                      formatRelative(notification.createdAt, l10n: l10n),
                      style: context.text.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (notification.type ==
                        NotificationType.unknown) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      AppChip(label: l10n.notificationsUnknownType),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (unread)
            Container(
              key: const Key('notification-unread-dot'),
              width: 8,
              height: 8,
              margin: const EdgeInsetsDirectional.only(
                start: AppSpacing.xs,
                top: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
