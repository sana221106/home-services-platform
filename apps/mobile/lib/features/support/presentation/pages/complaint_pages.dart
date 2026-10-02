import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/support_models.dart';
import '../../data/repositories/support_repository.dart';
import '../controllers/support_controllers.dart';
import '../widgets/support_widgets.dart';

/// Starts a new support thread.
///
/// Opening and first message are one request, so a thread can never be created
/// empty and then abandoned by a failed send.
class NewConversationPage extends ConsumerStatefulWidget {
  const NewConversationPage({this.requestId, super.key});

  final String? requestId;

  @override
  ConsumerState<NewConversationPage> createState() =>
      _NewConversationPageState();
}

class _NewConversationPageState extends ConsumerState<NewConversationPage> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _message.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final Conversation conversation = await ref
          .read(supportRepositoryProvider)
          .startConversation(
            requestId: widget.requestId,
            subject: _subject.text.trim(),
            firstMessage: body,
          );
      if (!mounted) return;

      // The new thread is opened, not shown in a list the customer has to find
      // it in.
      context.goNamed(
        AppRoute.conversationMessages.name,
        pathParameters: <String, String>{'conversationId': conversation.id},
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = context.l10n.commonSomethingWentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return AppPageScaffold(
      title: l10n.supportNewConversation,
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: StickyFooter(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              key: const Key('conversation-create'),
              onPressed: _sending ? null : _send,
              child: Text(l10n.supportSend),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            AppCard(
              child: Text(
                _error!,
                style: context.text.body.copyWith(color: colors.danger),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(l10n.supportChatTitle, style: context.text.title),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: <Widget>[
                TextField(
                  key: const Key('conversation-subject'),
                  controller: _subject,
                  decoration: InputDecoration(
                    labelText: l10n.supportChatTitle,
                    hintText: l10n.complaintSubjectHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('conversation-message'),
                  controller: _message,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: l10n.supportMessageHint,
                    hintText: l10n.complaintMessageHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Spec screen 16: filing a complaint.
///
/// The reason list comes from the server, and the description has a real minimum
/// length, so the field counter tells the customer what the backend requires
/// rather than letting the request fail on submit.
class NewComplaintPage extends ConsumerStatefulWidget {
  const NewComplaintPage({this.requestId, super.key});

  final String? requestId;

  @override
  ConsumerState<NewComplaintPage> createState() => _NewComplaintPageState();
}

class _NewComplaintPageState extends ConsumerState<NewComplaintPage> {
  final TextEditingController _description = TextEditingController();
  String? _reason;
  bool _loadingReasons = true;

  /// Mirrors the backend's `min_length=10` on the complaint description.
  static const int minimumDescriptionLength = 10;

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescriptionChanged);
    Future<void>.microtask(_loadReasons);
  }

  @override
  void dispose() {
    _description
      ..removeListener(_onDescriptionChanged)
      ..dispose();
    super.dispose();
  }

  void _onDescriptionChanged() => setState(() {});

  Future<void> _loadReasons() async {
    try {
      await ref.read(complaintsProvider.notifier).load();
    } on Object {
      // The list controller keeps the message; the form still shows whatever
      // reasons it already had cached.
    }
    if (!mounted) return;
    setState(() => _loadingReasons = false);
  }

  bool get _canSubmit =>
      _reason != null &&
      _description.text.trim().length >= minimumDescriptionLength;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final Complaint? complaint = await ref
        .read(complaintsProvider.notifier)
        .submit(
          requestId: widget.requestId,
          reason: _reason!,
          description: _description.text.trim(),
        );
    if (!mounted) return;

    if (complaint != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.complaintFiledSuccess)),
        );
      // Navigator rather than go_router, matching the other support screens, so
      // the form closes the same way whether it was opened from a tab or pushed.
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ComplaintsState state = ref.watch(complaintsProvider);
    final int remaining =
        minimumDescriptionLength - _description.text.trim().length;

    return AppPageScaffold(
      title: l10n.supportComplaintTitle,
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: StickyFooter(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              key: const Key('complaint-submit'),
              onPressed: _canSubmit && !state.isSubmitting ? _submit : null,
              child: Text(l10n.supportComplaintSubmit),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          if (state.errorMessage != null) ...<Widget>[
            AppCard(
              child: Text(
                state.errorMessage!,
                style: context.text.body.copyWith(color: colors.danger),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          Text(l10n.supportComplaintReasons, style: context.text.title),
          const SizedBox(height: AppSpacing.md),
          if (_loadingReasons)
            const Center(child: CircularProgressIndicator())
          else
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: RadioGroup<String>(
                // One group keeps the selection exclusive across rebuilds.
                groupValue: _reason,
                onChanged: (String? value) => setState(() => _reason = value),
                child: Column(
                  children: <Widget>[
                    for (final String code in state.reasons)
                      RadioListTile<String>(
                        key: Key('complaint-reason-$code'),
                        value: code,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_reasonLabel(code)),
                      ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          Text(l10n.supportComplaintDetails, style: context.text.title),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                TextField(
                  key: const Key('complaint-description'),
                  controller: _description,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: l10n.complaintMessageHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Counts up to the server's minimum instead of down, so the
                // number reads as progress towards being able to submit.
                Text(
                  remaining > 0
                      ? l10n.complaintSubmitHint
                      : '${_description.text.trim().length}',
                  style: context.text.caption.copyWith(
                    color: remaining > 0
                        ? colors.textSecondary
                        : colors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Server codes are matched against the local mirror for wording, and any code
  /// the app predates falls back to the raw value rather than vanishing.
  String _reasonLabel(String code) => complaintReasonLabel(context, code);
}
