import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/paginated.dart';
import '../../../properties/data/models/property_models.dart';
import '../../../properties/data/repositories/properties_repository.dart';
import '../datasources/requests_remote_data_source.dart';
import '../models/photo_annotation.dart';
import '../models/request_models.dart';

/// Repository for the catalogue and for the request lifecycle.
///
/// It translates transport failures into [ApiFailure] and does nothing else.
/// Quoting, deposit policy and status transitions stay on the backend; the
/// client only reflects them (§8, §12, §13).
class RequestsRepository {
  RequestsRepository(this._requests, this._catalogue, this._client);

  final RequestsRemoteDataSource _requests;
  final CatalogueRemoteDataSource _catalogue;
  final ApiClient _client;

  // ------------------------------------------------------------- catalogue

  /// One call instead of N+1: the catalogue nests problem types per category.
  Future<List<ServiceCategory>> catalogue() => _guard(_catalogue.catalogue);

  Future<List<ProblemType>> problems(String categoryId) =>
      _guard(() => _catalogue.problems(categoryId));

  // --------------------------------------------------------------- reading

  Future<Paginated<ServiceRequest>> list({
    int page = 1,
    int perPage = 20,
    List<String> statuses = const <String>[],
  }) => _guard(
    () => _requests.list(page: page, perPage: perPage, statuses: statuses),
  );

  Future<ServiceRequest> detail(String requestId) =>
      _guard(() => _requests.detail(requestId));

  Future<List<RequestEvent>> timeline(String requestId) =>
      _guard(() => _requests.timeline(requestId));

  Future<Quote?> quote(String requestId) =>
      _guard(() => _requests.quote(requestId));

  Future<CancellationPreview> cancellationPreview(String requestId) =>
      _guard(() => _requests.cancellationPreview(requestId));

  // -------------------------------------------------------------- writing

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
  }) => _guard(
    () => _requests.createDraft(
      propertyId: propertyId,
      categoryId: categoryId,
      problemDescription: problemDescription,
      address: address,
      problemTypeId: problemTypeId,
      urgency: urgency,
      inspectionOnly: inspectionOnly,
      preferredDate: preferredDate,
      preferredTimeWindow: preferredTimeWindow,
      customerNotes: customerNotes,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<RequestMedia> uploadMedia({
    required String requestId,
    required String filename,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) => _guard(
    () => _requests.uploadMedia(
      requestId: requestId,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
    ),
  );

  Future<void> deleteMedia(String requestId, String mediaId) =>
      _guard(() => _requests.deleteMedia(requestId, mediaId));

  /// Attaches one drawn mark to an uploaded photo. The payload shape is the
  /// backend `CreateAnnotationRequest` built by [PhotoAnnotation.toPayload].
  Future<void> addAnnotation({
    required String requestId,
    required String mediaId,
    required PhotoAnnotation annotation,
  }) => _guard(
    () => _requests.addAnnotation(
      requestId: requestId,
      mediaId: mediaId,
      payload: annotation.toPayload(),
    ),
  );

  Future<ServiceRequest> submit(String requestId, {String? idempotencyKey}) =>
      _guard(() => _requests.submit(requestId, idempotencyKey: idempotencyKey));

  Future<ServiceRequest> cancel(String requestId, {String? reasonNote}) =>
      _guard(() => _requests.cancel(requestId, reasonNote: reasonNote));

  Future<ServiceRequest> acceptQuote(
    String requestId, {
    required int acceptedRevision,
  }) => _guard(
    () => _requests.acceptQuote(requestId, acceptedRevision: acceptedRevision),
  );

  Future<ServiceRequest> rejectQuote(String requestId, {String? reason}) =>
      _guard(() => _requests.rejectQuote(requestId, reason: reason));

  /// Runs [action] and maps any failure onto the app's error type, so widgets
  /// only ever see [ApiFailure].
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

/// Convenience providers so pages never build the object graph by hand.
final Provider<RequestsRemoteDataSource> requestsRemoteDataSourceProvider =
    Provider<RequestsRemoteDataSource>(
      (Ref ref) => RequestsRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'requestsRemoteDataSource',
    );

final Provider<CatalogueRemoteDataSource> catalogueRemoteDataSourceProvider =
    Provider<CatalogueRemoteDataSource>(
      (Ref ref) => CatalogueRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'catalogueRemoteDataSource',
    );

final Provider<RequestsRepository> requestsRepositoryProvider =
    Provider<RequestsRepository>(
      (Ref ref) => RequestsRepository(
        ref.watch(requestsRemoteDataSourceProvider),
        ref.watch(catalogueRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'requestsRepository',
    );

/// The catalogue is shared by the wizard and any category picker, so it is
/// kept alive instead of refetching on every navigation.
final FutureProvider<List<ServiceCategory>> catalogueProvider =
    FutureProvider<List<ServiceCategory>>(
      (Ref ref) => ref.watch(requestsRepositoryProvider).catalogue(),
      name: 'catalogue',
    );

/// Property list for the wizard's location step, reused from the properties
/// feature so both screens agree on ordering and the default property.
final FutureProvider<List<Property>> wizardPropertiesProvider =
    FutureProvider<List<Property>>(
      (Ref ref) => ref.watch(propertiesRepositoryProvider).list(),
      name: 'wizardProperties',
    );
