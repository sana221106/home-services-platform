import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/errors/failure.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/orders_repository.dart';

enum OrderTrackingStatus { initial, loading, ready, failed }

class OrderTrackingState extends Equatable {
  const OrderTrackingState({
    this.status = OrderTrackingStatus.initial,
    this.tracking,
    this.errorMessage,
  });

  final OrderTrackingStatus status;
  final OrderTracking? tracking;
  final String? errorMessage;

  OrderTrackingState copyWith({
    OrderTrackingStatus? status,
    OrderTracking? tracking,
    String? errorMessage,
  }) {
    return OrderTrackingState(
      status: status ?? this.status,
      tracking: tracking ?? this.tracking,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, tracking, errorMessage];
}

/// Backs the tracking screen for one order.
///
/// Tracking is a single endpoint that already contains the timeline, so there is
/// no second request to orchestrate here — unlike the request detail screen,
/// which fetches three resources in parallel.
class OrderTrackingController extends Notifier<OrderTrackingState> {
  OrderTrackingController(this.requestId);

  final String requestId;

  @override
  OrderTrackingState build() {
    // Riverpod 3 dropped `FamilyNotifier`, so a family member is a plain
    // notifier that receives its argument in the constructor.
    Future<void>.microtask(load);
    return const OrderTrackingState(status: OrderTrackingStatus.loading);
  }

  Future<void> load() async {
    try {
      final OrderTracking tracking = await ref
          .read(ordersRepositoryProvider)
          .track(requestId);
      state = OrderTrackingState(
        status: OrderTrackingStatus.ready,
        tracking: tracking,
      );
    } on ApiFailure catch (failure) {
      state = OrderTrackingState(
        status: OrderTrackingStatus.failed,
        errorMessage: failure.message,
      );
    }
  }
}

final NotifierProviderFamily<
  OrderTrackingController,
  OrderTrackingState,
  String
>
orderTrackingProvider =
    NotifierProvider.family<
      OrderTrackingController,
      OrderTrackingState,
      String
    >(OrderTrackingController.new, name: 'orderTracking');
