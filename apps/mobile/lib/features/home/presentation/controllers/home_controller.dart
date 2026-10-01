import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/errors/failure.dart';
import '../../data/repositories/home_repository.dart';
import '../../data/models/home_models.dart';


enum HomeStatus { initial, loading, ready, failed }

class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.dashboard,
    this.errorMessage,
  });

  final HomeStatus status;
  final HomeDashboard? dashboard;
  final String? errorMessage;

  /// True only when the first load failed: a failed refresh while data is
  /// already on screen should not blank the dashboard.
  bool get isFatalError => status == HomeStatus.failed && dashboard == null;

  HomeState copyWith({
    HomeStatus? status,
    HomeDashboard? dashboard,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      dashboard: dashboard ?? this.dashboard,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, dashboard, errorMessage];
}

class HomeController extends Notifier<HomeState> {
  @override
  HomeState build() {
    ref.keepAlive();
    return const HomeState();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(status: HomeStatus.loading);
    try {
      final dashboard = await ref.read(homeRepositoryProvider).dashboard();
      state = HomeState(status: HomeStatus.ready, dashboard: dashboard);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: HomeStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  /// Called by the shell when the home tab becomes visible again, so a request
  /// completed on the orders tab is reflected without a pull-to-refresh.
  void refresh() => load(silent: state.dashboard != null);
}

final NotifierProvider<HomeController, HomeState> homeProvider =
    NotifierProvider<HomeController, HomeState>(
      HomeController.new,
      name: 'home',
    );
