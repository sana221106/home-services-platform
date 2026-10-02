import 'package:equatable/equatable.dart';

/// Every route name, declared once so `context.goNamed` can never be handed a
/// string literal that does not exist (go_router owns all navigation).
enum AppRoute {
  splash('splash', '/'),
  onboarding('onboarding', '/welcome'),
  phoneEntry('phone-entry', '/auth/phone'),
  otpVerify('otp-verify', '/auth/otp'),
  home('home', '/home'),
  requests('requests', '/requests'),
  requestNew('request-new', '/requests/new'),
  requestDetails('request-details', '/requests/new/details'),
  requestPhotos('request-photos', '/requests/new/photos'),
  requestLocation('request-location', '/requests/new/location'),
  requestReview('request-review', '/requests/new/review'),
  requestDetail('request-detail', '/requests/:requestId'),
  orders('orders', '/orders'),
  orderTracking('order-tracking', '/orders/:requestId'),
  properties('properties', '/properties'),
  propertyNew('property-new', '/properties/new'),
  propertyDetail('property-detail', '/properties/:propertyId'),
  propertyHistory('property-history', '/properties/:propertyId/history'),
  support('support', '/support'),
  payment('payment', '/requests/:requestId/payment'),
  rateService('rate-service', '/requests/:requestId/rate'),
  conversationNew('conversation-new', '/support/new'),
  conversationMessages(
    'conversation-messages',
    '/support/conversation/:conversationId',
  ),
  complaintNew('complaint-new', '/support/complaint/new'),
  reviews('reviews', '/reviews'),
  notifications('notifications', '/notifications'),
  profile('profile', '/profile'),
  profileEdit('profile-edit', '/profile/edit');

  const AppRoute(this.name, this.path);

  final String name;

  /// The location this route lives at, used by the redirect guard.
  ///
  /// go_router's top-level redirect never receives a route [name] (see its
  /// `buildTopLevelGoRouterState`, which leaves `name` null), so the guard has
  /// to reason about the matched location instead.
  final String path;

  /// Resolves a matched location back to its route, handling `:params`.
  static AppRoute? forLocation(String location) {
    for (final AppRoute route in AppRoute.values) {
      if (route.path == location) return route;
    }

    // No exact match: fall back to pattern matching, preferring the most
    // specific route (the one with the most literal segments).
    AppRoute? best;
    int bestScore = -1;
    final List<String> actual = location.split('/');
    for (final AppRoute route in AppRoute.values) {
      if (!route.path.contains(':')) continue;
      final List<String> pattern = route.path.split('/');
      if (pattern.length != actual.length) continue;
      bool matches = true;
      int score = 0;
      for (int i = 0; i < pattern.length; i++) {
        final String segment = pattern[i];
        if (segment.startsWith(':')) {
          if (actual[i].isEmpty) {
            matches = false;
            break;
          }
        } else if (segment != actual[i]) {
          matches = false;
          break;
        } else {
          score++;
        }
      }
      if (matches && score > bestScore) {
        best = route;
        bestScore = score;
      }
    }
    return best;
  }

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
    AppRoute.rateService,
    AppRoute.conversationNew,
    AppRoute.conversationMessages,
    AppRoute.complaintNew,
    AppRoute.reviews,
    AppRoute.notifications,
    AppRoute.profile,
    AppRoute.profileEdit,
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
