import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/core/network/paginated.dart';
import 'package:home_services_app/features/orders/data/models/order_models.dart';
import 'package:home_services_app/features/orders/data/repositories/orders_repository.dart';
import 'package:home_services_app/features/orders/presentation/controllers/orders_controller.dart';

void main() {
  group('OrdersController', () {
    test('load fills the first page', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();

      final OrdersState state = container.read(ordersProvider);
      expect(state.status, OrdersStatus.ready);
      expect(state.orders, hasLength(1));
      expect(repository.requestedPages, <int>[1]);
    });

    test('loadMore appends and advances the page', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository()
        ..hasNext = true;
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();
      await container.read(ordersProvider.notifier).loadMore();

      final OrdersState state = container.read(ordersProvider);
      expect(state.orders, hasLength(2));
      expect(state.hasNext, isFalse);
      expect(repository.requestedPages, <int>[1, 2]);
    });

    test('loadMore does nothing on the last page', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();
      await container.read(ordersProvider.notifier).loadMore();

      expect(repository.requestedPages, <int>[1]);
    });

    test('a failed first load is fatal and offers the message', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository()
        ..listError = const ApiFailure(
          code: 'NETWORK',
          message: 'Orders unavailable',
        );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();

      final OrdersState state = container.read(ordersProvider);
      expect(state.status, OrdersStatus.failed);
      expect(state.isFatalError, isTrue);
      expect(state.errorMessage, 'Orders unavailable');
    });

    test('a failed refresh keeps the rows already on screen', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();
      repository.listError = const ApiFailure(
        code: 'NETWORK',
        message: 'Offline',
      );
      await container.read(ordersProvider.notifier).refresh();

      final OrdersState state = container.read(ordersProvider);
      // Blanking the list on a flaky connection would be worse than showing
      // slightly stale rows.
      expect(state.orders, hasLength(1));
      expect(state.isFatalError, isFalse);
    });

    test('a failed page append keeps the rows already loaded', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository()
        ..hasNext = true
        ..failOnPageTwo = true;
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(ordersProvider.notifier).load();
      await container.read(ordersProvider.notifier).loadMore();

      final OrdersState state = container.read(ordersProvider);
      expect(state.orders, hasLength(1));
      // The spinner must stop, otherwise the list hangs on a dead loader.
      expect(state.isLoadingMore, isFalse);
    });

    test('hasUnreadOrderUpdatesProvider reflects the rows', () async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository(
        hasUnreadUpdates: true,
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      expect(container.read(hasUnreadOrderUpdatesProvider), isFalse);
      await container.read(ordersProvider.notifier).load();
      expect(container.read(hasUnreadOrderUpdatesProvider), isTrue);
    });
  });
}

ProviderContainer _container(_FakeOrdersRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      ordersRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakeOrdersRepository implements OrdersRepository {
  _FakeOrdersRepository({bool hasUnreadUpdates = false})
    : _hasUnreadUpdates = hasUnreadUpdates;

  final bool _hasUnreadUpdates;
  bool hasNext = false;
  bool failOnPageTwo = false;
  ApiFailure? listError;

  final List<int> requestedPages = <int>[];

  @override
  Future<Paginated<OrderSummary>> list({int page = 1, int perPage = 20}) async {
    requestedPages.add(page);
    if (failOnPageTwo && page > 1) {
      throw const ApiFailure(code: 'NETWORK', message: 'Page failed');
    }
    final ApiFailure? failure = listError;
    if (failure != null) throw failure;

    // `hasNext` on the fixture means "there is a second page", so page two is
    // always the last one.
    final int totalPages = hasNext ? 2 : 1;
    return Paginated<OrderSummary>(
      items: <OrderSummary>[
        OrderSummary(
          requestId: 'req-$page',
          referenceCode: 'REF-$page',
          status: 'ON_THE_WAY',
          categoryNameAr: 'Plumbing',
          urgency: 'NORMAL',
          propertyLabel: 'Home',
          createdAt: DateTime(2026, 1, 1),
          hasUnreadUpdates: _hasUnreadUpdates,
        ),
      ],
      meta: PageMeta(
        page: page,
        perPage: perPage,
        total: totalPages,
        totalPages: totalPages,
        hasNext: page < totalPages,
        hasPrevious: page > 1,
      ),
    );
  }

  @override
  Future<OrderTracking> track(String requestId) async =>
      OrderTracking.fromJson(<String, dynamic>{'request_id': requestId});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
