import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/localization/app_localizations.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/payments_controller.dart';
import '../../data/models/payment_models.dart';
import '../widgets/payment_widgets.dart';

/// Spec screen 17: the Payment screen for one request.
///
/// Everything on screen comes from one `GET /requests/{id}/payment` call, so the
/// outstanding total, the deposit and the payment history can never disagree
/// with each other.
class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({required this.requestId, this.referenceCode, super.key});

  final String requestId;
  final String? referenceCode;

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PaymentsState state = ref.watch(paymentsProvider(widget.requestId));

    return AppPageScaffold(
      title: l10n.paymentViewTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: switch (state.status) {
        PaymentsStatus.initial || PaymentsStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        PaymentsStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () =>
              ref.read(paymentsProvider(widget.requestId).notifier).load(),
        ),
        PaymentsStatus.ready => _Content(
          state: state,
          referenceCode: widget.referenceCode,
          onSubmit: _openSubmitSheet,
          onAttachProof: _attachProof,
        ),
      },
    );
  }

  Future<void> _openSubmitSheet() async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PaymentsState state = ref.read(paymentsProvider(widget.requestId));
    final PaymentView? view = state.view;
    if (view == null) return;

    final _PaymentSubmission? submission =
        await showModalBottomSheet<_PaymentSubmission>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) =>
              _SubmitPaymentSheet(view: view, methods: state.methods),
        );
    // A dismissed sheet returns null, which must not read as a submission.
    if (submission == null) return;

    final PaymentRecord? record = await ref
        .read(paymentsProvider(widget.requestId).notifier)
        .submit(
          method: submission.method,
          amount: submission.amount,
          referenceNumber: submission.referenceNumber,
          isDeposit: submission.isDeposit,
        );
    if (record == null) return;

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.paymentEvidenceSubmitted)),
    );
  }

  Future<void> _attachProof(PaymentRecord payment) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bool ok = await ref
          .read(paymentsProvider(widget.requestId).notifier)
          .uploadProof(
            paymentId: payment.id,
            filePath: picked.path,
            fileName: picked.name,
          );
      if (!ok) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.paymentReceiptAttached)),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.paymentReceiptFailed)),
      );
    }
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.onSubmit,
    required this.onAttachProof,
    this.referenceCode,
  });

  final PaymentsState state;
  final String? referenceCode;
  final Future<void> Function() onSubmit;
  final ValueChanged<PaymentRecord> onAttachProof;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PaymentView? view = state.view;
    if (view == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        _SummaryCard(view: view),
        if (view.hasDeposit && view.deposit != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          DepositCard(deposit: view.deposit!),
        ],

        if (view.instructionsAr != null &&
            view.instructionsAr!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _InstructionsCard(text: view.instructionsAr!),
        ],

        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: l10n.paymentHistory),
        const SizedBox(height: AppSpacing.sm),
        if (!view.hasPayments)
          AppCard(
            child: Text(
              l10n.paymentNoHistory,
              style: context.text.body.copyWith(
                color: AppColors.of(context).textSecondary,
              ),
            ),
          )
        else
          for (final PaymentRecord payment in view.payments) ...<Widget>[
            PaymentTile(
              key: Key('payment-${payment.id}'),
              payment: payment,
              // A verified payment needs no receipt any more, and offering the
              // upload would imply it could still change the outcome.
              onAttachProof: payment.hasProof
                  ? null
                  : () => onAttachProof(payment),
              isUploading:
                  state.isUploadingProof &&
                  state.uploadingPaymentId == payment.id,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

        if (state.refunds.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: l10n.paymentRefunds),
          const SizedBox(height: AppSpacing.sm),
          for (final RefundRecord refund in state.refunds) ...<Widget>[
            RefundTile(refund: refund),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],

        // Nothing to pay and nothing pending: there is no action to offer, and a
        // disabled button would only invite tapping it.
        if (!view.isSettled || view.hasOpenPayment) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: const Key('payment-submit'),
            onPressed: state.isSubmitting ? null : onSubmit,
            icon: state.isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long, size: 18),
            label: Text(l10n.paymentSubmitEvidence),
          ),
        ],
      ],
    );
  }
}

/// The outstanding amount, with the accepted total for context.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.view});

  final PaymentView view;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            view.isSettled ? l10n.paymentFullyPaid : l10n.paymentAmountDue,
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            formatMoney(view.amountDue.toStringAsFixed(2)),
            style: context.text.heading.copyWith(
              color: view.isSettled ? colors.success : colors.textPrimary,
            ),
          ),
          if (view.quoteTotal != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${l10n.paymentQuoteTotal}: '
              '${formatMoney(view.quoteTotal!.toStringAsFixed(2))}',
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (view.referenceCode.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '#${view.referenceCode}',
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (view.supportPhone != null &&
              view.supportPhone!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            InfoRow(label: l10n.paymentSupportPhone, value: view.supportPhone!),
          ],
        ],
      ),
    );
  }
}

