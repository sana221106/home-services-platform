import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import 'app_routes.dart';

/// Decides where a navigation attempt is allowed to land.
///
/// Returns the route name to redirect to, or null to allow the navigation.
///
/// Split out of `app_router.dart` so the authorisation gate can be unit tested
/// without a router, and so the route table stays a readable list of
/// destinations rather than a function body.
///
/// This is a UX gate only. The backend independently enforces every permission,
/// so a tampered client gains nothing here (§9).
String? resolveRedirect(BuildContext context, AuthState auth, String name) {
  // Wait for the token store before choosing a first screen, otherwise a
  // signed-in customer sees the onboarding carousel flash.
  if (auth.isRestoring) {
    return name == AppRoute.splash.name ? null : AppRoute.splash.name;
  }

  final AppRoute? current = routeByName(name);
  final bool atSplash = name == AppRoute.splash.name;

  if (auth.isAuthenticated) {
    if (atSplash) {
      return AppRoute.home.name;
    }
    if (current != null && current.requiresGuest) {
      return AppRoute.home.name;
    }
    return null;
  }

  if (atSplash) {
    return AppRoute.onboarding.name;
  }
  if (current != null && current.requiresAuth) {
    return AppRoute.onboarding.name;
  }
  return null;
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
