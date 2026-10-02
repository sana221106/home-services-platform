import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/errors/failure.dart';
import '../../data/models/property_models.dart';
import '../../data/repositories/properties_repository.dart';

enum PropertyDetailStatus { initial, loading, ready, failed }

class PropertyDetailState extends Equatable {
  const PropertyDetailState({
    this.status = PropertyDetailStatus.initial,
    this.property,
    this.error,
    this.isMutating = false,
    this.deleted = false,
  });

  final PropertyDetailStatus status;
  final Property? property;
  final String? error;
  final bool isMutating;

  /// Set once the backend archived the property, so the page can pop instead of
  /// rebuilding against a row that no longer exists.
  final bool deleted;

  PropertyDetailState copyWith({
    PropertyDetailStatus? status,
    Property? property,
    String? error,
    bool clearError = false,
    bool? isMutating,
    bool? deleted,
  }) {
    return PropertyDetailState(
      status: status ?? this.status,
      property: property ?? this.property,
      error: clearError ? null : (error ?? this.error),
      isMutating: isMutating ?? this.isMutating,
      deleted: deleted ?? this.deleted,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    property,
    error,
    isMutating,
    deleted,
  ];
}

/// Loads and mutates a single property (screen 14).
///
/// Riverpod 3 passes the family argument to the constructor, so the id is a
/// field rather than a `build` parameter.
class PropertyDetailController extends Notifier<PropertyDetailState> {
  PropertyDetailController(this.propertyId);

  final String propertyId;

  @override
  PropertyDetailState build() {
    Future<void>.microtask(load);
    return const PropertyDetailState();
  }

  Future<void> load() async {
    state = state.copyWith(
      status: PropertyDetailStatus.loading,
      clearError: true,
    );
    try {
      final Property property = await ref
          .read(propertiesRepositoryProvider)
          .get(propertyId);
      state = state.copyWith(
        status: PropertyDetailStatus.ready,
        property: property,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: PropertyDetailStatus.failed,
        error: failure.message,
      );
    }
  }

  /// Promotes this property to the customer's default. The backend demotes the
  /// previous default in the same transaction, so a local refetch is enough.
  Future<bool> setDefault() async {
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final Property updated = await ref
          .read(propertiesRepositoryProvider)
          .update(propertyId, isDefault: true);
      state = state.copyWith(
        isMutating: false,
        property: updated,
        status: PropertyDetailStatus.ready,
      );
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isMutating: false, error: failure.message);
      return false;
    }
  }

  Future<bool> remove() async {
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      await ref.read(propertiesRepositoryProvider).delete(propertyId);
      state = state.copyWith(isMutating: false, deleted: true);
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isMutating: false, error: failure.message);
      return false;
    }
  }
}

final NotifierProviderFamily<
  PropertyDetailController,
  PropertyDetailState,
  String
>
propertyDetailProvider =
    NotifierProvider.family<
      PropertyDetailController,
      PropertyDetailState,
      String
    >(PropertyDetailController.new, name: 'propertyDetail');
