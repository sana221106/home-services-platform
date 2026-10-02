import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../data/models/notification_models.dart';
import '../../data/repositories/notifications_repository.dart';

enum NotificationsStatus { initial, loading, ready, failed }

class NotificationsState extends Equatable {
  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.notifications = const <AppNotification>[],
    this.errorMessage,
    this.limit = _pageSize,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isMarkingAll = false,
  });

  static const int _pageSize = 50;
  static const int _pageStep = 50;

  final NotificationsStatus status;
  final List<AppNotification> notifications;
  final String? errorMessage;

  /// The list endpoint takes a maximum row count rather than a page number, so
  /// the current window is tracked and grown instead of offset.
  final int limit;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isMarkingAll;

  bool get isEmpty => notifications.isEmpty;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? notifications,
    String? errorMessage,
    int? limit,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isMarkingAll,
    bool clearError = false,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      notifications: notifications ?? this.notifications,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMarkingAll: isMarkingAll ?? this.isMarkingAll,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    notifications,
    errorMessage,
    limit,
    hasMore,
    isLoadingMore,
    isMarkingAll,
  ];
}

/// The notification inbox.
///
/// Reads are optimistic: a tap marks the row read locally and the request
/// follows. If it fails the row is put back and the customer is told, rather
/// than leaving a row that looks read but is not.
class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() => const NotificationsState();

  Future<void> load() async {
    state = state.copyWith(
      status: NotificationsStatus.loading,
      clearError: true,
    );
    try {
      final List<AppNotification> rows = await ref
          .read(notificationsRepositoryProvider)
          .notifications(limit: NotificationsState._pageSize);
      state = state.copyWith(
        status: NotificationsStatus.ready,
        notifications: rows,
        limit: NotificationsState._pageSize,
        hasMore: rows.length >= NotificationsState._pageSize,
        clearError: true,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: NotificationsStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);
    final int nextLimit = state.limit + NotificationsState._pageStep;
    try {
      final List<AppNotification> rows = await ref
          .read(notificationsRepositoryProvider)
          .notifications(limit: nextLimit);
      state = state.copyWith(
        status: NotificationsStatus.ready,
        notifications: rows,
        limit: nextLimit,
        hasMore: rows.length >= nextLimit,
        isLoadingMore: false,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) return;
    _setRead(notification.id, true);
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .markRead(ids: <String>[notification.id]);
    } on ApiFailure catch (failure) {
      _setRead(notification.id, false);
      state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> markAllRead() async {
    if (state.isMarkingAll) return;
    final List<AppNotification> before = state.notifications;
    if (before.every((AppNotification n) => n.isRead)) return;

    state = state.copyWith(
      isMarkingAll: true,
      clearError: true,
      notifications: <AppNotification>[
        for (final AppNotification n in before) n.copyWith(isRead: true),
      ],
    );
    try {
      await ref.read(notificationsRepositoryProvider).markRead();
      state = state.copyWith(isMarkingAll: false);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isMarkingAll: false,
        notifications: before,
        errorMessage: failure.message,
      );
    }
  }

  void _setRead(String id, bool read) {
    state = state.copyWith(
      notifications: <AppNotification>[
        for (final AppNotification n in state.notifications)
          if (n.id == id) n.copyWith(isRead: read) else n,
      ],
    );
  }
}

final NotifierProvider<NotificationsController, NotificationsState>
notificationsProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
      NotificationsController.new,
      name: 'notifications',
    );
