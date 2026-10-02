import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/profile_controller.dart';

/// Edits the two fields the profile endpoint accepts: name and email.
///
/// The phone is the sign-in identity and is not editable here; changing it needs
/// a verified new number, which is a different flow (§9).
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).profile;
    _name = TextEditingController(text: profile?.fullName ?? '');
    _email = TextEditingController(text: profile?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String email = _email.text.trim();
    final bool ok = await ref
        .read(profileProvider.notifier)
        .save(
          fullName: _name.text.trim(),
          // An emptied field is sent as null so the server clears it, rather
          // than being skipped and quietly left as it was.
          email: email.isEmpty ? null : email,
        );
    if (!mounted || !ok) return;

    ref.read(profileProvider.notifier).acknowledgeSaved();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.profileSavedMessage)));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ProfileState state = ref.watch(profileProvider);

    return AppPageScaffold(
      title: l10n.profileEditTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            TextFormField(
              key: const Key('profile-name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.profileNameLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) return l10n.commonRequiredField;
                if (text.length < 2) return l10n.commonRequiredField;
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('profile-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.profileEmailLabel,
                hintText: l10n.profileEmailHint,
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                // Deliberately loose: the server is the authority on what is
                // deliverable, and a strict client regex only blocks valid
                // addresses.
                return text.contains('@') ? null : l10n.commonRequiredField;
              },
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                state.errorMessage!,
                style: context.text.caption.copyWith(color: colors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('profile-save'),
                onPressed: state.isSaving ? null : _save,
                child: state.isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.profileSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
