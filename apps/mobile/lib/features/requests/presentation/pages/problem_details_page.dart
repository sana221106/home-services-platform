import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/request_wizard_controller.dart';
import '../widgets/request_wizard_scaffold.dart';
import '../widgets/wizard_navigation.dart';

/// Bounds enforced by `CreateServiceRequestRequest.problem_description`.
const int _descriptionMin = 10;
const int _descriptionMax = 4000;

/// Wizard step 2 of 5 (spec screen 7): describe the problem.
///
/// Also collects the optional extras that ride on the same backend payload:
/// urgency, inspection-only and customer notes.
class ProblemDetailsPage extends ConsumerWidget {
  const ProblemDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final RequestWizardState wizard = ref.watch(requestWizardProvider);
    final RequestWizardController controller = ref.read(
      requestWizardProvider.notifier,
    );

    final int length = wizard.description.trim().length;
    final bool tooShort = length > 0 && length < _descriptionMin;

    return RequestWizardScaffold(
      step: RequestWizardStep.details,
      onBack: () =>
          wizardGoBack(context, controller, RequestWizardStep.service),
      nextEnabled: wizard.descriptionIsValid,
      onNext: () => wizardGoNext(context, controller, RequestWizardStep.photos),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.requestsDescribeTitle),
          WizardTextField(
            fieldKey: const Key('request-description-field'),
            value: wizard.description,
            onChanged: controller.setDescription,
            hintText: l10n.requestsDescribeHint,
            minLines: 5,
            maxLines: 8,
            maxLength: _descriptionMax,
            // The length counter below is friendlier than the built-in one, so
            // the field's own counter is suppressed by capping it out of view.
            errorText: tooShort ? l10n.requestsDescTooShort : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '$length / $_descriptionMax',
              style: context.text.caption.copyWith(
                color: length > _descriptionMax
                    ? colors.danger
                    : colors.textSecondary,
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: l10n.requestsScheduleTitle),
          _UrgencySelector(
            value: wizard.urgency,
            // An inspection-only request cannot also be urgent; the backend
            // rejects the pair, so the option is disabled rather than hidden.
            urgentDisabled: wizard.inspectionOnly,
            onChanged: controller.setUrgency,
          ),

          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            key: const Key('request-inspection-only'),
            value: wizard.inspectionOnly,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.requestInspectionOnly, style: context.text.body),
            subtitle: Text(
              l10n.requestsInspectionOnlyHint,
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
            onChanged: (bool value) {
              controller.setInspectionOnly(value);
              if (value && wizard.urgency == 'URGENT') {
                // The backend returns 400 for inspection_only + URGENT, so the
                // downgrade happens here rather than as a submit failure.
                controller.setUrgency('NORMAL');
              }
            },
          ),

          const SizedBox(height: AppSpacing.md),
          SectionHeader(title: l10n.requestsNoteLabel),
          WizardTextField(
            value: wizard.notes ?? '',
            onChanged: controller.setNotes,
            hintText: l10n.commonOptional,
            minLines: 2,
            maxLines: 4,
          ),

          if (wizard.category?.requiresInspectionDefault ?? false) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppChip(
              label: l10n.requestInspectionOnly,
              icon: 'assets/icons/alert.svg',
              color: colors.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _UrgencySelector extends StatelessWidget {
  const _UrgencySelector({
    required this.value,
    required this.onChanged,
    required this.urgentDisabled,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool urgentDisabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final bool urgent = value == 'URGENT';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: WizardSelectTile(
            title: l10n.requestsUrgencyNormal,
            selected: !urgent,
            onTap: () => onChanged('NORMAL'),
            trailing: !urgent
                ? Icon(Icons.check_circle, size: 20, color: colors.primary)
                : null,
          ),
        ),
        Expanded(
          child: WizardSelectTile(
            title: l10n.requestsUrgencyUrgentLabel,
            subtitle: urgentDisabled
                ? l10n.requestsInspectionOnlyHint
                : l10n.requestsScheduleUrgentHint,
            selected: urgent,
            onTap: urgentDisabled ? null : () => onChanged('URGENT'),
            trailing: urgent
                ? Icon(Icons.check_circle, size: 20, color: colors.primary)
                : null,
          ),
        ),
      ],
    );
  }
}
