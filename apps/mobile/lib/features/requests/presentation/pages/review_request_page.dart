import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';
import '../controllers/request_wizard_controller.dart';
import '../widgets/catalogue_labels.dart';
import '../widgets/request_wizard_scaffold.dart';
import '../widgets/wizard_navigation.dart';

/// Wizard step 5 of 5 (spec screen 10): review and submit.
///
/// This is where the request is actually created, so the shared "next" button
/// is replaced by a submit button. Submission is a three-stage protocol
/// (create draft, upload media, submit) that the controller owns; this screen
/// only reports the stage and surfaces the failure.
class ReviewRequestPage extends ConsumerWidget {
  const ReviewRequestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final RequestWizardState wizard = ref.watch(requestWizardProvider);
    final RequestWizardController controller = ref.read(
      requestWizardProvider.notifier,
    );

    return RequestWizardScaffold(
      step: RequestWizardStep.review,
      onBack: () =>
          wizardGoBack(context, controller, RequestWizardStep.location),
      // Submit replaces the shared next button, so the scaffold's own footer
      // is suppressed and the submit bar is supplied at the end of the body.
      bottomBar: StickyFooter(
        children: <Widget>[
          FilledButton(
            key: const Key('request-submit'),
            onPressed: wizard.canSubmit ? () => _submit(context, ref) : null,
            child: Text(
              wizard.isSubmitting
                  ? l10n.requestsSubmitting
                  : l10n.requestsSubmit,
            ),
          ),
          if (wizard.isSubmitting) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _stageLabel(wizard.phase, l10n),
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.requestsReviewTitle),

          // A partly filled wizard is still reviewable, so every section
          // renders whatever exists and gaps are labelled rather than hidden.
          // `canSubmit` is the hard gate.
          _ReviewSection(
            title: wizard.category == null
                ? l10n.requestsReviewMissingService
                : localisedCategoryName(wizard.category!, l10n.localeName),
            isMissing: wizard.category == null,
            icon: 'assets/icons/wrench.svg',
            onEdit: wizard.category == null
                ? null
                : () => controller.goToStep(RequestWizardStep.service),
          ),
          if (wizard.problemType != null)
            _ReviewSection(
              title: localisedProblemName(wizard.problemType!, l10n.localeName),
              isMissing: true,
              icon: 'assets/icons/tool_box.svg',
              onEdit: () =>
                  _edit(context, controller, RequestWizardStep.service),
            ),

          _ReviewSection(
            title: wizard.description.isEmpty
                ? l10n.requestsReviewMissingDetails
                : wizard.description,
            isMissing: !wizard.descriptionIsValid,
            icon: 'assets/icons/doc.svg',
            multiline: true,
            onEdit: () => _edit(context, controller, RequestWizardStep.details),
          ),

          _ReviewSection(
            title: wizard.photos.isEmpty
                ? l10n.requestsReviewMissingPhotos
                : l10n.requestsPhotosCount(
                    wizard.photos.length,
                    RequestMedia.maxPerRequest,
                  ),
            isMissing: !wizard.photosSatisfySubmit,
            icon: 'assets/icons/camera.svg',
            onEdit: () => _edit(context, controller, RequestWizardStep.photos),
          ),

          _ReviewSection(
            title: wizard.address == null
                ? l10n.requestsReviewMissingLocation
                : addressSummary(wizard.address!),
            isMissing: !wizard.isLocationValid,
            icon: 'assets/icons/pin.svg',
            onEdit: () =>
                _edit(context, controller, RequestWizardStep.location),
          ),

          if (wizard.isUrgent || wizard.inspectionOnly) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                if (wizard.isUrgent)
                  AppChip(
                    label: l10n.requestsUrgencyUrgentLabel,
                    color: colors.danger,
                  ),
                if (wizard.inspectionOnly)
                  AppChip(
                    label: l10n.requestInspectionOnly,
                    icon: 'assets/icons/alert.svg',
                    color: colors.warning,
                  ),
              ],
            ),
          ],

          if (wizard.notes != null && wizard.notes!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            InfoRow(label: l10n.requestsNoteLabel, value: wizard.notes!),
          ],

          if (wizard.errorMessage != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    wizard.errorMessage!,
                    style: context.text.body.copyWith(color: colors.danger),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: wizard.isSubmitting
                        ? null
                        : () => _submit(context, ref),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.requestsSubmitRetry),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Jumps back to an earlier step from the review row.
  ///
  /// `goNamed` rather than `pushNamed` because the review screen is the top of
  /// the stack; pushing would leave it underneath and the customer would return
  /// to it after editing.
  static void _edit(
    BuildContext context,
    RequestWizardController controller,
    RequestWizardStep step,
  ) {
    controller.goToStep(step);
    context.goNamed(RequestWizardController.routeFor(step));
  }

  /// Progress text for the three-stage submit, so the customer knows the button
  /// is working rather than frozen.
  static String _stageLabel(WizardSubmitPhase phase, AppLocalizations l10n) =>
      switch (phase) {
        WizardSubmitPhase.creatingDraft => l10n.requestsCreatedDraft,
        WizardSubmitPhase.uploading => l10n.requestsPhotosUploading,
        WizardSubmitPhase.submitting => l10n.requestsSubmitting,
        _ => '',
      };

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    // Everything context-derived is read before the await, so nothing has to
    // reach back across the async gap.
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String successMessage = context.l10n.requestsSubmitSuccess;

    final ServiceRequest? created = await ref
        .read(requestWizardProvider.notifier)
        .submit();
    if (created == null) return;

    // The wizard holds photo bytes and a draft id that mean nothing for a
    // different request, so it is discarded once the real one exists.
    ref.invalidate(requestWizardProvider);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMessage)));

    // Pop back to the list rather than leaving a review screen for a request
    // that no longer exists in the wizard.
    if (navigator.canPop()) navigator.pop();
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.onEdit,
    this.isMissing = false,
    this.multiline = false,
  });

  final String title;
  final String icon;
  final VoidCallback? onEdit;
  final bool isMissing;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppIcon(
              icon,
              size: 22,
              color: isMissing ? colors.warning : colors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (isMissing)
                    Text(
                      l10n.requestsReviewMissing,
                      style: context.text.caption.copyWith(
                        color: colors.warning,
                      ),
                    ),
                  Text(
                    title,
                    style: context.text.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isMissing
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                    maxLines: multiline ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              TextButton(
                onPressed: onEdit,
                child: Text(l10n.requestsReviewEdit),
              ),
          ],
        ),
      ),
    );
  }
}
