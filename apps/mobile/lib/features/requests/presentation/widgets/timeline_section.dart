import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/constants/request_status.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';

/// The request's event history, newest first.
///
/// This is the customer's audit view: it is the record of what happened and
/// when, which is also why events are never edited or removed on the client.
class TimelineSection extends StatelessWidget {
  const TimelineSection({required this.events, super.key});

  final List<RequestEvent> events;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<RequestEvent> ordered = events.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.requestTimelineTitle),
        if (ordered.isEmpty)
          AppCard(
            child: Text(
              l10n.requestDetailNoTimeline,
              style: context.text.caption.copyWith(
                color: AppColors.of(context).textSecondary,
              ),
            ),
          )
        else
          AppCard(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < ordered.length; i++)
                  _TimelineRow(
                    event: ordered[i],
                    isFirst: i == 0,
                    // The connector is drawn between rows only, so the last
                    // entry has no trailing line hanging below it.
                    isLast: i == ordered.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final RequestEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final String actor = switch (event.actorType) {
      'CUSTOMER' => l10n.requestDetailAddedByYou,
      _ => l10n.requestDetailAddedByTeam,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Dot plus the vertical connector, so the rail reads as one line.
          Column(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFirst ? colors.primary : colors.border,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: colors.border)),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _headline(context),
                    style: context.text.body.copyWith(
                      fontWeight: isFirst ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_when(context)} · $actor',
                    style: context.text.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (event.note != null && event.note!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(event.note!, style: context.text.caption),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A status change reads better as the status it moved to; anything else uses
  /// the raw event type, which is still useful for support conversations.
  String _headline(BuildContext context) {
    final String? to = event.toStatus;
    if (to != null && to.isNotEmpty) {
      return requestStatusPresentation(context, to).label;
    }
    return event.eventType;
  }

  /// `occurred_at` is nullable in the schema, so a scheduled-but-not-yet-event
  /// row shows the event type alone instead of a bogus timestamp.
  String _when(BuildContext context) {
    final DateTime? when = event.occurredAt;
    if (when == null) return event.eventType;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final String date = material.formatMediumDate(when.toLocal());
    final String time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(when.toLocal()),
    );
    return '$date · $time';
  }
}
