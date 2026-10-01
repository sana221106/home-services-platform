import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/app/router/app_routes.dart';
import 'package:home_services_app/app/router/route_guards.dart';
import 'package:home_services_app/features/auth/presentation/controllers/auth_controller.dart';

void main() {
  // The guard only reads the context to satisfy the callback signature, so a
  // real BuildContext is not needed to test the decision table.
  late BuildContext context;

  setUp(() {
    context = _TestContext();
  });

  const AuthState restoring = AuthState.restoring();
  const AuthState guest = AuthState(stage: AuthStage.unauthenticated);
  const AuthState awaitingOtp = AuthState(stage: AuthStage.awaitingOtp);
  const AuthState signedIn = AuthState(stage: AuthStage.authenticated);

  group('while the token store is still being read', () {
    test('holds the customer on splash from anywhere', () {
      expect(
        resolveRedirect(context, restoring, AppRoute.home.name),
        AppRoute.splash.name,
      );
      expect(
        resolveRedirect(context, restoring, AppRoute.onboarding.name),
        AppRoute.splash.name,
      );
    });

    test('leaves splash alone', () {
      expect(resolveRedirect(context, restoring, AppRoute.splash.name), isNull);
    });
  });

  group('signed in', () {
    test('sends splash straight to home, skipping onboarding', () {
      expect(
        resolveRedirect(context, signedIn, AppRoute.splash.name),
        AppRoute.home.name,
      );
    });

    test('bounces a guest-only route back to home', () {
      for (final route in <AppRoute>[
        AppRoute.onboarding,
        AppRoute.phoneEntry,
        AppRoute.otpVerify,
      ]) {
        expect(
          resolveRedirect(context, signedIn, route.name),
          AppRoute.home.name,
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
          resolveRedirect(context, signedIn, route.name),
          isNull,
          reason: route.name,
        );
      }
    });
  });

  group('signed out', () {
    test('sends splash to onboarding, not to the phone form', () {
      expect(
        resolveRedirect(context, guest, AppRoute.splash.name),
        AppRoute.onboarding.name,
      );
    });

    test('keeps a customer behind onboarding', () {
      for (final route in <AppRoute>[
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
      ]) {
        expect(
          resolveRedirect(context, guest, route.name),
          AppRoute.onboarding.name,
          reason: route.name,
        );
      }
    });

    test('allows the guest flow to continue', () {
      for (final route in <AppRoute>[
        AppRoute.onboarding,
        AppRoute.phoneEntry,
        AppRoute.otpVerify,
      ]) {
        expect(
          resolveRedirect(context, guest, route.name),
          isNull,
          reason: route.name,
        );
      }
    });

    test('an OTP in flight does not block the OTP screen', () {
      expect(
        resolveRedirect(context, awaitingOtp, AppRoute.otpVerify.name),
        isNull,
      );
      expect(
        resolveRedirect(context, awaitingOtp, AppRoute.home.name),
        AppRoute.onboarding.name,
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

  group('route metadata', () {
    test('route names are unique', () {
      expect(
        AppRoute.values.map((r) => r.name).toSet().length,
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

class _TestContext extends StatelessElement {
  _TestContext() : super(const Placeholder());
}
