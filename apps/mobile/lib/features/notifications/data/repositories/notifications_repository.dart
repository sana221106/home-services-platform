import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../datasources/notifications_remote_data_source.dart';
import '../models/notification_models.dart';

/// Repository for the notification inbox.
class NotificationsRepository {
  NotificationsRepository(this._notifications, this._client);

  final NotificationsRemoteDataSource _notifications;
  final ApiClient _client;

  Future<List<AppNotification>> notifications({
    int limit = 50,
    bool unreadOnly = false,
  }) => _guard(
    () => _notifications.notifications(limit: limit, unreadOnly: unreadOnly),
  );

  /// The endpoint only acknowledges, it does not return the updated rows, so
  /// the caller keeps its local list and the next load reconciles.
  Future<void> markRead({List<String>? ids}) =>
      _guard(() => _notifications.markRead(ids: ids));

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

final Provider<NotificationsRemoteDataSource>
notificationsRemoteDataSourceProvider = Provider<NotificationsRemoteDataSource>(
  (Ref ref) => NotificationsRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'notificationsRemoteDataSource',
);

final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>(
      (Ref ref) => NotificationsRepository(
        ref.watch(notificationsRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'notificationsRepository',
    );
