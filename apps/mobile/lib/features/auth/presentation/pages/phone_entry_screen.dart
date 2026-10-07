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

/// Asks for the details the OTP is bound to.
///
/// The customer never picks a password: a six-digit code is sent to the email
/// address below and that code is the only sign-in path. The name is captured
/// here because the backend only trusts it once the code proves the address
/// belongs to this device; the phone is voluntary and stored for support.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  static final RegExp _emailPattern = RegExp(
    r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String? normalised = PhoneNumber.normalize(_phoneController.text);

    final bool sent = await ref.read(authProvider.notifier).requestOtp(
      email: _emailController.text.trim().toLowerCase(),
      phone: normalised,
      fullName: _nameController.text.trim(),
    );

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
              l10n.authSignInTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.authSignInBody,
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
                    controller: _nameController,
                    textDirection: TextDirection.rtl,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.authNameLabel,
                      hintText: l10n.authNameHint,
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.commonRequiredField;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(255),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.authEmailLabel,
                      hintText: l10n.authEmailHint,
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.commonRequiredField;
                      }
                      if (!_emailPattern.hasMatch(value.trim())) {
                        return l10n.authEmailInvalid;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                      LengthLimitingTextInputFormatter(18),
                    ],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.authPhoneLabel} (${l10n.commonOptional})',
                      hintText: l10n.authPhoneHint,
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return PhoneNumber.normalize(value) == null
                          ? l10n.authPhoneInvalid
                          : null;
                    },
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
                l10n.authEmailNewAccountHint,
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