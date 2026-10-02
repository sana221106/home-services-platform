import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/failure.dart';
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

  Future<List<Property>> list() => _guard(() => _remote.listProperties());

  Future<Property> get(String propertyId) =>
      _guard(() => _remote.getProperty(propertyId));

  Future<List<MaintenanceHistoryItem>> history(String propertyId) =>
      _guard(() => _remote.getHistory(propertyId));

  Future<Property> create({
    required String label,
    required String governorate,
    required String city,
    required double latitude,
    required double longitude,
    String? propertyType,
    String? zone,
    String? district,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? notes,
    bool isDefault = false,
    String? contactName,
    String? contactPhone,
  }) => _guard(
    () => _remote.createProperty(
      label: label,
      governorate: governorate,
      city: city,
      latitude: latitude,
      longitude: longitude,
      propertyType: propertyType,
      zone: zone,
      district: district,
      street: street,
      building: building,
      floor: floor,
      apartment: apartment,
      landmark: landmark,
      notes: notes,
      isDefault: isDefault,
      contactName: contactName,
      contactPhone: contactPhone,
    ),
  );

  Future<Property> update(
    String propertyId, {
    String? label,
    String? governorate,
    String? city,
    double? latitude,
    double? longitude,
    String? propertyType,
    String? zone,
    String? district,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? notes,
    bool? isDefault,
    String? contactName,
    String? contactPhone,
  }) => _guard(
    () => _remote.updateProperty(
      propertyId,
      label: label,
      governorate: governorate,
      city: city,
      latitude: latitude,
      longitude: longitude,
      propertyType: propertyType,
      zone: zone,
      district: district,
      street: street,
      building: building,
      floor: floor,
      apartment: apartment,
      landmark: landmark,
      notes: notes,
      isDefault: isDefault,
      contactName: contactName,
      contactPhone: contactPhone,
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
