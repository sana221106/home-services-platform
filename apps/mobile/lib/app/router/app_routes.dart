import 'package:equatable/equatable.dart';

/// Every route name, declared once so `context.goNamed` can never be handed a
/// string literal that does not exist (§20: go_router owns all navigation).
enum AppRoute {
  splash('splash'),
  onboarding('onboarding'),
  phoneEntry('phone-entry'),
  otpVerify('otp-verify'),
  home('home'),
  requests('requests'),
  requestNew('request-new'),
  requestDetail('request-detail'),
  orders('orders'),
  orderDetail('order-detail'),
  orderTracking('order-tracking'),
  properties('properties'),
  propertyNew('property-new'),
  propertyDetail('property-detail'),
  propertyHistory('property-history'),
  support('support'),
  reviews('reviews'),
  profile('profile');

  const AppRoute(this.name);

  final String name;

  /// Routes reachable only with a session.
  bool get requiresAuth => const <AppRoute>{
    AppRoute.home,
    AppRoute.requests,
    AppRoute.requestNew,
    AppRoute.requestDetail,
    AppRoute.orders,
    AppRoute.orderDetail,
    AppRoute.orderTracking,
    AppRoute.properties,
    AppRoute.propertyNew,
    AppRoute.propertyDetail,
    AppRoute.propertyHistory,
    AppRoute.support,
    AppRoute.reviews,
    AppRoute.profile,
  }.contains(this);

  /// Routes reachable only without a session.
  bool get requiresGuest => const <AppRoute>{
    AppRoute.onboarding,
    AppRoute.phoneEntry,
    AppRoute.otpVerify,
  }.contains(this);
}

/// Tabs of the customer bottom bar.
enum HomeTab {
  home('home', 'assets/icons/home.svg'),
  requests('requests', 'assets/icons/orders.svg'),
  properties('properties', 'assets/icons/building.svg'),
  support('support', 'assets/icons/chat.svg'),
  profile('profile', 'assets/icons/user.svg');

  const HomeTab(this.routeName, this.iconAsset);

  final String routeName;
  final String iconAsset;
}

/// Immutable bottom-tab selection, so the shell does not need `setState`.
class TabSelection extends Equatable {
  const TabSelection(this.tab);

  final HomeTab tab;

  @override
  List<Object?> get props => <Object?>[tab];
}
