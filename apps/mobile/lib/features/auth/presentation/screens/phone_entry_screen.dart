import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/localization/app_localizations.dart';
import '../../../../core/utils/phone_number.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../presentation/controllers/auth_controller.dart';

/// Asks for the phone number that the OTP will be sent to.
///
/// The customer never picks a password: the backend decides whether this phone
/// is new and the OTP endpoint is the only sign-in path.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  /// Prefixed dial code. Kept as a constant rather than a picker because the
  /// platform is a single market; the backend still validates the full number.
  static const String _dialCode = PhoneNumber.defaultDialCode;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String? normalised = PhoneNumber.normalize(_phoneController.text);
    if (normalised == null) return;

    final bool sent = await ref
        .read(authProvider.notifier)
        .requestOtp(phone: normalised, fullName: _nameController.text.trim());

    if (!mounted || !sent) return;
    await context.pushNamed(AppRoute.otpVerify.name);
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = ref.watch(authProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final bool isNew = state.isNewCustomer || state.error == null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.vertical,
          ),
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: AppIcon(
                  'assets/icons/back.svg',
                  color: colors.textPrimary,
                  semanticLabel: l10n.commonBack,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              l10n.authPhoneTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.authPhoneBody,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                      LengthLimitingTextInputFormatter(18),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.authPhoneLabel,
                      hintText: l10n.authPhoneHint,
                      prefixText: '$_dialCode ',
                      prefixStyle: Theme.of(context).textTheme.bodyLarge,
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.commonRequiredField;
                      }
                      return PhoneNumber.normalize(value) == null
                          ? l10n.authPhoneInvalid
                          : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.authNameLabel} (${l10n.commonOptional})',
                      hintText: l10n.authNameHint,
                    ),
                  ),
                ],
              ),
            ),
            if (state.error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _ErrorBanner(
                message: state.error!,
                onDismiss: () => ref.read(authProvider.notifier).clearError(),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colors.surface,
                      ),
                    )
                  : Text(l10n.commonContinue),
            ),
            if (isNew && state.error == null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.authPhoneNewAccountHint,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIcon('assets/icons/alert.svg', size: 20, color: colors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: AppIcon(
                'assets/icons/check.svg',
                size: 18,
                color: colors.danger,
              ),
            ),
        ],
      ),
    );
  }
}