/// The finance team's own wording for how to pay.
class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.text.caption)),
        ],
      ),
    );
  }
}

/// What the sheet hands back to the page.
class _PaymentSubmission {
  const _PaymentSubmission({
    required this.method,
    required this.amount,
    required this.isDeposit,
    this.referenceNumber,
  });

  final String method;
  final double amount;
  final bool isDeposit;
  final String? referenceNumber;
}

/// The payment evidence form.
///
/// The amount starts at whatever the server says is outstanding, because that is
/// the number finance will check the transfer against; the deposit is offered
/// only when a deposit is actually attached.
class _SubmitPaymentSheet extends StatefulWidget {
  const _SubmitPaymentSheet({required this.view, required this.methods});

  final PaymentView view;
  final List<PaymentMethodOption> methods;

  @override
  State<_SubmitPaymentSheet> createState() => _SubmitPaymentSheetState();
}

class _SubmitPaymentSheetState extends State<_SubmitPaymentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();

  String? _method;
  bool _isDeposit = false;

  /// Methods come from the backend view, so an empty catalogue means there is
  /// nothing legitimate to submit.
  late final List<String> _codes = widget.view.methods;
  PaymentMethodOption? _optionFor(String code) {
    for (final PaymentMethodOption option in widget.methods) {
      if (option.code == code) return option;
    }
    return null;
  }

  bool get _needsReference {
    final PaymentMethodOption? option = _method == null
        ? null
        : _optionFor(_method!);
    // Cash is the one method with nothing to reference; an unknown method is
    // treated as needing one rather than silently skipping the field.
    return _method != null &&
        _method != 'CASH' &&
        (option?.requiresProof ?? true);
  }

  @override
  void initState() {
    super.initState();
    final DepositObligation? deposit = widget.view.deposit;
    final double amount = deposit != null && !deposit.isSatisfied
        ? deposit.outstandingAmount
        : widget.view.amountDue;
    _amount.text = amount > 0 ? amount.toStringAsFixed(2) : '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  double? get _parsedAmount => double.tryParse(_amount.text.trim());

  bool get _canSubmit {
    final double? amount = _parsedAmount;
    return _method != null &&
        _codes.contains(_method) &&
        amount != null &&
        amount > 0 &&
        // The backend caps a single submission at 1,000,000; matching it here
        // avoids a round trip that is certain to fail.
        amount <= 1000000 &&
        (!_needsReference || _reference.text.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final DepositObligation? deposit = widget.view.deposit;
    final PaymentMethodOption? option = _method == null
        ? null
        : _optionFor(_method!);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        // Lifts the sheet above the keyboard.
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.paymentSubmitEvidence, style: context.text.title),
            const SizedBox(height: AppSpacing.md),

            Text(l10n.paymentChooseMethod, style: context.text.labelStrong),
            const SizedBox(height: AppSpacing.xs),
            if (_codes.isEmpty)
              Text(
                l10n.commonSomethingWentWrong,
                style: context.text.caption.copyWith(color: colors.danger),
              )
            else
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final String code in _codes)
                    ChoiceChip(
                      key: Key('payment-method-$code'),
                      label: Text(
                        _optionFor(code)?.label ?? code,
                        textDirection: TextDirection.rtl,
                      ),
                      selected: _method == code,
                      onSelected: (_) => setState(() => _method = code),
                    ),
                ],
              ),

            // The backend's own per-method wording, so the finance team can
            // change the process without shipping the app.
            if (option?.instructionsAr != null &&
                option!.instructionsAr!.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                option.instructionsAr!,
                style: context.text.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('payment-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.paymentAmount,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),

            if (_needsReference) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('payment-reference'),
                controller: _reference,
                decoration: InputDecoration(
                  labelText: l10n.paymentReferenceNumber,
                  hintText: l10n.paymentReferenceHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],

            if (deposit != null && deposit.isRequired) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                key: const Key('payment-is-deposit'),
                value: _isDeposit,
                onChanged: (bool? value) =>
                    setState(() => _isDeposit = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${l10n.paymentIsDeposit} '
                  '(${formatMoney(deposit.outstandingAmount.toStringAsFixed(2))})',
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('payment-submit-confirm'),
                onPressed: _canSubmit
                    ? () => Navigator.of(context).pop(
                        _PaymentSubmission(
                          method: _method!,
                          amount: _parsedAmount!,
                          isDeposit: _isDeposit,
                          referenceNumber: _reference.text.trim().isEmpty
                              ? null
                              : _reference.text.trim(),
                        ),
                      )
                    : null,
                child: Text(l10n.paymentSubmitEvidence),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
