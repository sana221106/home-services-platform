import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/app/router/app_routes.dart';
import 'package:home_services_app/app/router/route_guards.dart';
import 'package:home_services_app/features/auth/presentation/controllers/auth_controller.dart';

void main() {
  const AuthState restoring = AuthState.restoring();
  const AuthState guest = AuthState(stage: AuthStage.unauthenticated);
  const AuthState awaitingOtp = AuthState(stage: AuthStage.awaitingOtp);
  const AuthState signedIn = AuthState(stage: AuthStage.authenticated);

  group('while the token store is still being read', () {
    test('holds the customer on splash from anywhere', () {
      expect(
        resolveRedirect(restoring, AppRoute.home.path),
        AppRoute.splash.path,
      );
      expect(
        resolveRedirect(restoring, AppRoute.onboarding.path),
        AppRoute.splash.path,
      );
    });

    test('leaves splash alone', () {
      expect(resolveRedirect(restoring, AppRoute.splash.path), isNull);
    });
  });

  group('signed in', () {
    test('sends splash straight to home, skipping onboarding', () {
      expect(
        resolveRedirect(signedIn, AppRoute.splash.path),
        AppRoute.home.path,
      );
    });

    test('bounces a guest-only route back to home', () {
      for (final route in <AppRoute>[
        AppRoute.onboarding,
        AppRoute.phoneEntry,
        AppRoute.otpVerify,
      ]) {
        expect(
          resolveRedirect(signedIn, route.path),
          AppRoute.home.path,
          reason: route.name,
        );
      }
    });

    test('allows customer routes through', () {
      for (final route in <AppRoute>[
        AppRoute.home,
        AppRoute.requests,
        AppRoute.orders,
        AppRoute.properties,
        AppRoute.profile,
      ]) {
        expect(
          resolveRedirect(signedIn, route.path),
          isNull,
          reason: route.name,
        );
      }
    });

    test('allows routes with a path parameter through', () {
      expect(resolveRedirect(signedIn, '/requests/abc123'), isNull);
      expect(resolveRedirect(signedIn, '/requests/abc123/payment'), isNull);
      expect(resolveRedirect(signedIn, '/properties/abc123/history'), isNull);
      expect(resolveRedirect(signedIn, '/orders/abc123'), isNull);
    });
  });

  group('signed out', () {
    test('sends splash to onboarding, not to the phone form', () {
      expect(
        resolveRedirect(guest, AppRoute.splash.path),
        AppRoute.onboarding.path,
      );
    });

    test('keeps a customer behind onboarding', () {
      for (final route in <AppRoute>[
        AppRoute.home,
        AppRoute.requests,
        AppRoute.requestNew,
        AppRoute.requestDetail,
        AppRoute.orders,
        AppRoute.orderTracking,
        AppRoute.properties,
        AppRoute.propertyNew,
        AppRoute.propertyDetail,
        AppRoute.propertyHistory,
        AppRoute.support,
        AppRoute.reviews,
        AppRoute.profile,
      ]) {
        expect(
          resolveRedirect(guest, route.path),
          AppRoute.onboarding.path,
          reason: route.name,
        );
      }
    });

    test('bounces an unmatched deep link to onboarding', () {
      expect(
        resolveRedirect(guest, '/some/deep/link'),
        AppRoute.onboarding.path,
      );
      expect(
        resolveRedirect(guest, '/requests/abc123'),
        AppRoute.onboarding.path,
      );
    });

    test('allows the guest flow to continue', () {
      for (final route in <AppRoute>[
        AppRoute.onboarding,
        AppRoute.phoneEntry,
        AppRoute.otpVerify,
      ]) {
        expect(resolveRedirect(guest, route.path), isNull, reason: route.name);
      }
    });

    test('an OTP in flight does not block the OTP screen', () {
      expect(resolveRedirect(awaitingOtp, AppRoute.otpVerify.path), isNull);
      expect(
        resolveRedirect(awaitingOtp, AppRoute.home.path),
        AppRoute.onboarding.path,
      );
    });
  });

  group('routeByName', () {
    test('round trips every route', () {
      for (final route in AppRoute.values) {
        expect(routeByName(route.name), route);
      }
    });

    test('returns null for an unknown name', () {
      expect(routeByName('does-not-exist'), isNull);
    });
  });

  group('AppRoute.forLocation', () {
    test('resolves every static path', () {
      for (final route in AppRoute.values) {
        if (route.path.contains(':')) continue;
        expect(AppRoute.forLocation(route.path), route, reason: route.name);
      }
    });

    test('resolves parameterised paths', () {
      expect(AppRoute.forLocation('/requests/abc'), AppRoute.requestDetail);
      expect(AppRoute.forLocation('/requests/abc/payment'), AppRoute.payment);
      expect(AppRoute.forLocation('/requests/abc/rate'), AppRoute.rateService);
      expect(AppRoute.forLocation('/orders/abc'), AppRoute.orderTracking);
      expect(AppRoute.forLocation('/properties/abc'), AppRoute.propertyDetail);
      expect(
        AppRoute.forLocation('/properties/abc/history'),
        AppRoute.propertyHistory,
      );
      expect(
        AppRoute.forLocation('/support/conversation/abc'),
        AppRoute.conversationMessages,
      );
    });

    test('prefers an exact static route over a parameter pattern', () {
      expect(AppRoute.forLocation('/requests/new'), AppRoute.requestNew);
      expect(AppRoute.forLocation('/properties/new'), AppRoute.propertyNew);
      expect(
        AppRoute.forLocation('/support/complaint/new'),
        AppRoute.complaintNew,
      );
    });

    test('returns null for an unknown location', () {
      expect(AppRoute.forLocation('/nope/nope'), isNull);
    });
  });

  group('route metadata', () {
    test('route names are unique', () {
      expect(
        AppRoute.values.map((r) => r.name).toSet().length,
        AppRoute.values.length,
      );
    });

    test('route paths are unique', () {
      expect(
        AppRoute.values.map((r) => r.path).toSet().length,
        AppRoute.values.length,
      );
    });

    test('no route is both guest-only and session-only', () {
      for (final route in AppRoute.values) {
        expect(
          route.requiresAuth && route.requiresGuest,
          isFalse,
          reason: route.name,
        );
      }
    });

    test('splash belongs to neither group', () {
      expect(AppRoute.splash.requiresAuth, isFalse);
      expect(AppRoute.splash.requiresGuest, isFalse);
    });
  });
}
