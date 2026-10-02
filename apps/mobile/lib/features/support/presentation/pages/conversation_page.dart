import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/support_models.dart';
import '../controllers/support_controllers.dart';
import '../widgets/support_widgets.dart';

/// One support thread.
///
/// The composer is pinned to the bottom rather than below the list so the
/// customer can always reply without scrolling back.
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({
    required this.conversationId,
    this.subject,
    super.key,
  });

  final String conversationId;
  final String? subject;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final String body = _composer.text.trim();
    if (body.isEmpty) return;

    // Cleared before the await so the composer is ready for the next message;
    // the list is refetched from the server, not appended optimistically.
    _composer.clear();
    ref.read(messagesProvider(widget.conversationId).notifier).send(body);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final MessagesState state = ref.watch(
      messagesProvider(widget.conversationId),
    );
    final String subject = widget.subject == null || widget.subject!.isEmpty
        ? l10n.supportChatTitle
        : widget.subject!;

    return AppPageScaffold(
      title: subject,
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: state.status == MessagesStatus.ready
          ? _Composer(
              controller: _composer,
              isSending: state.isSending,
              onSend: _send,
            )
          : null,
      body: switch (state.status) {
        MessagesStatus.initial || MessagesStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        MessagesStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () =>
              ref.read(messagesProvider(widget.conversationId).notifier).load(),
        ),
        MessagesStatus.ready => _Body(
          messages: state.messages,
          scroll: _scroll,
          onRetry: () =>
              ref.read(messagesProvider(widget.conversationId).notifier).load(),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.messages,
    required this.scroll,
    required this.onRetry,
  });

  final List<SupportMessage> messages;
  final ScrollController scroll;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    if (messages.isEmpty) {
      return EmptyState(
        title: l10n.supportMessagesEmpty,
        icon: 'assets/icons/chat.svg',
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.md,
        ),
        // `+ 1` so the newest message sits at the bottom of the first frame,
        // which is where a conversation opens.
        itemCount: messages.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                formatRelative(
                  messages.first.sentAt,
                  l10n: l10n,
                  now: messages.last.sentAt,
                ),
                style: context.text.caption.copyWith(
                  color: AppColors.of(context).textSecondary,
                ),
              ),
            );
          }
          return MessageBubble(message: messages[index - 1]);
        },
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return StickyFooter(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const Key('message-field'),
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: l10n.supportMessageHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filled(
          key: const Key('message-send'),
          onPressed: isSending ? null : onSend,
          icon: isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 18),
          tooltip: l10n.supportSend,
        ),
      ],
    );
  }
}
