import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/paginated.dart';
import '../models/support_models.dart';

/// Reads and writes support threads and complaints.
///
/// Four of these endpoints declare `response_model=list[...]` and return a bare
/// JSON array rather than the `{items, meta}` envelope, so they are read through
/// `getList` and not through `mapList('items')`.
class SupportRemoteDataSource {
  SupportRemoteDataSource(this._client);

  final ApiClient _client;

  Future<List<Conversation>> conversations() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.conversations,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(Conversation.fromJson)
        .toList(growable: false);
  }

  /// Opening a thread needs the opening message, so it is one request rather
  /// than a create followed by a send that could fail in between.
  Future<Conversation> startConversation({
    String? requestId,
    String? subject,
    required String firstMessage,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.conversations,
      data: <String, dynamic>{
        'request_id': ?requestId,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        'first_message': firstMessage,
      },
    );
    return Conversation.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<SupportMessage>> messages(String conversationId) async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.conversationMessages(conversationId),
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(SupportMessage.fromJson)
        .toList(growable: false);
  }

  Future<void> sendMessage(
    String conversationId, {
    required String body,
  }) async {
    await _client.post(
      ApiEndpoints.conversationMessages(conversationId),
      data: <String, dynamic>{'body': body},
    );
  }

  Future<void> markRead(String conversationId) async {
    await _client.post(ApiEndpoints.conversationRead(conversationId));
  }

  Future<Paginated<Complaint>> complaints({
    int page = 1,
    int perPage = 20,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.complaints,
      query: <String, dynamic>{'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(
      response.data ?? const <String, dynamic>{},
      Complaint.fromJson,
    );
  }

  /// The reason codes are served as a bare list, so the dropdown is populated
  /// from the server rather than from a hard-coded copy that could drift.
  Future<List<String>> complaintReasons() async {
    final Response<List<String>> response = await _client.getStringList(
      ApiEndpoints.complaintReasons,
    );
    return response.data ?? const <String>[];
  }

  Future<Complaint> createComplaint({
    String? requestId,
    required String reason,
    required String description,
    String? idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.complaints,
      data: <String, dynamic>{
        'request_id': ?requestId,
        'reason': reason,
        'description': description,
        'idempotency_key': ?idempotencyKey,
      },
    );
    return Complaint.fromJson(response.data ?? const <String, dynamic>{});
  }
}
