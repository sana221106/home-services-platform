import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/core/network/paginated.dart';
import 'package:home_services_app/features/support/data/models/support_models.dart';
import 'package:home_services_app/features/support/data/repositories/support_repository.dart';
import 'package:home_services_app/features/support/presentation/controllers/support_controllers.dart';

void main() {
  group('ConversationsController', () {
    test('load fills the threads and clears any earlier error', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(conversationsProvider.notifier).load();

      final ConversationsState state = container.read(conversationsProvider);
      expect(state.status, ConversationsStatus.ready);
      expect(state.conversations, hasLength(1));
      expect(state.errorMessage, isNull);
    });

    test('a failure keeps the threads already on screen', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(conversationsProvider.notifier).load();
      repository.conversationsError = const ApiFailure(
        code: 'NETWORK',
        message: 'Support unavailable',
      );
      await container.read(conversationsProvider.notifier).load();

      final ConversationsState state = container.read(conversationsProvider);
      // Losing the list on a failed refresh would throw away what the customer
      // was already reading.
      expect(state.status, ConversationsStatus.failed);
      expect(state.conversations, hasLength(1));
      expect(state.errorMessage, 'Support unavailable');
    });

    test('the unread badge sums unread across threads', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository()
        ..conversationsValue = <Conversation>[
          _conversation(unreadCount: 2),
          _conversation(unreadCount: 3),
        ];
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(conversationsProvider.notifier).load();

      expect(container.read(unreadConversationsProvider), 5);
    });
  });

  group('MessagesController', () {
    test('build fetches the thread so it opens ready', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      final MessagesState state = container.read(messagesProvider('conv-1'));
      expect(state.status, MessagesStatus.loading);

      await container.read(messagesProvider('conv-1').notifier).load();

      expect(container.read(messagesProvider('conv-1')).messages, hasLength(1));
    });

    test('send posts the body then refetches instead of appending', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(messagesProvider('conv-1').notifier).send('  hi  ');

      // Trimmed, and the refetch is what makes the thread authoritative.
      expect(repository.sentBodies, <String>['hi']);
      expect(repository.messageReads, 2);
    });

    test('a blank body is never sent', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(messagesProvider('conv-1').notifier).send('   ');

      expect(repository.sentBodies, isEmpty);
    });

    test(
      'a failed send surfaces the message and clears the sending flag',
      () async {
        final _FakeSupportRepository repository = _FakeSupportRepository()
          ..sendError = const ApiFailure(
            code: 'NETWORK',
            message: 'Send failed',
          );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);

        await container.read(messagesProvider('conv-1').notifier).send('hi');

        final MessagesState state = container.read(messagesProvider('conv-1'));
        expect(state.errorMessage, 'Send failed');
        expect(state.isSending, isFalse);
      },
    );
  });

  group('ComplaintsController', () {
    test(
      'load brings the complaints and the server reason codes together',
      () async {
        final _FakeSupportRepository repository = _FakeSupportRepository();
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);

        await container.read(complaintsProvider.notifier).load();

        final ComplaintsState state = container.read(complaintsProvider);
        expect(state.status, ComplaintsStatus.ready);
        expect(state.complaints, hasLength(1));
        expect(state.reasons, contains('WORK_NOT_DONE'));
      },
    );

    test('a failed load keeps the complaints already on screen', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(complaintsProvider.notifier).load();
      repository.complaintsError = const ApiFailure(
        code: 'NETWORK',
        message: 'Complaints unavailable',
      );
      await container.read(complaintsProvider.notifier).load();

      final ComplaintsState state = container.read(complaintsProvider);
      expect(state.status, ComplaintsStatus.failed);
      expect(state.complaints, hasLength(1));
      expect(state.errorMessage, 'Complaints unavailable');
    });

    test('submit puts the new complaint first and returns it', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(complaintsProvider.notifier).load();
      final Complaint? created = await container
          .read(complaintsProvider.notifier)
          .submit(reason: 'DAMAGE', description: 'Wall cracked');

      expect(created, isNotNull);
      expect(created!.referenceCode, 'CMP-NEW');
      expect(
        container.read(complaintsProvider).complaints.first.referenceCode,
        'CMP-NEW',
      );
    });

    test('a rejected submit returns null and keeps the message', () async {
      final _FakeSupportRepository repository = _FakeSupportRepository()
        ..createError = const ApiFailure(
          code: 'VALIDATION',
          message: 'Too short',
        );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      final Complaint? created = await container
          .read(complaintsProvider.notifier)
          .submit(reason: 'DAMAGE', description: 'short');

      expect(created, isNull);
      final ComplaintsState state = container.read(complaintsProvider);
      expect(state.errorMessage, 'Too short');
      expect(state.isSubmitting, isFalse);
      expect(state.complaints, isEmpty);
    });
  });
}

