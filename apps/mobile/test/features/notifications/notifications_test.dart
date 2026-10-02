import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/notifications/data/models/notification_models.dart';
import 'package:home_services_app/features/notifications/data/repositories/notifications_repository.dart';
import 'package:home_services_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:home_services_app/features/notifications/presentation/pages/notifications_page.dart';

void main() {
  group('AppNotification', () {
    test('maps a known type code onto the enum', () {
      final AppNotification notification = AppNotification.fromJson(
        _json(type: 'QUOTE_READY', isRead: false),
      );

      expect(notification.type, NotificationType.quoteReady);
      expect(notification.isRead, isFalse);
      expect(notification.hasRequest, isTrue);
      expect(notification.title, 'Quote ready');
    });

    test('an unknown type still renders as a fallback', () {
      final AppNotification notification = AppNotification.fromJson(
        _json(type: 'SOMETHING_NEW'),
      );

      // A backend event the client has never seen must not throw.
      expect(notification.type, NotificationType.unknown);
      expect(notification.type.iconAsset, 'assets/icons/bell.svg');
    });

    test('an event without a request has nowhere to go', () {
      final AppNotification notification = AppNotification.fromJson(
        _json(type: 'RATING_REMINDER', requestId: null),
      );

      expect(notification.hasRequest, isFalse);
    });
  });

  group('NotificationsController', () {
    test(
      'load fills the list and reports more to come at the page size',
      () async {
        final _FakeNotificationsRepository repository =
            _FakeNotificationsRepository()
              ..listValue = List<AppNotification>.generate(
                50,
                (int i) => _notification(id: 'n-$i'),
              );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);

        await container.read(notificationsProvider.notifier).load();

        final NotificationsState state = container.read(notificationsProvider);
        expect(state.status, NotificationsStatus.ready);
        expect(state.hasMore, isTrue);
        expect(repository.lastLimit, 50);
      },
    );

    test('a short page means there is nothing more to load', () async {
      final ProviderContainer container = _container(
        _FakeNotificationsRepository()
          ..listValue = <AppNotification>[_notification()],
      );
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();

      expect(container.read(notificationsProvider).hasMore, isFalse);
    });

    test('loadMore widens the window instead of offsetting', () async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository()
            ..listValue = List<AppNotification>.generate(
              50,
              (int i) => _notification(id: 'n-$i'),
            );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();
      repository.listValue = List<AppNotification>.generate(
        60,
        (int i) => _notification(id: 'n-$i'),
      );
      await container.read(notificationsProvider.notifier).loadMore();

      expect(repository.lastLimit, 100);
      expect(
        container.read(notificationsProvider).notifications,
        hasLength(60),
      );
    });

    test('a failed load offers the message', () async {
      final ProviderContainer container = _container(
        _FakeNotificationsRepository()
          ..listError = const ApiFailure(
            code: 'NETWORK',
            message: 'Unavailable',
          ),
      );
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();

      expect(container.read(notificationsProvider).errorMessage, 'Unavailable');
    });

    test('markRead is optimistic', () async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();
      final AppNotification first = container
          .read(notificationsProvider)
          .notifications
          .first;
      await container.read(notificationsProvider.notifier).markRead(first);

      expect(
        container.read(notificationsProvider).notifications.first.isRead,
        isTrue,
      );
      expect(repository.markedIds, <String>[first.id]);
    });

    test('a failed markRead puts the row back', () async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository()
            ..markError = const ApiFailure(
              code: 'NETWORK',
              message: 'Unavailable',
            );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();
      final AppNotification first = container
          .read(notificationsProvider)
          .notifications
          .first;
      await container.read(notificationsProvider.notifier).markRead(first);

      // A row must not read as seen when the request never landed.
      expect(
        container.read(notificationsProvider).notifications.first.isRead,
        isFalse,
      );
    });

    test('a failed markAllRead restores the earlier rows', () async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository()
            ..markError = const ApiFailure(
              code: 'NETWORK',
              message: 'Unavailable',
            );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(notificationsProvider.notifier).load();
      await container.read(notificationsProvider.notifier).markAllRead();

      expect(
        container
            .read(notificationsProvider)
            .notifications
            .every((AppNotification n) => n.isRead),
        isFalse,
      );
    });
  });

  group('NotificationsPage', () {
    testWidgets('renders the inbox', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(_FakeNotificationsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Quote ready'), findsOneWidget);
      expect(find.text('Your quote is waiting'), findsOneWidget);
    });

    testWidgets('explains itself when there is nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeNotificationsRepository()..listValue = <AppNotification>[]),
      );
      await tester.pumpAndSettle();

      expect(find.text('No notifications'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository()
            ..listError = const ApiFailure(
              code: 'NETWORK',
              message: 'Unavailable',
            );
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);

      repository.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Quote ready'), findsOneWidget);
    });

    testWidgets('mark all read clears the action and the dots', (
      WidgetTester tester,
    ) async {
      final _FakeNotificationsRepository repository =
          _FakeNotificationsRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification-unread-dot')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notifications-mark-all-read')));
      await tester.pumpAndSettle();

      expect(repository.markAllCalled, isTrue);
      expect(find.byKey(const Key('notification-unread-dot')), findsNothing);
      expect(
        find.byKey(const Key('notifications-mark-all-read')),
        findsNothing,
      );
    });

    testWidgets('an unknown event type is labelled rather than dropped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeNotificationsRepository()
            ..listValue = <AppNotification>[
              AppNotification.fromJson(_json(type: 'FUTURE_EVENT')),
            ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New type'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _json({
  String type = 'QUOTE_READY',
  bool isRead = false,
  String? requestId = 'req-1',
}) {
  return <String, dynamic>{
    'id': 'notif-1',
    'request_id': requestId,
    'type': type,
    'title_ar': 'Quote ready',
    'body_ar': 'Your quote is waiting',
    'is_read': isRead,
    'created_at': '2026-01-02T10:00:00Z',
  };
}

AppNotification _notification({String id = 'notif-1', bool isRead = false}) {
  return AppNotification(
    id: id,
    requestId: null,
    type: NotificationType.quoteReady,
    title: 'Quote ready',
    body: 'Your quote is waiting',
    isRead: isRead,
    createdAt: DateTime(2026, 1, 2),
  );
}

Widget _wrap(_FakeNotificationsRepository repository) {
  return ProviderScope(
    overrides: <Override>[
      notificationsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const NotificationsPage(),
    ),
  );
}

ProviderContainer _container(_FakeNotificationsRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      notificationsRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakeNotificationsRepository implements NotificationsRepository {
  List<AppNotification> listValue = <AppNotification>[_notification()];
  ApiFailure? listError;
  ApiFailure? markError;
  int? lastLimit;
  List<String>? markedIds;
  bool markAllCalled = false;

  @override
  Future<List<AppNotification>> notifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    lastLimit = limit;
    final ApiFailure? failure = listError;
    if (failure != null) throw failure;
    return listValue;
  }

  @override
  Future<void> markRead({List<String>? ids}) async {
    final ApiFailure? failure = markError;
    if (failure != null) throw failure;
    if (ids == null) {
      markAllCalled = true;
    } else {
      markedIds = ids;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
