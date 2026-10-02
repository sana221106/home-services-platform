import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/paginated.dart';
import '../models/property_models.dart';

/// Reads and writes the customer's properties and their maintenance history.
class PropertiesRemoteDataSource {
  PropertiesRemoteDataSource(this._client);

  final ApiClient _client;

  /// `GET /properties` answers with a bare `list[PropertyResponse]`, not a
  /// pagination envelope, so it is read through [ApiClient.getList].
  Future<List<Property>> listProperties() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.properties,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(Property.fromJson)
        .toList(growable: false);
  }

  Future<Property> getProperty(String propertyId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.property(propertyId),
    );
    return Property.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<MaintenanceHistoryItem>> getHistory(
    String propertyId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.propertyHistory(propertyId),
      query: <String, dynamic>{'page': page, 'per_page': perPage},
    );
    return Paginated<MaintenanceHistoryItem>.fromJson(
      response.data ?? const <String, dynamic>{},
      MaintenanceHistoryItem.fromJson,
    ).items;
  }

  /// Creates a property.
  ///
  /// The wire shape is the flat `CreatePropertyRequest`; `latitude`/`longitude`
  /// are required by the backend because every request snapshots them for area
  /// intelligence (§18). The primary contact is sent as the flat
  /// `contact_name`/`contact_phone` pair the endpoint accepts.
  Future<Property> createProperty({
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
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.properties,
      data: <String, dynamic>{
        'label': label,
        'governorate': governorate,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'property_type': ?propertyType,
        'zone': ?zone,
        'district': ?district,
        'street': ?street,
        'building': ?building,
        'floor': ?floor,
        'apartment': ?apartment,
        'landmark': ?landmark,
        'notes': ?notes,
        'is_default': isDefault,
        'contact_name': ?contactName,
        'contact_phone': ?contactPhone,
      },
    );
    return Property.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<Property> updateProperty(
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
  }) async {
    final Response<Map<String, dynamic>> response = await _client.patch(
      ApiEndpoints.property(propertyId),
      data: <String, dynamic>{
        'label': ?label,
        'governorate': ?governorate,
        'city': ?city,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'property_type': ?propertyType,
        'zone': ?zone,
        'district': ?district,
        'street': ?street,
        'building': ?building,
        'floor': ?floor,
        'apartment': ?apartment,
        'landmark': ?landmark,
        'notes': ?notes,
        'is_default': ?isDefault,
        'contact_name': ?contactName,
        'contact_phone': ?contactPhone,
      },
    );
    return Property.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> deleteProperty(String propertyId) =>
      _client.delete(ApiEndpoints.property(propertyId));
}