Conversation _conversation({int unreadCount = 0}) {
  return Conversation(
    id: 'conv-1',
    subject: 'Leaking tap',
    isOpen: true,
    unreadCount: unreadCount,
    lastMessageAt: DateTime(2026, 1, 1),
  );
}

Complaint _complaint() {
  return Complaint(
    id: 'cmp-1',
    referenceCode: 'CMP-1',
    reason: 'POOR_QUALITY',
    description: 'Not clean',
    status: 'OPEN',
    createdAt: DateTime(2026, 1, 1),
  );
}

ProviderContainer _container(_FakeSupportRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      supportRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakeSupportRepository implements SupportRepository {
  List<Conversation> conversationsValue = <Conversation>[_conversation()];
  ApiFailure? conversationsError;

  List<SupportMessage> messagesValue = <SupportMessage>[
    const SupportMessage(
      id: 'msg-1',
      body: 'How can I help?',
      senderType: 'support',
      sentAt: null,
    ),
  ];
  ApiFailure? sendError;
  ApiFailure? messagesError;

  List<String> reasonsValue = <String>['WORK_NOT_DONE', 'DAMAGE'];
  Paginated<Complaint> complaintsValue = _page(<Complaint>[_complaint()]);
  ApiFailure? complaintsError;
  ApiFailure? createError;

  final List<String> sentBodies = <String>[];
  int messageReads = 0;

  @override
  Future<List<Conversation>> conversations() async {
    final ApiFailure? failure = conversationsError;
    if (failure != null) throw failure;
    return conversationsValue;
  }

  @override
  Future<List<SupportMessage>> messages(String conversationId) async {
    messageReads++;
    final ApiFailure? failure = messagesError;
    if (failure != null) throw failure;
    return messagesValue;
  }

  @override
  Future<void> sendMessage(
    String conversationId, {
    required String body,
  }) async {
    sentBodies.add(body);
    final ApiFailure? failure = sendError;
    if (failure != null) throw failure;
  }

  @override
  Future<Paginated<Complaint>> complaints({
    int page = 1,
    int perPage = 20,
  }) async {
    final ApiFailure? failure = complaintsError;
    if (failure != null) throw failure;
    return complaintsValue;
  }

  @override
  Future<List<String>> complaintReasons() async => reasonsValue;

  @override
  Future<Complaint> createComplaint({
    String? requestId,
    required String reason,
    required String description,
    String? idempotencyKey,
  }) async {
    final ApiFailure? failure = createError;
    if (failure != null) throw failure;
    return Complaint(
      id: 'cmp-new',
      referenceCode: 'CMP-NEW',
      reason: reason,
      description: description,
      status: 'OPEN',
      createdAt: DateTime(2026, 1, 2),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Paginated<Complaint> _page(List<Complaint> items) {
  return Paginated<Complaint>(
    items: items,
    meta: const PageMeta(
      page: 1,
      perPage: 20,
      total: 1,
      totalPages: 1,
      hasNext: false,
      hasPrevious: false,
    ),
  );
}
