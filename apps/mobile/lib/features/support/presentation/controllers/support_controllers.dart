import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/errors/failure.dart';
import '../../../../core/network/paginated.dart';
import '../../data/models/support_models.dart';
import '../../data/repositories/support_repository.dart';

enum ConversationsStatus { initial, loading, ready, failed }

class ConversationsState extends Equatable {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.conversations = const <Conversation>[],
    this.errorMessage,
  });

  final ConversationsStatus status;
  final List<Conversation> conversations;
  final String? errorMessage;

  @override
  List<Object?> get props => <Object?>[status, conversations, errorMessage];
}

/// The list of support threads for the Support tab.
class ConversationsController extends Notifier<ConversationsState> {
  @override
  ConversationsState build() => const ConversationsState();

  Future<void> load() async {
    state = ConversationsState(
      status: ConversationsStatus.loading,
      conversations: state.conversations,
    );
    try {
      final List<Conversation> conversations = await ref
          .read(supportRepositoryProvider)
          .conversations();
      state = ConversationsState(
        status: ConversationsStatus.ready,
        conversations: conversations,
      );
    } on ApiFailure catch (failure) {
      state = ConversationsState(
        status: ConversationsStatus.failed,
        conversations: state.conversations,
        errorMessage: failure.message,
      );
    }
  }
}

final NotifierProvider<ConversationsController, ConversationsState>
conversationsProvider =
    NotifierProvider<ConversationsController, ConversationsState>(
      ConversationsController.new,
      name: 'conversations',
    );

/// Total unread across all threads, for the badge on the Support tab.
final Provider<int> unreadConversationsProvider = Provider<int>((Ref ref) {
  return ref
      .watch(conversationsProvider)
      .conversations
      .fold(0, (int sum, Conversation c) => sum + c.unreadCount);
});

enum MessagesStatus { initial, loading, ready, failed }

class MessagesState extends Equatable {
  const MessagesState({
    this.status = MessagesStatus.initial,
    this.messages = const <SupportMessage>[],
    this.errorMessage,
    this.isSending = false,
  });

  final MessagesStatus status;
  final List<SupportMessage> messages;
  final String? errorMessage;
  final bool isSending;

  MessagesState copyWith({
    MessagesStatus? status,
    List<SupportMessage>? messages,
    String? errorMessage,
    bool? isSending,
    bool clearError = false,
  }) {
    return MessagesState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSending: isSending ?? this.isSending,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    messages,
    errorMessage,
    isSending,
  ];
}

/// Messages inside one thread.
///
/// Opening a thread marks it read, which the backend does as a side effect of
/// the message fetch; the badge therefore clears without a second request.
class MessagesController extends Notifier<MessagesState> {
  MessagesController(this.conversationId);

  final String conversationId;

  @override
  MessagesState build() {
    Future<void>.microtask(load);
    return const MessagesState(status: MessagesStatus.loading);
  }

  Future<void> load() async {
    try {
      final List<SupportMessage> messages = await ref
          .read(supportRepositoryProvider)
          .messages(conversationId);
      state = MessagesState(status: MessagesStatus.ready, messages: messages);
    } on ApiFailure catch (failure) {
      state = MessagesState(
        status: MessagesStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  /// Sends and then refetches rather than appending locally.
  ///
  /// The server stamps `sent_at` and assigns the id, and staff can reply in
  /// between; refetching means the thread is always exactly what the server
  /// holds instead of an optimistic guess that could disagree.
  Future<void> send(String body) async {
    final String trimmed = body.trim();
    if (trimmed.isEmpty || state.isSending) return;

    state = state.copyWith(isSending: true, clearError: true);
    try {
      await ref
          .read(supportRepositoryProvider)
          .sendMessage(conversationId, body: trimmed);
      final List<SupportMessage> messages = await ref
          .read(supportRepositoryProvider)
          .messages(conversationId);
      state = MessagesState(status: MessagesStatus.ready, messages: messages);
    } on ApiFailure catch (failure) {
      state = state.copyWith(isSending: false, errorMessage: failure.message);
    }
  }
}

final NotifierProviderFamily<MessagesController, MessagesState, String>
messagesProvider =
    NotifierProvider.family<MessagesController, MessagesState, String>(
      MessagesController.new,
      name: 'messages',
    );

enum ComplaintsStatus { initial, loading, ready, failed }

class ComplaintsState extends Equatable {
  const ComplaintsState({
    this.status = ComplaintsStatus.initial,
    this.complaints = const <Complaint>[],
    this.reasons = const <String>[],
    this.errorMessage,
    this.isSubmitting = false,
  });

  final ComplaintsStatus status;
  final List<Complaint> complaints;
  final List<String> reasons;
  final String? errorMessage;
  final bool isSubmitting;

  ComplaintsState copyWith({
    ComplaintsStatus? status,
    List<Complaint>? complaints,
    List<String>? reasons,
    String? errorMessage,
    bool? isSubmitting,
    bool clearError = false,
  }) {
    return ComplaintsState(
      status: status ?? this.status,
      complaints: complaints ?? this.complaints,
      reasons: reasons ?? this.reasons,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    complaints,
    reasons,
    errorMessage,
    isSubmitting,
  ];
}

/// Complaints plus the reason dropdown values.
///
/// The reasons are fetched with the list because the complaint form needs them
/// and the backend owns the enum.
class ComplaintsController extends Notifier<ComplaintsState> {
  @override
  ComplaintsState build() => const ComplaintsState();

  Future<void> load() async {
    state = state.copyWith(status: ComplaintsStatus.loading, clearError: true);
    try {
      // Independent reads, so they run together rather than in sequence.
      final results = await Future.wait<Object?>(<Future<Object?>>[
        ref.read(supportRepositoryProvider).complaints(),
        ref.read(supportRepositoryProvider).complaintReasons(),
      ]);

      state = ComplaintsState(
        status: ComplaintsStatus.ready,
        complaints: (results[0] as Paginated<Complaint>).items,
        reasons: results[1]! as List<String>,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: ComplaintsStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  Future<Complaint?> submit({
    String? requestId,
    required String reason,
    required String description,
  }) async {
    if (state.isSubmitting) return null;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final Complaint complaint = await ref
          .read(supportRepositoryProvider)
          .createComplaint(
            requestId: requestId,
            reason: reason,
            description: description,
          );
      state = state.copyWith(
        complaints: <Complaint>[complaint, ...state.complaints],
        isSubmitting: false,
      );
      return complaint;
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: failure.message,
      );
      return null;
    }
  }
}

final NotifierProvider<ComplaintsController, ComplaintsState>
complaintsProvider = NotifierProvider<ComplaintsController, ComplaintsState>(
  ComplaintsController.new,
  name: 'complaints',
);
