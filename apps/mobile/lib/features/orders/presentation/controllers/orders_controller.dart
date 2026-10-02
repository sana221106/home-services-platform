import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/network/paginated.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/orders_repository.dart';

enum OrdersStatus { initial, loading, ready, failed }

class OrdersState extends Equatable {
  const OrdersState({
    this.status = OrdersStatus.initial,
    this.page,
    this.errorMessage,
    this.isLoadingMore = false,
  });

  final OrdersStatus status;
  final Paginated<OrderSummary>? page;
  final String? errorMessage;
  final bool isLoadingMore;

  List<OrderSummary> get orders => page?.items ?? const <OrderSummary>[];

  bool get hasNext => page?.hasNext ?? false;

  /// True only when the first load failed. A failed refresh while rows are
  /// already visible must not blank the list.
  bool get isFatalError => status == OrdersStatus.failed && orders.isEmpty;

  OrdersState copyWith({
    OrdersStatus? status,
    Paginated<OrderSummary>? page,
    String? errorMessage,
    bool? isLoadingMore,
    bool clearError = false,
  }) {
    return OrdersState(
      status: status ?? this.status,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    page,
    errorMessage,
    isLoadingMore,
  ];
}

/// Backs the Orders screen.
///
/// No filter tabs here, unlike the requests list: `GET /orders` takes no
/// `?status=` parameter, so slicing by lifecycle client-side would silently drop
/// rows that live on the next page. The server already returns the accepted
/// total, the status label and the unread marker the rows need.
class OrdersController extends Notifier<OrdersState> {
  @override
  OrdersState build() => const OrdersState();

  Future<void> load({bool silent = false}) async {
    state = state.copyWith(
      status: silent ? state.status : OrdersStatus.loading,
      clearError: silent,
    );
    try {
      final page = await ref.read(ordersRepositoryProvider).list();
      state = OrdersState(status: OrdersStatus.ready, page: page);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: OrdersStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Appends the next page, guarded so a scroll listener and a pull-to-refresh
  /// cannot request the same page number twice.
  Future<void> loadMore() async {
    final current = state.page;
    if (current == null || !current.hasNext || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await ref
          .read(ordersRepositoryProvider)
          .list(page: current.meta.page + 1, perPage: current.meta.perPage);
      state = state.copyWith(
        page: Paginated<OrderSummary>(
          items: <OrderSummary>[...current.items, ...next.items],
          meta: next.meta,
        ),
        isLoadingMore: false,
      );
    } on ApiFailure {
      // Keep the rows already loaded; the customer can pull to refresh.
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final NotifierProvider<OrdersController, OrdersState> ordersProvider =
    NotifierProvider<OrdersController, OrdersState>(
      OrdersController.new,
      name: 'orders',
    );

/// Whether any order carries unread staff updates, which drives the dot on the
/// orders entry point.
final Provider<bool> hasUnreadOrderUpdatesProvider = Provider<bool>((Ref ref) {
  return ref
      .watch(ordersProvider)
      .orders
      .any((OrderSummary order) => order.hasUnreadUpdates);
});
