import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/constants/request_status.dart';
import '../../../../core/errors/failure.dart';
import '../../data/models/request_models.dart';
import '../../data/repositories/requests_repository.dart';

enum RequestDetailStatus { initial, loading, ready, failed }

class RequestDetailState extends Equatable {
  const RequestDetailState({
    this.status = RequestDetailStatus.initial,
    this.request,
    this.events = const <RequestEvent>[],
    this.quote,
    this.errorMessage,
    this.isActing = false,
    this.actionError,
  });

  final RequestDetailStatus status;
  final ServiceRequest? request;
  final List<RequestEvent> events;
  final Quote? quote;
  final String? errorMessage;

  /// True while accept/reject/cancel is in flight, so the buttons can lock.
  final bool isActing;
  final String? actionError;

  AppRequestStatus? get requestStatus =>
      AppRequestStatus.fromCode(request?.status);

  /// A quote in `SENT` or `AWAITING_CUSTOMER_APPROVAL` is one the customer can
  /// still act on. `EXPIRED` and a decided quote are not.
  bool get hasQuoteToAnswer => quote?.isOpen ?? false;

  /// Mirrors the server's cancellable set.
  ///
  /// The backend can still refuse based on deposits and staffing, so a 409 is
  /// possible; this only avoids offering an action that is certain to fail.
  bool get canCancel =>
      (requestStatus?.canCancelOptimistically ?? false) && !isActing;

  bool get canRate =>
      (requestStatus?.canRateOptimistically ?? false) && !isActing;

  bool get canComplain =>
      (requestStatus?.canComplainOptimistically ?? false) && !isActing;

  /// The request identifier, exposed so the action bar can hand it to the
  /// payment and complaint routes instead of each page re-reading it.
  String get requestId => request?.id ?? '';

  String get referenceCode => request?.referenceCode ?? '';

  /// Payment is offered whenever an accepted quote exists: the money is owed
  /// from acceptance, long before the job reaches a status that allows rating.
  ///
  /// Whether anything is actually outstanding is the Payment screen's call, not
  /// this page's, so the button appears and the screen explains the rest.
  bool get canPay =>
      quote?.isAccepted == true &&
      (requestStatus?.canCancelOptimistically ?? true) &&
      !isActing;

  RequestDetailState copyWith({
    RequestDetailStatus? status,
    ServiceRequest? request,
    List<RequestEvent>? events,
    Quote? quote,
    String? errorMessage,
    bool? isActing,
    String? actionError,
    bool clearError = false,
    bool clearActionError = false,
    bool clearQuote = false,
  }) {
    return RequestDetailState(
      status: status ?? this.status,
      request: request ?? this.request,
      events: events ?? this.events,
      quote: clearQuote ? null : (quote ?? this.quote),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isActing: isActing ?? this.isActing,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    request,
    events,
    quote,
    errorMessage,
    isActing,
    actionError,
  ];
}

/// Loads one request together with its timeline and quote.
///
/// Riverpod 3 hands the family argument to the constructor, so the request id
/// is a field rather than a `build` parameter. The first load is kicked off in
/// `build` so a page that only watches the provider still fetches.
class RequestDetailController extends Notifier<RequestDetailState> {
  RequestDetailController(this.requestId);

  final String requestId;

  @override
  RequestDetailState build() {
    Future<void>.microtask(load);
    return const RequestDetailState();
  }

  Future<void> load({bool force = false}) async {
    if (state.status == RequestDetailStatus.loading) return;
    if (!force &&
        state.status == RequestDetailStatus.ready &&
        state.request != null) {
      return;
    }

    state = state.copyWith(
      status: RequestDetailStatus.loading,
      clearError: true,
    );

    final RequestsRepository repository = ref.read(requestsRepositoryProvider);

    try {
      // All three are keyed on the request id and none depends on another, so
      // they run together instead of tripling time to first paint. A null quote
      // is a normal result (most requests never get one), not a failure.
      final List<Object?> results =
          await Future.wait<Object?>(<Future<Object?>>[
            repository.detail(requestId),
            repository.timeline(requestId),
            repository.quote(requestId),
          ]);

      state = state.copyWith(
        status: RequestDetailStatus.ready,
        request: results[0]! as ServiceRequest,
        events: results[1]! as List<RequestEvent>,
        quote: results[2] as Quote?,
        clearError: true,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: RequestDetailStatus.failed,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: RequestDetailStatus.failed,
        errorMessage: null,
      );
    }
  }

  /// Accepting sends the revision number, because a newer quote may have been
  /// issued while this screen was open and a stale revision is rejected.
  Future<void> acceptQuote() async {
    final Quote? quote = state.quote;
    if (quote == null || state.isActing) return;

    state = state.copyWith(isActing: true, clearActionError: true);
    try {
      final ServiceRequest updated = await ref
          .read(requestsRepositoryProvider)
          .acceptQuote(requestId, acceptedRevision: quote.revisionNumber);
      state = state.copyWith(
        request: updated,
        clearQuote: true,
        isActing: false,
      );
    } on ApiFailure catch (failure) {
      // The quote stays put so the customer can retry without reloading.
      state = state.copyWith(isActing: false, actionError: failure.message);
    }
  }

  /// A blank reason is sent as null: the API takes an optional reason and an
  /// empty string would be stored as a real, meaningless value.
  Future<void> rejectQuote({String? reason}) async {
    if (state.quote == null || state.isActing) return;

    state = state.copyWith(isActing: true, clearActionError: true);
    try {
      final ServiceRequest updated = await ref
          .read(requestsRepositoryProvider)
          .rejectQuote(requestId, reason: _blankToNull(reason));
      state = state.copyWith(
        request: updated,
        clearQuote: true,
        isActing: false,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(isActing: false, actionError: failure.message);
    }
  }

  /// Fetches the server-computed refund before confirming a cancellation.
  ///
  /// The deposit policy is the backend's to decide, so the amount shown in the
  /// confirmation dialog is the same number that will be paid out. It runs with
  /// `isActing` locked so the cancel button cannot be double-tapped.
  Future<CancellationPreview> cancellationPreview() async {
    state = state.copyWith(isActing: true, clearActionError: true);
    try {
      final CancellationPreview preview = await ref
          .read(requestsRepositoryProvider)
          .cancellationPreview(requestId);
      state = state.copyWith(isActing: false);
      return preview;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isActing: false, actionError: failure.message);
      rethrow;
    }
  }

  /// Only called after the customer has seen the server-computed refund, so the
  /// cancellation policy is never guessed on the client.
  Future<void> cancel({String? reasonNote}) async {
    if (state.isActing) return;

    state = state.copyWith(isActing: true, clearActionError: true);
    try {
      final ServiceRequest updated = await ref
          .read(requestsRepositoryProvider)
          .cancel(requestId, reasonNote: _blankToNull(reasonNote));
      state = state.copyWith(request: updated, isActing: false);
    } on ApiFailure catch (failure) {
      state = state.copyWith(isActing: false, actionError: failure.message);
    }
  }

  void clearActionError() => state = state.copyWith(clearActionError: true);
}

String? _blankToNull(String? value) =>
    (value == null || value.trim().isEmpty) ? null : value;

final NotifierProviderFamily<
  RequestDetailController,
  RequestDetailState,
  String
>
requestDetailProvider =
    NotifierProvider.family<
      RequestDetailController,
      RequestDetailState,
      String
    >(RequestDetailController.new, name: 'requestDetail');
