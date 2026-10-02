import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import 'app_routes.dart';

/// Decides where a navigation attempt is allowed to land.
///
/// Takes the matched location (not a route name -- go_router's top-level
/// redirect never receives a name) and returns the location to redirect to, or
/// null to allow the navigation.
///
/// Split out of `app_router.dart` so the authorisation gate can be unit tested
/// without a router, and so the route table stays a readable list of
/// destinations rather than a function body.
///
/// This is a UX gate only. The backend independently enforces every permission,
/// so a tampered client gains nothing here (§9).
String? resolveRedirect(AuthState auth, String location) {
  final AppRoute? current = AppRoute.forLocation(location);
  final bool atSplash = current == AppRoute.splash;

  // Wait for the token store before choosing a first screen, otherwise a
  // signed-in customer sees the onboarding carousel flash.
  if (auth.isRestoring) {
    return atSplash ? null : AppRoute.splash.path;
  }

  if (auth.isAuthenticated) {
    if (atSplash || (current?.requiresGuest ?? false)) {
      return AppRoute.home.path;
    }
    return null;
  }

  // Signed out. The guest flow (onboarding -> phone -> OTP) is the only place
  // an anonymous visitor may be; anything else, including an unmatched deep
  // link, is bounced to the start of that flow.
  if (atSplash) {
    return AppRoute.onboarding.path;
  }
  if (current != null && current.requiresGuest) {
    return null;
  }
  return AppRoute.onboarding.path;
}

/// Resolves a route name back to its enum value.
AppRoute? routeByName(String name) {
  for (final AppRoute route in AppRoute.values) {
    if (route.name == name) return route;
  }
  return null;
}

/// Bridges Riverpod auth changes into go_router's redirect cycle.
///
/// `go_router` only re-evaluates redirects when its `refreshListenable` fires,
/// so this forwards auth state changes into `notifyListeners`.
class SessionListenable extends ChangeNotifier {
  SessionListenable(this._ref) {
    _subscription = _ref.listen<AuthState>(
      authProvider,
      (AuthState? previous, AuthState next) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
