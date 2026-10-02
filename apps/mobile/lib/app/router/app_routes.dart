import 'package:equatable/equatable.dart';

/// Every route name, declared once so `context.goNamed` can never be handed a
/// string literal that does not exist (go_router owns all navigation).
enum AppRoute {
  splash('splash'),
  onboarding('onboarding'),
  phoneEntry('phone-entry'),
  otpVerify('otp-verify'),
  home('home'),
  requests('requests'),
  requestNew('request-new'),
  requestDetails('request-details'),
  requestPhotos('request-photos'),
  requestLocation('request-location'),
  requestReview('request-review'),
  requestDetail('request-detail'),
  orders('orders'),
  orderTracking('order-tracking'),
  properties('properties'),
  propertyNew('property-new'),
  propertyDetail('property-detail'),
  propertyHistory('property-history'),
  support('support'),
  payment('payment'),
  conversationNew('conversation-new'),
  conversationMessages('conversation-messages'),
  complaintNew('complaint-new'),
  reviews('reviews'),
  profile('profile');

  const AppRoute(this.name);

  final String name;

  /// Routes reachable only with a session.
  bool get requiresAuth => const <AppRoute>{
    AppRoute.home,
    AppRoute.requests,
    AppRoute.requestNew,
    AppRoute.requestDetails,
    AppRoute.requestPhotos,
    AppRoute.requestLocation,
    AppRoute.requestReview,
    AppRoute.requestDetail,
    AppRoute.orders,
    AppRoute.orderTracking,
    AppRoute.properties,
    AppRoute.propertyNew,
    AppRoute.propertyDetail,
    AppRoute.propertyHistory,
    AppRoute.support,
    AppRoute.payment,
    AppRoute.conversationNew,
    AppRoute.conversationMessages,
    AppRoute.complaintNew,
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
