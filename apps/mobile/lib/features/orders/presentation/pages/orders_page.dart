import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/orders_controller.dart';
import '../widgets/order_card.dart';

/// Spec screen 13: the customer's order history.
///
/// Unlike the requests tab this screen is not part of the bottom bar, so it is
/// reachable from Home and owns its own back affordance.
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Loading is kicked off here rather than in the controller's build because
    // this page can be re-entered many times and should refetch on each visit.
    _scroll.addListener(_onScroll);
    Future<void>.microtask(() => ref.read(ordersProvider.notifier).load());
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
    // Fetch before the user reaches the bottom so the list never visibly stalls.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(ordersProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final OrdersState state = ref.watch(ordersProvider);

    return AppPageScaffold(
      title: l10n.ordersTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: _Body(state: state, scroll: _scroll),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.scroll});

  final OrdersState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    if (state.isFatalError) {
      return ErrorRetry(
        message: state.errorMessage ?? l10n.commonSomethingWentWrong,
        onRetry: () => ref.read(ordersProvider.notifier).refresh(),
      );
    }

    if (state.status == OrdersStatus.loading && state.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.orders.isEmpty) {
      return EmptyState(
        title: l10n.ordersEmptyTitle,
        body: l10n.ordersEmptyBody,
        icon: 'assets/icons/orders.svg',
        actionLabel: l10n.ordersEmptyCta,
        onAction: () => context.goNamed(AppRoute.requestNew.name),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
      child: ListView.separated(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        itemCount: state.orders.length + (state.hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.orders.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final order = state.orders[index];
          return OrderCard(
            key: Key('order-${order.requestId}'),
            order: order,
            onTap: () => context.goNamed(
              AppRoute.orderTracking.name,
              pathParameters: <String, String>{'requestId': order.requestId},
            ),
          );
        },
      ),
    );
  }
}
