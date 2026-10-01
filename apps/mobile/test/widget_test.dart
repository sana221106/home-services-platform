import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:home_services_app/app/app.dart';
import 'package:home_services_app/app/bootstrap/providers.dart';
import 'package:home_services_app/core/storage/secure_storage_service.dart';
import 'package:home_services_app/features/auth/presentation/controllers/auth_controller.dart';

/// Shared overrides for every test here: real preferences are mocked, and the
/// keystore is swapped for an in-memory store so nothing touches a platform
/// channel.
List<Override> _overrides(SharedPreferences prefs) => <Override>[
  sharedPreferencesProvider.overrideWithValue(prefs),
  tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
];

Future<Widget> _buildApp() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: _overrides(prefs),
    child: const HomeServicesApp(),
  );
}

void main() {
  // The router resolves `/` through the splash redirect, so a real network call
  // is unavoidable. These assertions only cover the frames that render before it
  // resolves; anything deeper is covered by the router and controller suites.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'app boots and resolves the unauthenticated splash to onboarding',
    (WidgetTester tester) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
    },
  );

  test('a fresh session restores to the guest stage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final ProviderContainer container = ProviderContainer(
      overrides: _overrides(prefs),
    );
    addTearDown(container.dispose);

    // Riverpod 3 tears a provider down as soon as its last listener goes away,
    // and the controller kicks off its restore asynchronously. Holding a
    // subscription keeps it alive, and the completer lets the test wait for the
    // restore to actually settle instead of guessing how many microtasks deep
    // the token-store read happens to be.
    final Completer<AuthState> settled = Completer<AuthState>();
    final ProviderSubscription<AuthState> sub = container.listen<AuthState>(
      authProvider,
      (AuthState? previous, AuthState next) {
        if (next.stage != AuthStage.restoring && !settled.isCompleted) {
          settled.complete(next);
        }
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final AuthState state = await settled.future;

    expect(state.stage, AuthStage.unauthenticated);
    expect(state.isAuthenticated, isFalse);
  });
}
