import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/constants/request_status.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';
import '../controllers/requests_controller.dart';

/// Spec screen 13: the customer's request list.
///
/// Paging is cursor based through `Paginated`, and the backend accepts the tab
/// as a repeated `?status=` query parameter, so switching tabs resets to the
/// first page rather than filtering the page already in memory.
class RequestsPage extends ConsumerStatefulWidget {
  const RequestsPage({super.key});

  @override
  ConsumerState<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends ConsumerState<RequestsPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Fetch the next page before the user reaches the bottom so the list does
    // not visibly stall.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(requestsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final RequestsState state = ref.watch(requestsProvider);

    ref.listen(requestsProvider, (RequestsState? previous, RequestsState next) {
      if (next.status == RequestsStatus.failed &&
          next.errorMessage != null &&
          previous?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return AppPageScaffold(
      title: l10n.requestsTitle,
      actions: <Widget>[
        IconButton(
          key: const Key('requests-new'),
          onPressed: () => context.goNamed(AppRoute.requestNew.name),
          icon: const Icon(Icons.add),
          tooltip: l10n.requestsNew,
        ),
      ],
      body: Column(
        children: <Widget>[
          _FilterBar(
            active: state.activeTab,
            awaitingCount: ref.watch(awaitingActionCountProvider),
            onChanged: (RequestFilter filter) =>
                ref.read(requestsProvider.notifier).switchFilter(filter),
          ),
          Expanded(
            child: _Body(state: state, scroll: _scroll),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.active,
    required this.onChanged,
    required this.awaitingCount,
  });

  final RequestFilter active;
  final ValueChanged<RequestFilter> onChanged;
  final int awaitingCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        children: <Widget>[
          _FilterChip(
            label: l10n.requestsFilterAll,
            selected: active == RequestFilter.all,
            onTap: () => onChanged(RequestFilter.all),
          ),
          _FilterChip(
            label: l10n.requestsFilterActive,
            selected: active == RequestFilter.active,
            onTap: () => onChanged(RequestFilter.active),
          ),
          _FilterChip(
            label: awaitingCount > 0
                ? '${l10n.requestsFilterAction} ($awaitingCount)'
                : l10n.requestsFilterAction,
            selected: active == RequestFilter.awaitingAction,
            onTap: () => onChanged(RequestFilter.awaitingAction),
          ),
          _FilterChip(
            label: l10n.requestsFilterDone,
            selected: active == RequestFilter.completed,
            onTap: () => onChanged(RequestFilter.completed),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: context.text.label.copyWith(
          color: selected ? colors.primary : colors.textSecondary,
        ),
        selectedColor: colors.primarySoft,
        backgroundColor: colors.surface,
        side: BorderSide(color: selected ? colors.primary : colors.border),
        showCheckmark: false,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.scroll});

  final RequestsState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    if (state.isFatalError) {
      return ErrorRetry(
        message: state.errorMessage ?? l10n.commonSomethingWentWrong,
        onRetry: () => ref.read(requestsProvider.notifier).refresh(),
      );
    }

    if (state.status == RequestsStatus.loading && state.requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.requests.isEmpty) {
      return EmptyState(
        title: l10n.requestsEmptyTitle,
        body: l10n.requestsEmptyBody,
        icon: 'assets/icons/orders.svg',
        actionLabel: l10n.requestsNew,
        onAction: () => context.goNamed(AppRoute.requestNew.name),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(requestsProvider.notifier).refresh(),
      child: ListView.separated(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        itemCount: state.requests.length + (state.hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.requests.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return RequestCard(request: state.requests[index]);
        },
      ),
    );
  }
}

class RequestCard extends StatelessWidget {
  const RequestCard({required this.request, super.key});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ({Color color, String label}) status = requestStatusPresentation(
      context,
      request.status,
    );

    return AppCard(
      onTap: () => context.goNamed(
        AppRoute.requestDetail.name,
        pathParameters: <String, String>{'requestId': request.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  request.displayTitle,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (request.isUrgent)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                  ),
                  child: AppChip(
                    label: l10n.requestsUrgencyUrgentLabel,
                    color: colors.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '#${request.referenceCode}',
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),

          if (request.addressSummaryAr != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              request.addressSummaryAr!,
              style: context.text.caption.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              AppChip(label: status.label, color: status.color),
              const Spacer(),
              if (request.hasUnreadUpdates)
                AppChip(label: l10n.requestsNewActivity, color: colors.primary),
              if (request.mediaCount > 0) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    const Icon(Icons.image_outlined, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      '${request.mediaCount}',
                      style: context.text.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
