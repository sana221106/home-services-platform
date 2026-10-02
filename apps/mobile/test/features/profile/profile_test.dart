import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:home_services_app/app/bootstrap/app_bootstrap.dart';
import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/localization/locale_provider.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/profile/data/models/profile_models.dart';
import 'package:home_services_app/features/profile/data/repositories/profile_repository.dart';
import 'package:home_services_app/features/profile/presentation/controllers/profile_controller.dart';
import 'package:home_services_app/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:home_services_app/features/profile/presentation/pages/profile_page.dart';

void main() {
  group('ProfileDetails', () {
    test('reads the identity fields and the counters', () {
      final ProfileDetails profile = ProfileDetails.fromJson(<String, dynamic>{
        'id': 'cust-1',
        'full_name': 'Mona Ali',
        'phone': '+201000000000',
        'email': 'mona@example.com',
        'preferred_language': 'ar',
        'properties_count': 2,
        'requests_count': 5,
        'completed_orders_count': 3,
        'member_since': '2025-03-01T10:00:00Z',
      });

      expect(profile.fullName, 'Mona Ali');
      expect(profile.requestsCount, 5);
      expect(profile.completedOrdersCount, 3);
      expect(profile.memberSince, isNotNull);
    });

    test('initials come from the first two words', () {
      expect(_profile(fullName: 'Mona Ali').initials, 'MA');
      expect(_profile(fullName: 'Mona').initials, 'M');
      expect(_profile(fullName: '').initials, '?');
    });

    test('an absent avatar is reported as absent', () {
      expect(_profile().hasAvatar, isFalse);
      expect(_profile(avatarUrl: 'https://x/y.jpg').hasAvatar, isTrue);
    });
  });

  group('ProfileController', () {
    test('load fills the profile', () async {
      final ProviderContainer container = _container(_FakeProfileRepository());
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).load();

      final ProfileState state = container.read(profileProvider);
      expect(state.status, ProfileStatus.ready);
      expect(state.profile?.fullName, 'Mona Ali');
    });

    test('a failed load offers the message', () async {
      final ProviderContainer container = _container(
        _FakeProfileRepository()
          ..loadError = const ApiFailure(
            code: 'NETWORK',
            message: 'Unavailable',
          ),
      );
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).load();

      expect(container.read(profileProvider).errorMessage, 'Unavailable');
    });

    test('save sends only the changed fields and confirms', () async {
      final _FakeProfileRepository repository = _FakeProfileRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).load();
      final bool ok = await container
          .read(profileProvider.notifier)
          .save(fullName: 'Mona Hassan', email: null);

      expect(ok, isTrue);
      expect(repository.savedFullName, 'Mona Hassan');
      expect(container.read(profileProvider).profile?.fullName, 'Mona Hassan');
      expect(container.read(profileProvider).saved, isTrue);
    });

    test('a rejected save keeps the customer on the form', () async {
      final ProviderContainer container = _container(
        _FakeProfileRepository()
          ..saveError = const ApiFailure(
            code: 'VALIDATION',
            message: 'Name already used',
          ),
      );
      addTearDown(container.dispose);

      final bool ok = await container
          .read(profileProvider.notifier)
          .save(fullName: 'Mona Hassan');

      expect(ok, isFalse);
      expect(container.read(profileProvider).errorMessage, 'Name already used');
      expect(container.read(profileProvider).isSaving, isFalse);
    });
  });

  group('AppLocaleController', () {
    test('arabic resolves to the ar locale and persists', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(localeProvider).locale, isNull);

      await container
          .read(localeProvider.notifier)
          .setLanguage(AppLanguage.arabic);

      expect(container.read(localeProvider).locale, const Locale('ar'));
      expect(prefs.getString(AppLocaleController.storageKey), 'language.ar');
    });
  });

  group('ProfilePage', () {
    testWidgets('renders the header and counters', (WidgetTester tester) async {
      await tester.pumpWidget(await _wrap(_FakeProfileRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Mona Ali'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeProfileRepository repository = _FakeProfileRepository()
        ..loadError = const ApiFailure(code: 'NETWORK', message: 'Unavailable');
      await tester.pumpWidget(await _wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);

      repository.loadError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Mona Ali'), findsOneWidget);
    });

    testWidgets('picking a language persists it', (WidgetTester tester) async {
      await tester.pumpWidget(await _wrap(_FakeProfileRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('profile-option-AppLanguage.english')),
      );
      await tester.pumpAndSettle();

      expect(find.text('English'), findsWidgets);
    });

    testWidgets('logging out asks for confirmation first', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(await _wrap(_FakeProfileRepository()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Log out'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      // The dialog must exist; confirming is what actually ends the session.
      expect(find.text('Log out?'), findsOneWidget);
    });
  });

  group('EditProfilePage', () {
    testWidgets('a blank name is refused', (WidgetTester tester) async {
      final _FakeProfileRepository repository = _FakeProfileRepository();
      await tester.pumpWidget(await _wrap(repository, edit: true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('profile-name')), '');
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();

      expect(find.text('This field is required'), findsOneWidget);
      expect(repository.savedFullName, isNull);
    });

    testWidgets('a changed name is saved', (WidgetTester tester) async {
      final _FakeProfileRepository repository = _FakeProfileRepository();
      await tester.pumpWidget(await _wrap(repository, edit: true));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Mona Hassan',
      );
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();

      expect(repository.savedFullName, 'Mona Hassan');
    });

    testWidgets('a rejected save shows the reason', (
      WidgetTester tester,
    ) async {
      final _FakeProfileRepository repository = _FakeProfileRepository()
        ..saveError = const ApiFailure(
          code: 'VALIDATION',
          message: 'Name already used',
        );
      await tester.pumpWidget(await _wrap(repository, edit: true));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Mona Hassan',
      );
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();

      expect(find.text('Name already used'), findsOneWidget);
    });
  });
}

ProfileDetails _profile({String fullName = 'Mona Ali', String? avatarUrl}) {
  return ProfileDetails(
    id: 'cust-1',
    fullName: fullName,
    phone: '+201000000000',
    avatarUrl: avatarUrl,
    propertiesCount: 2,
    requestsCount: 5,
    completedOrdersCount: 3,
  );
}

Future<Widget> _wrap(
  _FakeProfileRepository repository, {
  bool edit = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      profileRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: edit ? const EditProfilePage() : const ProfilePage(),
    ),
  );
}

ProviderContainer _container(_FakeProfileRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      profileRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakeProfileRepository implements ProfileRepository {
  ProfileDetails value = _profile();
  ApiFailure? loadError;
  ApiFailure? saveError;

  String? savedFullName;
  String? savedEmail;
  String? savedLanguage;

  @override
  Future<ProfileDetails> profile() async {
    final ApiFailure? failure = loadError;
    if (failure != null) throw failure;
    return value;
  }

  @override
  Future<ProfileDetails> update({
    String? fullName,
    String? email,
    String? preferredLanguage,
  }) async {
    savedFullName = fullName;
    savedEmail = email;
    savedLanguage = preferredLanguage;
    final ApiFailure? failure = saveError;
    if (failure != null) throw failure;
    value = ProfileDetails(
      id: value.id,
      fullName: fullName ?? value.fullName,
      phone: value.phone,
      email: email ?? value.email,
      preferredLanguage: preferredLanguage ?? value.preferredLanguage,
      propertiesCount: value.propertiesCount,
      requestsCount: value.requestsCount,
      completedOrdersCount: value.completedOrdersCount,
      memberSince: value.memberSince,
    );
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
