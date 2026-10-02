import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/pages/onboarding_screen.dart';
import '../../features/auth/presentation/pages/otp_verify_screen.dart';
import '../../features/auth/presentation/pages/phone_entry_screen.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/orders/presentation/pages/order_tracking_page.dart';
import '../../features/orders/presentation/pages/orders_page.dart';
import '../../features/payments/presentation/pages/payment_page.dart';
import '../../features/support/presentation/pages/complaint_pages.dart';
import '../../features/support/presentation/pages/conversation_page.dart';
import '../../features/support/presentation/pages/support_page.dart';
import '../../features/properties/presentation/pages/properties_page.dart';
import '../../features/properties/presentation/pages/property_detail_page.dart';
import '../../features/properties/presentation/pages/property_history_page.dart';
import '../../features/properties/presentation/pages/property_new_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/reviews/presentation/pages/reviews_page.dart';
import '../../features/requests/presentation/pages/location_page.dart';
import '../../features/requests/presentation/pages/problem_details_page.dart';
import '../../features/requests/presentation/pages/photo_annotation_page.dart';
import '../../features/requests/presentation/pages/request_detail_page.dart';
import '../../features/requests/presentation/pages/requests_page.dart';
import '../../features/requests/presentation/pages/review_request_page.dart';
import '../../features/requests/presentation/pages/select_service_page.dart';
import '../localization/app_localizations.dart';
import '../shell/app_shell.dart';
import 'app_routes.dart';
import 'route_guards.dart';

/// Route table and the single place navigation is decided.
///
/// The redirect below is the app's only authorisation gate on the client, and
/// it exists for UX only: the backend independently enforces every permission,
/// so a tampered client gains nothing (§9).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootKey,
    // A location, not a route name: go_router parses this as a URL, and the
    // splash route lives at '/'.
    initialLocation: AppRoute.splash.path,
    refreshListenable: SessionListenable(ref),
    debugLogDiagnostics: false,
    // The redirect works in locations because go_router's top-level callback
    // never receives the matched route's name.
    redirect: (BuildContext context, GoRouterState state) =>
        resolveRedirect(ref.read(authProvider), state.matchedLocation),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.name,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding.path,
        name: AppRoute.onboarding.name,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoute.phoneEntry.path,
        name: AppRoute.phoneEntry.name,
        builder: (BuildContext context, GoRouterState state) =>
            const PhoneEntryScreen(),
      ),
      GoRoute(
        path: AppRoute.otpVerify.path,
        name: AppRoute.otpVerify.name,
        builder: (BuildContext context, GoRouterState state) =>
            const OtpVerifyScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) => AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.home.path,
                name: AppRoute.home.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.requests.path,
                name: AppRoute.requests.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const RequestsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.properties.path,
                name: AppRoute.properties.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const PropertiesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.support.path,
                name: AppRoute.support.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const SupportPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.profile.path,
                name: AppRoute.profile.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      // The wizard is five separate routes so the back button, deep links and
      // process death all behave like a normal stack. The step itself is owned
      // by `RequestWizardController`, and every page reads the same state, so
      // entering the wizard at step 3 still shows steps 1 and 2 answered.
      GoRoute(
        path: AppRoute.requestNew.path,
        name: AppRoute.requestNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const SelectServicePage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'details',
            name: AppRoute.requestDetails.name,
            parentNavigatorKey: rootKey,
            builder: (BuildContext context, GoRouterState state) =>
                const ProblemDetailsPage(),
          ),
          GoRoute(
            path: 'photos',
            name: AppRoute.requestPhotos.name,
            parentNavigatorKey: rootKey,
            builder: (BuildContext context, GoRouterState state) =>
                const PhotoAnnotationPage(),
          ),
          GoRoute(
            path: 'location',
            name: AppRoute.requestLocation.name,
            parentNavigatorKey: rootKey,
            builder: (BuildContext context, GoRouterState state) =>
                const LocationPage(),
          ),
          GoRoute(
            path: 'review',
            name: AppRoute.requestReview.name,
            parentNavigatorKey: rootKey,
            builder: (BuildContext context, GoRouterState state) =>
                const ReviewRequestPage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.requestDetail.path,
        name: AppRoute.requestDetail.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            RequestDetailPage(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: AppRoute.payment.path,
        name: AppRoute.payment.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) => PaymentPage(
          requestId: state.pathParameters['requestId']!,
          referenceCode: state.uri.queryParameters['reference'],
        ),
      ),
      GoRoute(
        path: AppRoute.conversationNew.path,
        name: AppRoute.conversationNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) {
          final String? requestId = state.uri.queryParameters['requestId'];
          return NewConversationPage(requestId: requestId);
        },
      ),
      GoRoute(
        path: AppRoute.complaintNew.path,
        name: AppRoute.complaintNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) {
          final String? requestId = state.uri.queryParameters['requestId'];
          return NewComplaintPage(requestId: requestId);
        },
      ),
      GoRoute(
        path: AppRoute.conversationMessages.path,
        name: AppRoute.conversationMessages.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            ConversationPage(
              conversationId: state.pathParameters['conversationId']!,
              subject: state.uri.queryParameters['subject'],
            ),
      ),
      GoRoute(
        path: AppRoute.reviews.path,
        name: AppRoute.reviews.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const ReviewsPage(),
      ),
      GoRoute(
        path: AppRoute.notifications.path,
        name: AppRoute.notifications.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const NotificationsPage(),
      ),
      GoRoute(
        path: AppRoute.profileEdit.path,
        name: AppRoute.profileEdit.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const EditProfilePage(),
      ),
      GoRoute(
        path: AppRoute.rateService.path,
        name: AppRoute.rateService.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            RateServicePage(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: AppRoute.orders.path,
        name: AppRoute.orders.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const OrdersPage(),
      ),
      GoRoute(
        path: AppRoute.orderTracking.path,
        name: AppRoute.orderTracking.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            OrderTrackingPage(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: AppRoute.propertyNew.path,
        name: AppRoute.propertyNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const PropertyNewPage(),
      ),
      GoRoute(
        path: AppRoute.propertyDetail.path,
        name: AppRoute.propertyDetail.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            PropertyDetailPage(propertyId: state.pathParameters['propertyId']!),
      ),
      GoRoute(
        path: AppRoute.propertyHistory.path,
        name: AppRoute.propertyHistory.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            PropertyHistoryPage(
              propertyId: state.pathParameters['propertyId']!,
            ),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.commonSomethingWentWrong,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
});
