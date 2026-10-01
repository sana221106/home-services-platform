import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/errors/failure.dart';
import '../../data/models/property_models.dart';
import '../../data/repositories/properties_repository.dart';

enum PropertyHistoryStatus { initial, loading, ready, failed }

class PropertyHistoryState extends Equatable {
  const PropertyHistoryState({
    this.status = PropertyHistoryStatus.initial,
    this.property,
    this.items = const <MaintenanceHistoryItem>[],
    this.error,
  });

  final PropertyHistoryStatus status;

  /// The property itself, so the header can show its label instead of a bare id.
  final Property? property;

  final List<MaintenanceHistoryItem> items;
  final String? error;

  /// Number of past visits the backend linked to the same recurring issue.
  ///
  /// This is reported, not computed: §17 leaves recurrence detection to the
  /// backend, so the client must never group rows itself.
  int get recurringCount =>
      items.where((MaintenanceHistoryItem item) => item.isRecurring).length;

  bool get isEmpty => status == PropertyHistoryStatus.ready && items.isEmpty;

  PropertyHistoryState copyWith({
    PropertyHistoryStatus? status,
    Property? property,
    List<MaintenanceHistoryItem>? items,
    String? error,
    bool clearError = false,
  }) {
    return PropertyHistoryState(
      status: status ?? this.status,
      property: property ?? this.property,
      items: items ?? this.items,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, property, items, error];
}

/// Loads maintenance history for a single property.
///
/// Riverpod 3 hands the family argument to the constructor, so the id is a
/// field rather than a `build` parameter. Auto-disposes on leave, but a refetch
/// keeps the previous payload so pull-to-refresh never blanks the list.
class PropertyHistoryController extends Notifier<PropertyHistoryState> {
  PropertyHistoryController(this.propertyId);

  final String propertyId;

  @override
  PropertyHistoryState build() {
    Future<void>.microtask(load);
    return const PropertyHistoryState();
  }

  Future<void> load() async {
    state = state.copyWith(
      status: PropertyHistoryStatus.loading,
      clearError: true,
    );

    final repository = ref.read(propertiesRepositoryProvider);

    // The header only needs the label, so a failure here must not hide an
    // otherwise valid history list.
    Property? property = state.property;
    try {
      property = await repository.get(propertyId);
    } on ApiFailure {
      property = state.property;
    }

    try {
      final List<MaintenanceHistoryItem> items = await repository.history(
        propertyId,
      );
      state = state.copyWith(
        status: PropertyHistoryStatus.ready,
        property: property,
        items: items,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: PropertyHistoryStatus.failed,
        property: property,
        error: failure.message,
      );
    }
  }

  /// Pull-to-refresh, so the list is replaced without a spinner swap.
  Future<void> refresh() => load();
}

final NotifierProviderFamily<
  PropertyHistoryController,
  PropertyHistoryState,
  String
>
propertyHistoryProvider =
    NotifierProvider.family<
      PropertyHistoryController,
      PropertyHistoryState,
      String
    >(PropertyHistoryController.new, name: 'propertyHistory');
