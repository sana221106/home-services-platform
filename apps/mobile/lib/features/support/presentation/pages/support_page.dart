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
import '../controllers/support_controllers.dart';
import '../widgets/support_widgets.dart';

/// Which slice of support this tab is showing.
enum SupportSection { conversations, complaints }

/// Spec screen 15: the Support tab.
///
/// Conversations and complaints share this tab rather than taking a tab each,
/// because they are two views of the same need: getting help with a job.
class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  SupportSection _section = SupportSection.conversations;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadActive);
  }

  /// Only the visible section is fetched. Loading both on every visit would
  /// spend two extra round trips the customer may never need.
  void _loadActive() {
    switch (_section) {
      case SupportSection.conversations:
        ref.read(conversationsProvider.notifier).load();
      case SupportSection.complaints:
        ref.read(complaintsProvider.notifier).load();
    }
  }

  void _select(SupportSection section) {
    if (section == _section) return;
    setState(() => _section = section);
    _loadActive();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppPageScaffold(
      title: l10n.supportTitle,
      actions: <Widget>[
        if (_section == SupportSection.conversations)
          IconButton(
            key: const Key('support-new-conversation'),
            onPressed: () => context.pushNamed(AppRoute.conversationNew.name),
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: l10n.supportNewConversation,
          ),
      ],
      body: Column(
        children: <Widget>[
          _SectionToggle(active: _section, onChanged: _select),
          Expanded(
            child: switch (_section) {
              SupportSection.conversations => const _ConversationsBody(),
              SupportSection.complaints => const _ComplaintsBody(),
            },
          ),
        ],
      ),
    );
  }
}

class _SectionToggle extends StatelessWidget {
  const _SectionToggle({required this.active, required this.onChanged});

  final SupportSection active;
  final ValueChanged<SupportSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.xs,
        AppSpacing.screenHorizontal,
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _ToggleChip(
                label: l10n.supportThreadsTitle,
                selected: active == SupportSection.conversations,
                onTap: () => onChanged(SupportSection.conversations),
              ),
            ),
            Expanded(
              child: _ToggleChip(
                label: l10n.supportComplaintsTitle,
                selected: active == SupportSection.complaints,
                onTap: () => onChanged(SupportSection.complaints),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.label.copyWith(
            color: selected ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ConversationsBody extends ConsumerWidget {
  const _ConversationsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ConversationsState state = ref.watch(conversationsProvider);

    if (state.status == ConversationsStatus.failed &&
        state.conversations.isEmpty) {
      return ErrorRetry(
        message: state.errorMessage ?? l10n.commonSomethingWentWrong,
        onRetry: () => ref.read(conversationsProvider.notifier).load(),
      );
    }

    if (state.status == ConversationsStatus.loading &&
        state.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.conversations.isEmpty) {
      return EmptyState(
        title: l10n.supportThreadsEmptyTitle,
        body: l10n.supportThreadsEmptyBody,
        icon: 'assets/icons/chat.svg',
        actionLabel: l10n.supportNewConversation,
        onAction: () => context.pushNamed(AppRoute.conversationNew.name),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(conversationsProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        itemCount: state.conversations.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final Conversation conversation = state.conversations[index];
          return ConversationTile(
            key: Key('conversation-${conversation.id}'),
            conversation: conversation,
            onTap: () => openConversation(context, conversation),
          );
        },
      ),
    );
  }
}

class _ComplaintsBody extends ConsumerWidget {
  const _ComplaintsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ComplaintsState state = ref.watch(complaintsProvider);

    return Stack(
      children: <Widget>[
        if (state.status == ComplaintsStatus.failed && state.complaints.isEmpty)
          ErrorRetry(
            message: state.errorMessage ?? l10n.commonSomethingWentWrong,
            onRetry: () => ref.read(complaintsProvider.notifier).load(),
          )
        else if (state.status == ComplaintsStatus.loading &&
            state.complaints.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.complaints.isEmpty)
          EmptyState(
            title: l10n.supportComplaintsEmptyTitle,
            body: l10n.supportComplaintsEmptyBody,
            icon: 'assets/icons/flag.svg',
            actionLabel: l10n.supportComplaintSubmit,
            onAction: () => context.pushNamed(AppRoute.complaintNew.name),
          )
        else
          RefreshIndicator(
            onRefresh: () => ref.read(complaintsProvider.notifier).load(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.md,
                AppSpacing.screenHorizontal,
                96,
              ),
              itemCount: state.complaints.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int index) {
                return ComplaintTile(complaint: state.complaints[index]);
              },
            ),
          ),

        // The complaint form is the point of this section, so it is one tap
        // away at all times rather than only from the empty state.
        PositionedDirectional(
          bottom: AppSpacing.lg,
          end: AppSpacing.screenHorizontal,
          child: FloatingActionButton.extended(
            key: const Key('complaints-new'),
            onPressed: () => context.pushNamed(AppRoute.complaintNew.name),
            backgroundColor: AppColors.of(context).primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add, size: 20),
            label: Text(l10n.supportComplaintSubmit),
          ),
        ),
      ],
    );
  }
}
