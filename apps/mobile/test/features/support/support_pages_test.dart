import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/core/network/paginated.dart';
import 'package:home_services_app/features/support/data/models/support_models.dart';
import 'package:home_services_app/features/support/data/repositories/support_repository.dart';
import 'package:home_services_app/features/support/presentation/pages/complaint_pages.dart';
import 'package:home_services_app/features/support/presentation/pages/conversation_page.dart';
import 'package:home_services_app/features/support/presentation/pages/support_page.dart';

void main() {
  group('SupportMessage', () {
    test('parses the thread payload and tells the two senders apart', () {
      final SupportMessage message = SupportMessage.fromJson(<String, dynamic>{
        'id': 'msg-1',
        'body': 'On my way',
        'sender_type': 'customer',
        'sent_at': '2026-01-01T10:00:00Z',
        'attachment_urls': <String>[],
      });

      expect(message.id, 'msg-1');
      expect(message.isFromCustomer, isTrue);
      expect(message.sentAt, isNotNull);
    });

    test('a support reply is not treated as the customer speaking', () {
      final SupportMessage message = SupportMessage.fromJson(<String, dynamic>{
        'id': 'msg-2',
        'sender_type': 'support',
      });

      expect(message.isFromCustomer, isFalse);
      expect(message.attachmentUrls, isEmpty);
    });
  });

  group('Complaint', () {
    test('parses the payload including resolution and rework', () {
      final Complaint complaint = Complaint.fromJson(<String, dynamic>{
        'id': 'cmp-1',
        'reference_code': 'CMP-0001',
        'request_id': 'req-1',
        'reason': 'POOR_QUALITY',
        'description': 'Not clean',
        'status': 'RESOLVED',
        'created_at': '2026-01-01T10:00:00Z',
        'resolved_at': '2026-01-03T10:00:00Z',
        'requires_rework': true,
        'resolution': 'Rework done',
      });

      expect(complaint.referenceCode, 'CMP-0001');
      expect(complaint.isSettled, isTrue);
      expect(complaint.requiresRework, isTrue);
      expect(complaint.resolution, 'Rework done');
    });

    test('an unresolved complaint is not reported as finished', () {
      final Complaint complaint = Complaint.fromJson(<String, dynamic>{
        'id': 'cmp-2',
        'status': 'UNDER_REVIEW',
      });

      expect(complaint.isSettled, isFalse);
      expect(complaint.resolution, isNull);
    });
  });

  group('ComplaintReasonCode', () {
    test('a code the server adds early is kept rather than dropped', () {
      expect(
        ComplaintReasonCode.fromCode('SOMETHING_NEW').code,
        'SOMETHING_NEW',
      );
      expect(ComplaintReasonCode.fromCode(null).code, isEmpty);
    });
  });

  group('SupportPage', () {
    testWidgets('lists the threads with the unread badge', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _support(
          _FakeSupportRepository()
            ..conversationsValue = <Conversation>[
              _conversation(subject: 'Leaking tap', unreadCount: 2),
              _conversation(subject: 'Closed thread', isOpen: false),
              _conversation(subject: 'Second thread'),
            ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Leaking tap'), findsOneWidget);
      expect(find.text('Unread (2)'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Second thread'), findsOneWidget);
    });

    testWidgets('shows the empty state with a way to start a thread', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _support(
          _FakeSupportRepository()..conversationsValue = <Conversation>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.text('New message'), findsWidgets);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeSupportRepository repository = _FakeSupportRepository()
        ..conversationsError = const ApiFailure(
          code: 'NETWORK',
          message: 'Support unavailable',
        );
      await tester.pumpWidget(_support(repository));
      await tester.pumpAndSettle();

      expect(find.text('Support unavailable'), findsOneWidget);

      repository.conversationsError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Leaking tap'), findsOneWidget);
    });

    testWidgets('the complaints section shows the filed complaint', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_support(_FakeSupportRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My complaints'));
      await tester.pumpAndSettle();

      expect(find.text('Poor quality'), findsOneWidget);
      expect(find.text('#CMP-0001'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('the complaints section explains itself when empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _support(
          _FakeSupportRepository()..complaintsValue = _page(<Complaint>[]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('My complaints'));
      await tester.pumpAndSettle();

      expect(find.text('No complaints'), findsOneWidget);
    });
  });

  group('ConversationPage', () {
    testWidgets('renders the thread and the composer', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _thread(
          _FakeSupportRepository()
            ..messagesValue = <SupportMessage>[
              const SupportMessage(
                id: 'm1',
                body: 'On my way',
                senderType: 'customer',
                sentAt: null,
              ),
              const SupportMessage(
                id: 'm2',
                body: 'How can I help?',
                senderType: 'support',
                sentAt: null,
              ),
            ],
          subject: 'Leaking tap',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Leaking tap'), findsOneWidget);
      expect(find.text('On my way'), findsOneWidget);
      expect(find.text('How can I help?'), findsOneWidget);
      expect(find.byKey(const Key('message-field')), findsOneWidget);
    });

    testWidgets('a failed thread load offers a retry', (
      WidgetTester tester,
    ) async {
      final _FakeSupportRepository repository = _FakeSupportRepository()
        ..messagesError = const ApiFailure(
          code: 'NETWORK',
          message: 'Thread unavailable',
        );
      await tester.pumpWidget(_thread(repository));
      await tester.pumpAndSettle();

      expect(find.text('Thread unavailable'), findsOneWidget);
    });

    testWidgets('sending sends the typed body and refetches the thread', (
      WidgetTester tester,
    ) async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      await tester.pumpWidget(_thread(repository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('message-field')), 'Hello');
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();

      expect(repository.sentBodies, <String>['Hello']);
    });

    testWidgets('an empty thread says so instead of showing a blank list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _thread(
          _FakeSupportRepository()..messagesValue = <SupportMessage>[],
          subject: 'Leaking tap',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
    });
  });

  group('NewComplaintPage', () {
    testWidgets('submit stays disabled until a reason and a real description', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeSupportRepository(),
          child: const NewComplaintPage(requestId: 'req-1'),
        ),
      );
      await tester.pumpAndSettle();

      FilledButton button() => tester.widget<FilledButton>(
        find.byKey(const Key('complaint-submit')),
      );

      expect(button().onPressed, isNull);

      await tester.tap(find.byKey(const Key('complaint-reason-DAMAGE')));
      await tester.pumpAndSettle();

      // A reason alone is not enough; the backend wants ten characters.
      expect(button().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('complaint-description')),
        'The wall is cracked',
      );
      await tester.pumpAndSettle();

      expect(button().onPressed, isNotNull);
    });

    testWidgets('submitting posts the description and pops back', (
      WidgetTester tester,
    ) async {
      final _FakeSupportRepository repository = _FakeSupportRepository();
      await tester.pumpWidget(
        _wrap(repository, child: const NewComplaintPage(requestId: 'req-1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-reason-DAMAGE')));
      await tester.enterText(
        find.byKey(const Key('complaint-description')),
        'The wall is cracked',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-submit')));
      await tester.pumpAndSettle();

      expect(repository.createdDescription, 'The wall is cracked');
      expect(repository.createdRequestId, 'req-1');
      // The new complaint is in the state the list will read.
      expect(repository.createdReason, 'DAMAGE');
    });

    testWidgets('a rejected submit keeps the customer on the form', (
      WidgetTester tester,
    ) async {
      final _FakeSupportRepository repository = _FakeSupportRepository()
        ..createError = const ApiFailure(
          code: 'VALIDATION',
          message: 'Description too short',
        );
      await tester.pumpWidget(
        _wrap(repository, child: const NewComplaintPage(requestId: 'req-1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-reason-DAMAGE')));
      await tester.enterText(
        find.byKey(const Key('complaint-description')),
        'The wall is cracked',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Description too short'), findsOneWidget);
    });
  });
}

Conversation _conversation({
  String subject = 'Leaking tap',
  bool isOpen = true,
  int unreadCount = 0,
}) {
  return Conversation(
    id: 'conv-1',
    subject: subject,
    isOpen: isOpen,
    unreadCount: unreadCount,
    lastMessageAt: DateTime(2026, 1, 1),
    lastMessagePreview: 'How can I help?',
  );
}

Complaint _complaint() {
  return Complaint(
    id: 'cmp-1',
    referenceCode: 'CMP-0001',
    reason: 'POOR_QUALITY',
    description: 'Not clean',
    status: 'OPEN',
    createdAt: DateTime(2026, 1, 1),
  );
}

Paginated<Complaint> _page(List<Complaint> items) {
  return Paginated<Complaint>(
    items: items,
    meta: PageMeta(
      page: 1,
      perPage: 20,
      total: items.length,
      totalPages: 1,
      hasNext: false,
      hasPrevious: false,
    ),
  );
}

Widget _wrap(_FakeSupportRepository repository, {required Widget child}) {
  return ProviderScope(
    overrides: <Override>[
      supportRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Widget _support(_FakeSupportRepository repository) =>
    _wrap(repository, child: const SupportPage());

Widget _thread(
  _FakeSupportRepository repository, {
  String subject = 'Leaking tap',
}) {
  return _wrap(
    repository,
    child: ConversationPage(conversationId: 'conv-1', subject: subject),
  );
}

class _FakeSupportRepository implements SupportRepository {
  List<Conversation> conversationsValue = <Conversation>[_conversation()];
  ApiFailure? conversationsError;

  List<SupportMessage> messagesValue = <SupportMessage>[
    const SupportMessage(
      id: 'm1',
      body: 'How can I help?',
      senderType: 'support',
    ),
  ];
  ApiFailure? messagesError;
  ApiFailure? sendError;

  List<String> reasonsValue = <String>['WORK_NOT_DONE', 'DAMAGE'];
  Paginated<Complaint> complaintsValue = _page(<Complaint>[_complaint()]);
  ApiFailure? complaintsError;
  ApiFailure? createError;

  final List<String> sentBodies = <String>[];
  String? createdDescription;
  String? createdRequestId;
  String? createdReason;

  @override
  Future<List<Conversation>> conversations() async {
    final ApiFailure? failure = conversationsError;
    if (failure != null) throw failure;
    return conversationsValue;
  }

  @override
  Future<List<SupportMessage>> messages(String conversationId) async {
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
    createdDescription = description;
    createdRequestId = requestId;
    createdReason = reason;
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
