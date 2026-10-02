import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/notification_models.dart';

/// Reads the customer's notifications and unread totals.
///
/// The list endpoint answers with a bare JSON array and takes a `limit` instead
/// of page offsets, so "load more" is a larger limit rather than a later page.
class NotificationsRemoteDataSource {
  NotificationsRemoteDataSource(this._client);

  final ApiClient _client;

  Future<List<AppNotification>> notifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.notifications,
      query: <String, dynamic>{
        'limit': limit,
        if (unreadOnly) 'unread_only': true,
      },
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(AppNotification.fromJson)
        .toList(growable: false);
  }

  /// Passing null ids marks every unread notification read, which is what the
  /// "mark all read" action wants.
  Future<void> markRead({List<String>? ids}) async {
    await _client.post(
      ApiEndpoints.notificationsRead,
      data: <String, dynamic>{'ids': ?ids},
    );
  }
}
