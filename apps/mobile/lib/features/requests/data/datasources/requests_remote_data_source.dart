import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/network/paginated.dart';
import '../models/request_models.dart';

/// Reads the service catalogue for the "Select Service" step.
///
/// `GET /catalogue` returns categories with their problem types already nested,
/// so the wizard needs one round trip rather than N+1. The per-category
/// endpoints stay available for the case where the customer changes their mind
/// after the catalogue load.
class CatalogueRemoteDataSource {
  CatalogueRemoteDataSource(this._client);

  final ApiClient _client;

  /// These three endpoints all declare `response_model=list[...]` on the
  /// backend, so they return a bare JSON array rather than the `{items: [...]}`
  /// envelope used by the paginated routes. Reading them through `get` and
  /// `mapList('items')` would fail on every call.
  ///
  /// The whole catalogue in one call, problems included.
  Future<List<ServiceCategory>> catalogue() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.catalogue,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(ServiceCategory.fromJson)
        .toList(growable: false);
  }

  Future<List<ServiceCategory>> categories() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.services,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(ServiceCategory.fromJson)
        .toList(growable: false);
  }

  Future<List<ProblemType>> problems(String categoryId) async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.serviceProblems(categoryId),
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(ProblemType.fromJson)
        .toList(growable: false);
  }
}

/// Creates and acts on service requests.
///
/// Note the create/submit split: `POST /requests` only produces a `DRAFT`, and
/// `POST /requests/{id}/submit` rejects with 400 unless at least one photo was
/// uploaded first. [RequestsRemoteDataSource.createDraft] and
/// [uploadMedia] and [submit] together are the wizard's final action, so they
/// live side by side to keep that ordering visible.
class RequestsRemoteDataSource {
  RequestsRemoteDataSource(this._client);

  final ApiClient _client;

  Future<Paginated<ServiceRequest>> list({
    int page = 1,
    int perPage = 20,
    List<String> statuses = const <String>[],
  }) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.requests,
      query: <String, dynamic>{
        'page': page,
        'per_page': perPage,
        // Repeated query param: ?status=A&status=B, not a comma-joined list.
        if (statuses.isNotEmpty) 'status': statuses,
      },
    );
    return Paginated<ServiceRequest>.fromJson(
      response.data ?? const <String, dynamic>{},
      ServiceRequest.fromJson,
    );
  }

  Future<ServiceRequest> detail(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.request(requestId),
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }

  /// Creates the draft. `idempotency_key` is matched against `reference_code`,
  /// so a retry returns the original request instead of creating a duplicate.
  Future<ServiceRequest> createDraft({
    required String propertyId,
    required String categoryId,
    required String problemDescription,
    required AddressSnapshot address,
    String? problemTypeId,
    String urgency = 'NORMAL',
    bool inspectionOnly = false,
    DateTime? preferredDate,
    String? preferredTimeWindow,
    String? customerNotes,
    String? idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requests,
      data: <String, dynamic>{
        'property_id': propertyId,
        'category_id': categoryId,
        'problem_description': problemDescription,
        'address': address.toPayload(),
        if (problemTypeId != null && problemTypeId.isNotEmpty)
          'problem_type_id': problemTypeId,
        if (urgency.isNotEmpty) 'urgency': urgency,
        if (inspectionOnly) 'inspection_only': true,
        // The backend rejects inspection_only + URGENT, so only send the date
        // when it can actually be honoured.
        if (preferredDate != null && !inspectionOnly)
          'preferred_date': preferredDate.toUtc().toIso8601String(),
        if (preferredTimeWindow != null && preferredTimeWindow.isNotEmpty)
          'preferred_time_window': preferredTimeWindow,
        if (customerNotes != null && customerNotes.isNotEmpty)
          'customer_notes': customerNotes,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotency_key': idempotencyKey,
      },
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }

  /// Attaches one photo. The multipart field must be named `file`, and the
  /// response is `{media: [...]}` rather than a bare array.
  Future<RequestMedia> uploadMedia({
    required String requestId,
    required String filename,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final Response<Map<String, dynamic>> response = await _client.upload(
      ApiEndpoints.requestMediaUpload(requestId),
      formData: FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: Options(contentType: contentType),
    );
    final Map<String, dynamic> body =
        response.data ?? const <String, dynamic>{};
    final List<Map<String, dynamic>> items = body.mapList('media');
    if (items.isEmpty) {
      throw StateError('Media upload returned no media item.');
    }
    return RequestMedia.fromJson(items.first);
  }

  Future<void> deleteMedia(String requestId, String mediaId) =>
      _client.delete(ApiEndpoints.requestMediaItem(requestId, mediaId));

  /// Attaches one normalized mark to an already-uploaded photo (§80).
  Future<void> addAnnotation({
    required String requestId,
    required String mediaId,
    required Map<String, dynamic> payload,
  }) async {
    await _client.post(
      ApiEndpoints.requestMediaAnnotations(requestId, mediaId),
      data: payload,
    );
  }

  /// Submits the draft. Rejects with 400 when no photo is attached.
  Future<ServiceRequest> submit(
    String requestId, {
    String? idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requestSubmit(requestId),
      data: <String, dynamic>{
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotency_key': idempotencyKey,
      },
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<ServiceRequest> cancel(String requestId, {String? reasonNote}) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requestCancel(requestId),
      data: <String, dynamic>{
        if (reasonNote != null && reasonNote.isNotEmpty)
          'reason_note': reasonNote,
      },
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<CancellationPreview> cancellationPreview(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.requestCancellationPreview(requestId),
    );
    return CancellationPreview.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  Future<List<RequestEvent>> timeline(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.requestTimeline(requestId),
    );
    return (response.data ?? const <String, dynamic>{})
        .mapList('events')
        .map(RequestEvent.fromJson)
        .toList(growable: false);
  }

  /// Returns null when the request has no quote yet; the endpoint returns JSON
  /// `null`, not a 404.
  Future<Quote?> quote(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.requestQuote(requestId),
    );
    final Map<String, dynamic> body =
        response.data ?? const <String, dynamic>{};
    if (body.isEmpty) return null;
    return Quote.fromJson(body);
  }

  /// `accepted_revision` must equal the server's current revision or it returns
  /// 409 QUOTE_SUPERSEDED, which is why the revision is carried back explicitly.
  Future<ServiceRequest> acceptQuote(
    String requestId, {
    required int acceptedRevision,
    String? idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requestQuoteAccept(requestId),
      data: <String, dynamic>{
        'accepted_revision': acceptedRevision,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotency_key': idempotencyKey,
      },
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<ServiceRequest> rejectQuote(String requestId, {String? reason}) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requestQuoteReject(requestId),
      data: <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return ServiceRequest.fromJson(response.data ?? const <String, dynamic>{});
  }
}
