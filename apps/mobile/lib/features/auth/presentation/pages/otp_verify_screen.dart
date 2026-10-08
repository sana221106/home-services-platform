import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../app/localization/app_localizations.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../presentation/controllers/auth_controller.dart';

/// Enters the OTP that was sent to the email captured in [AuthState.email].
///
/// The resend timer is cosmetic: the backend rate limit is authoritative, and
/// a stale timer must never be the reason a legitimate resend is blocked.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key});

  static const int codeLength = 6;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _ticker;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Show the backend's "code sent" confirmation once; it lives in
    // AuthState because the server authors it in the user's locale.
    final String? message = ref.read(authProvider).otpConfirmMessage;
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    final DateTime? target = ref.read(authProvider).resendAvailableAt;
    if (target == null) return;

    _secondsRemaining = target
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 86400);
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final DateTime? next = ref.read(authProvider).resendAvailableAt;
      final int left = next == null
          ? 0
          : next.difference(DateTime.now()).inSeconds.clamp(0, 86400);
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsRemaining = left);
      if (left <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final String code = _codeController.text.trim();
    if (code.length != OtpVerifyScreen.codeLength) return;

    // On success the router's redirect listener moves the customer to home;
    // navigating here as well would fight the shell.
    await ref.read(authProvider.notifier).verifyOtp(code: code);
  }

  Future<void> _resend() async {
    final String? email = ref.read(authProvider).email;
    if (email == null) return;

    final bool sent = await ref
        .read(authProvider.notifier)
        .requestOtp(email: email);
    if (!mounted || !sent) return;

    _startCountdown();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.authOtpSent)));
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = ref.watch(authProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final bool canSubmit =
        _codeController.text.trim().length == OtpVerifyScreen.codeLength &&
        !state.isSubmitting;
    final String? errorMessage =
        state.error ??
        switch (state.errorCode) {
          AuthErrorCode.emailRequired => l10n.authEmailRequired,
          null => null,
        };

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
                onPressed: () {
                  ref.read(authProvider.notifier).backToSignIn();
                  context.pop();
                },
                icon: AppIcon(
                  'assets/icons/back.svg',
                  color: colors.textPrimary,
                  semanticLabel: l10n.commonBack,
                ),
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(l10n.authOtpTitle, style: context.text.heading),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.authOtpBody(OtpVerifyScreen.codeLength),
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.email ?? '',
              textDirection: TextDirection.ltr,
              style: context.text.body.copyWith(color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              maxLength: OtpVerifyScreen.codeLength,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _verify(),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: context.text.heading,
              decoration: InputDecoration(
                labelText: l10n.authOtpField,
                counterText: '',
              ),
            ),
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                errorMessage,
                style: context.text.caption.copyWith(color: colors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: canSubmit ? _verify : null,
              child: state.isSubmitting
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colors.surface,
                      ),
                    )
                  : Text(l10n.authOtpVerify),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _secondsRemaining > 0 ? null : _resend,
              child: Text(
                _secondsRemaining > 0
                    ? l10n.authOtpResendIn(_secondsRemaining)
                    : l10n.authOtpResendNow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
