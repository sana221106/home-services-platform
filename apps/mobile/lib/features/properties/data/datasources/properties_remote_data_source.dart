import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/paginated.dart';
import '../models/property_models.dart';

/// Reads and writes the customer's properties and their maintenance history.
class PropertiesRemoteDataSource {
  PropertiesRemoteDataSource(this._client);

  final ApiClient _client;

  Future<Paginated<Property>> listProperties({
    int page = 1,
    int perPage = 20,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.properties,
      query: <String, dynamic>{'page': page, 'per_page': perPage},
    );
    return Paginated<Property>.fromJson(
      response.data ?? const <String, dynamic>{},
      Property.fromJson,
    );
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

  /// Creates a property. The backend copies the address onto every future
  /// request as a snapshot, so the payload is flat, not nested.
  Future<Property> createProperty({
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
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.properties,
      data: <String, dynamic>{
        'label': label,
        'address_line': addressLine,
        'district': ?district,
        'city': ?city,
        'governorate': ?governorate,
        'zone': ?zone,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'is_default': isDefault,
        if (contacts.isNotEmpty)
          'contacts': contacts
              .map(
                (PropertyContact c) => <String, dynamic>{
                  'contact_name': c.name,
                  if (c.phone != null) 'phone': c.phone,
                  if (c.relation != null) 'relation': c.relation,
                  if (c.isPrimary) 'is_primary': true,
                },
              )
              .toList(growable: false),
      },
    );
    return Property.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<Property> updateProperty(
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
  }) async {
    final Response<Map<String, dynamic>> response = await _client.patch(
      ApiEndpoints.property(propertyId),
      data: <String, dynamic>{
        'label': ?label,
        'address_line': ?addressLine,
        'district': ?district,
        'city': ?city,
        'governorate': ?governorate,
        'zone': ?zone,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'is_default': ?isDefault,
      },
    );
    return Property.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> deleteProperty(String propertyId) =>
      _client.delete(ApiEndpoints.property(propertyId));
}
