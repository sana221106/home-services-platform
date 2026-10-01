import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/network/paginated.dart';
import '../../data/models/request_models.dart';
import '../../data/repositories/requests_repository.dart';

enum RequestsStatus { initial, loading, ready, failed }

class RequestsState extends Equatable {
  const RequestsState({
    this.status = RequestsStatus.initial,
    this.page,
    this.errorMessage,
    this.activeTab = RequestFilter.all,
    this.isLoadingMore = false,
  });

  final RequestsStatus status;
  final Paginated<ServiceRequest>? page;
  final String? errorMessage;

  /// Which slice of the lifecycle the list is showing.
  final RequestFilter activeTab;
  final bool isLoadingMore;

  List<ServiceRequest> get requests => page?.items ?? const <ServiceRequest>[];

  bool get hasNext => page?.hasNext ?? false;

  /// True only when the first load failed. A failed refresh while rows are
  /// already on screen must not blank the list.
  bool get isFatalError => status == RequestsStatus.failed && requests.isEmpty;

  RequestsState copyWith({
    RequestsStatus? status,
    Paginated<ServiceRequest>? page,
    String? errorMessage,
    RequestFilter? activeTab,
    bool? isLoadingMore,
    bool clearError = false,
  }) {
    return RequestsState(
      status: status ?? this.status,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeTab: activeTab ?? this.activeTab,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    page,
    errorMessage,
    activeTab,
    isLoadingMore,
  ];
}

/// The list is split by lifecycle stage rather than by raw status, because the
/// customer thinks in "what needs me" and "what's finished" (§40, screen 13).
enum RequestFilter {
  all('all'),
  active('active'),
  awaitingAction('awaitingAction'),
  completed('completed');

  const RequestFilter(this.id);

  final String id;

  /// Maps to the backend's `?status=` repeated query parameter.
  ///
  /// `active` mirrors the 19 statuses `GET /requests/active` treats as active,
  /// so the tab count matches what the server would return. `awaitingAction` is
  /// the subset that needs something from the customer.
  List<String> get statuses => switch (this) {
    RequestFilter.all => const <String>[],
    RequestFilter.active => activeStatusCodes,
    RequestFilter.awaitingAction => <String>[
      'NEED_MORE_INFORMATION',
      'AWAITING_CUSTOMER_APPROVAL',
      'QUOTE_SENT',
      'DEPOSIT_PENDING',
      'PAYMENT_PENDING',
      'INSPECTION_SCHEDULED',
      'AWAITING_RATING',
    ],
    RequestFilter.completed => const <String>[
      'RESOLVED',
      'CLOSED',
      'CANCELLED',
      'SERVICE_COMPLETED',
      'PAID',
    ],
  };

  /// The exact set `GET /requests/active` uses server-side.
  static const List<String> activeStatusCodes = <String>[
    'SUBMITTED',
    'UNDER_REVIEW',
    'NEED_MORE_INFORMATION',
    'INSPECTION_REQUIRED',
    'INSPECTION_SCHEDULED',
    'INSPECTION_IN_PROGRESS',
    'INSPECTION_COMPLETED',
    'QUOTE_PREPARATION',
    'QUOTE_SENT',
    'AWAITING_CUSTOMER_APPROVAL',
    'DEPOSIT_PENDING',
    'DEPOSIT_VERIFICATION',
    'CONFIRMED',
    'TECHNICIAN_ASSIGNMENT_PENDING',
    'TECHNICIAN_ASSIGNED',
    'ON_THE_WAY',
    'ARRIVED',
    'WORK_IN_PROGRESS',
    'PAYMENT_PENDING',
  ];
}

/// Backs the requests tab and the standalone Orders screen.
class RequestsController extends Notifier<RequestsState> {
  @override
  RequestsState build() => const RequestsState();

  Future<void> load({bool silent = false}) async {
    state = state.copyWith(
      status: silent ? state.status : RequestsStatus.loading,
      clearError: silent,
    );
    try {
      final page = await ref
          .read(requestsRepositoryProvider)
          .list(statuses: state.activeTab.statuses);
      state = RequestsState(
        status: RequestsStatus.ready,
        page: page,
        activeTab: state.activeTab,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: RequestsStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> switchFilter(RequestFilter filter) async {
    if (filter == state.activeTab) return;
    state = state.copyWith(activeTab: filter, status: RequestsStatus.loading);
    await load(silent: true);
  }

  Future<void> refresh() => load(silent: true);

  /// Appends the next page. Kept separate so pull-to-refresh and infinite
  /// scroll cannot race the same page number.
  Future<void> loadMore() async {
    final current = state.page;
    if (current == null || !current.hasNext || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await ref
          .read(requestsRepositoryProvider)
          .list(
            page: current.meta.page + 1,
            perPage: current.meta.perPage,
            statuses: state.activeTab.statuses,
          );
      state = state.copyWith(
        page: Paginated<ServiceRequest>(
          items: <ServiceRequest>[...current.items, ...next.items],
          meta: next.meta,
        ),
        isLoadingMore: false,
      );
    } on ApiFailure {
      // A failed page append keeps the rows already loaded; just stop the
      // spinner so the customer can pull to refresh.
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final NotifierProvider<RequestsController, RequestsState> requestsProvider =
    NotifierProvider<RequestsController, RequestsState>(
      RequestsController.new,
      name: 'requests',
    );

/// How many rows the customer still has to act on, for the tab badge.
///
/// Derived client-side from the same status sets the list uses, so the badge
/// can never disagree with the tab it opens.
final Provider<int> awaitingActionCountProvider = Provider<int>((Ref ref) {
  final all = ref.watch(requestsProvider).requests;
  final Set<String> waiting = RequestFilter.awaitingAction.statuses.toSet();
  return all.where((ServiceRequest r) => waiting.contains(r.status)).length;
});

/// Whether any visible request carries unread staff updates, which drives the
/// dot on the requests tab.
final Provider<bool> hasUnreadRequestUpdatesProvider = Provider<bool>((
  Ref ref,
) {
  final all = ref.watch(requestsProvider).requests;
  return all.any((ServiceRequest r) => r.hasUnreadUpdates);
});
