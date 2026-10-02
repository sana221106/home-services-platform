import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../data/models/property_models.dart';
import '../../data/repositories/properties_repository.dart';

enum PropertiesStatus { initial, loading, ready, failed }

class PropertiesState extends Equatable {
  const PropertiesState({
    this.status = PropertiesStatus.initial,
    this.properties = const <Property>[],
    this.error,
    this.isMutating = false,
  });

  final PropertiesStatus status;
  final List<Property> properties;
  final String? error;
  final bool isMutating;

  bool get isEmpty => status == PropertiesStatus.ready && properties.isEmpty;

  /// The property a new request should default to (§61 snapshots the address
  /// at creation, so the wizard must pick one deliberately).
  Property? get defaultProperty {
    if (properties.isEmpty) return null;
    for (final property in properties) {
      if (property.isDefault) return property;
    }
    return properties.first;
  }

  PropertiesState copyWith({
    PropertiesStatus? status,
    List<Property>? properties,
    String? error,
    bool clearError = false,
    bool? isMutating,
  }) {
    return PropertiesState(
      status: status ?? this.status,
      properties: properties ?? this.properties,
      error: clearError ? null : (error ?? this.error),
      isMutating: isMutating ?? this.isMutating,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, properties, error, isMutating];
}

/// Loads the customer's properties.
///
/// Kept alive because both the request wizard and the properties tab read the
/// same list, and refetching on each navigation would be wasteful.
class PropertiesController extends Notifier<PropertiesState> {
  @override
  PropertiesState build() {
    ref.keepAlive();
    Future<void>.microtask(load);
    return const PropertiesState();
  }

  Future<void> load() async {
    state = state.copyWith(status: PropertiesStatus.loading, clearError: true);
    try {
      final List<Property> properties = await ref
          .read(propertiesRepositoryProvider)
          .list();
      state = state.copyWith(
        status: PropertiesStatus.ready,
        properties: properties,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: PropertiesStatus.failed,
        error: failure.message,
      );
    }
  }

  Future<Property?> create({
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
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final created = await ref
          .read(propertiesRepositoryProvider)
          .create(
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
          );
      state = state.copyWith(
        isMutating: false,
        properties: <Property>[...state.properties, created],
        status: PropertiesStatus.ready,
      );
      return created;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isMutating: false, error: failure.message);
      return null;
    }
  }

  Future<void> remove(String propertyId) async {
    final previous = state.properties;
    state = state.copyWith(
      properties: previous
          .where((Property p) => p.id != propertyId)
          .toList(growable: false),
      isMutating: true,
      clearError: true,
    );
    try {
      await ref.read(propertiesRepositoryProvider).delete(propertyId);
      state = state.copyWith(isMutating: false);
    } on ApiFailure catch (failure) {
      // Restore the row so the list never silently drops a property.
      state = state.copyWith(
        properties: previous,
        isMutating: false,
        error: failure.message,
      );
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final NotifierProvider<PropertiesController, PropertiesState>
propertiesProvider = NotifierProvider<PropertiesController, PropertiesState>(
  PropertiesController.new,
  name: 'properties',
);
