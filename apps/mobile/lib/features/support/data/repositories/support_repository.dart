import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/paginated.dart';
import '../datasources/support_remote_data_source.dart';
import '../models/support_models.dart';

/// Repository for support threads and complaints.
class SupportRepository {
  SupportRepository(this._support, this._client);

  final SupportRemoteDataSource _support;
  final ApiClient _client;

  Future<List<Conversation>> conversations() => _guard(_support.conversations);

  Future<Conversation> startConversation({
    String? requestId,
    String? subject,
    required String firstMessage,
  }) => _guard(
    () => _support.startConversation(
      requestId: requestId,
      subject: subject,
      firstMessage: firstMessage,
    ),
  );

  Future<List<SupportMessage>> messages(String conversationId) =>
      _guard(() => _support.messages(conversationId));

  Future<void> sendMessage(String conversationId, {required String body}) =>
      _guard(() => _support.sendMessage(conversationId, body: body));

  Future<void> markRead(String conversationId) =>
      _guard(() => _support.markRead(conversationId));

  Future<Paginated<Complaint>> complaints({int page = 1, int perPage = 20}) =>
      _guard(() => _support.complaints(page: page, perPage: perPage));

  Future<List<String>> complaintReasons() => _guard(_support.complaintReasons);

  Future<Complaint> createComplaint({
    String? requestId,
    required String reason,
    required String description,
    String? idempotencyKey,
  }) => _guard(
    () => _support.createComplaint(
      requestId: requestId,
      reason: reason,
      description: description,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiFailure {
      rethrow;
    } on DioException catch (error) {
      throw _client.translate(error);
    } catch (error) {
      throw ApiFailure(
        code: 'UNEXPECTED',
        message: 'حدث خطأ غير متوقع.',
        details: <String, String>{'reason': error.runtimeType.toString()},
      );
    }
  }
}

final Provider<SupportRemoteDataSource> supportRemoteDataSourceProvider =
    Provider<SupportRemoteDataSource>(
      (Ref ref) => SupportRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'supportRemoteDataSource',
    );

final Provider<SupportRepository> supportRepositoryProvider =
    Provider<SupportRepository>(
      (Ref ref) => SupportRepository(
        ref.watch(supportRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'supportRepository',
    );
