import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../data/models/profile_models.dart';

/// The account header: avatar, name, phone and join date.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({required this.profile, super.key});

  final ProfileDetails profile;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 32,
          backgroundColor: colors.primarySoft,
          // A broken or absent image must not blank the header, so the initials
          // take over whenever there is no URL.
          backgroundImage: profile.hasAvatar
              ? NetworkImage(profile.avatarUrl!)
              : null,
          child: profile.hasAvatar
              ? null
              : Text(
                  profile.initials,
                  style: context.text.heading.copyWith(color: colors.primary),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                profile.fullName,
                style: context.text.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                profile.phone.isNotEmpty ? profile.phone : '—',
                style: context.text.body.copyWith(color: colors.textSecondary),
                // The phone is shown read-only; it is the sign-in identity and
                // changing it needs a verified number, not a profile edit. A
                // Google account has no number to show, so show a dash.
              ),
              if (profile.memberSince != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${l10n.profileMemberSinceLabel} ${formatDate(profile.memberSince)}',
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single counter under the header.
class ProfileStat extends StatelessWidget {
  const ProfileStat({required this.value, required this.label, super.key});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Expanded(
      child: Column(
        children: <Widget>[
          Text('$value', style: context.text.heading),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: context.text.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// One tappable row in the account menu.
class ProfileMenuItem extends StatelessWidget {
  const ProfileMenuItem({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final String icon;
  final String label;

  /// Current selection, e.g. the active language, shown before the chevron.
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color tint = destructive ? colors.danger : colors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              AppIcon(icon, size: 22, color: tint),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: context.text.body.copyWith(color: tint),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  style: context.text.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Transform.flip(
                // The row is a navigation affordance, so the chevron points
                // toward the reading direction: right in LTR, left in RTL.
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
