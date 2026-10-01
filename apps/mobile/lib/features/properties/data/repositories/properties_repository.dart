import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/paginated.dart';
import '../datasources/properties_remote_data_source.dart';
import '../models/property_models.dart';

/// Repository for properties and their maintenance history.
///
/// It translates transport failures into [ApiFailure] and does nothing else.
/// Business rules such as deposit policy and pricing stay on the backend
/// (§8, §12, §13).
class PropertiesRepository {
  PropertiesRepository(this._remote, this._client);

  final PropertiesRemoteDataSource _remote;
  final ApiClient _client;

  Future<Paginated<Property>> list({int page = 1, int perPage = 20}) =>
      _guard(() => _remote.listProperties(page: page, perPage: perPage));

  Future<Property> get(String propertyId) =>
      _guard(() => _remote.getProperty(propertyId));

  Future<List<MaintenanceHistoryItem>> history(String propertyId) =>
      _guard(() => _remote.getHistory(propertyId));

  Future<Property> create({
    required String label,
    required String addressLine,
    String? district,
    String? city,
    String? governorate,
    String? zone,
    double? latitude,
    double? longitude,
    bool isDefault = false,
    List<PropertyContact> contacts = const <PropertyContact>[],
  }) => _guard(
    () => _remote.createProperty(
      label: label,
      addressLine: addressLine,
      district: district,
      city: city,
      governorate: governorate,
      zone: zone,
      latitude: latitude,
      longitude: longitude,
      isDefault: isDefault,
      contacts: contacts,
    ),
  );

  Future<Property> update(
    String propertyId, {
    String? label,
    String? addressLine,
    String? district,
    String? city,
    String? governorate,
    String? zone,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) => _guard(
    () => _remote.updateProperty(
      propertyId,
      label: label,
      addressLine: addressLine,
      district: district,
      city: city,
      governorate: governorate,
      zone: zone,
      latitude: latitude,
      longitude: longitude,
      isDefault: isDefault,
    ),
  );

  Future<void> delete(String propertyId) =>
      _guard(() => _remote.deleteProperty(propertyId));

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
final Provider<PropertiesRemoteDataSource> propertiesRemoteDataSourceProvider =
    Provider<PropertiesRemoteDataSource>(
      (Ref ref) => PropertiesRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'propertiesRemoteDataSource',
    );

final Provider<PropertiesRepository> propertiesRepositoryProvider =
    Provider<PropertiesRepository>(
      (Ref ref) => PropertiesRepository(
        ref.watch(propertiesRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'propertiesRepository',
    );
