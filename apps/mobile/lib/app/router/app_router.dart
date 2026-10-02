import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_localizations.dart';

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
import '../../features/properties/presentation/pages/property_history_page.dart';
import '../../features/requests/presentation/pages/location_page.dart';
import '../../features/requests/presentation/pages/problem_details_page.dart';
import '../../features/requests/presentation/pages/photo_annotation_page.dart';
import '../../features/requests/presentation/pages/request_detail_page.dart';
import '../../features/requests/presentation/pages/requests_page.dart';
import '../../features/requests/presentation/pages/review_request_page.dart';
import '../../features/requests/presentation/pages/select_service_page.dart';
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
    initialLocation: AppRoute.splash.name,
    refreshListenable: SessionListenable(ref),
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) =>
        resolveRedirect(context, ref.read(authProvider), state.name ?? ''),
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: AppRoute.splash.name,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: AppRoute.onboarding.name,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        name: AppRoute.phoneEntry.name,
        builder: (BuildContext context, GoRouterState state) =>
            const PhoneEntryScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
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
                path: '/home',
                name: AppRoute.home.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/requests',
                name: AppRoute.requests.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const RequestsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/properties',
                name: AppRoute.properties.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const PropertiesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/support',
                name: AppRoute.support.name,
                builder: (BuildContext context, GoRouterState state) =>
                    const SupportPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                name: AppRoute.profile.name,
                builder: (BuildContext context, GoRouterState state) =>
                    ComingSoonScreen(title: context.l10n.profileTitle),
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
        path: '/requests/new',
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
        path: '/requests/:requestId',
        name: AppRoute.requestDetail.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            RequestDetailPage(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: '/requests/:requestId/payment',
        name: AppRoute.payment.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) => PaymentPage(
          requestId: state.pathParameters['requestId']!,
          referenceCode: state.uri.queryParameters['reference'],
        ),
      ),
      GoRoute(
        path: '/support/new',
        name: AppRoute.conversationNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) {
          final String? requestId = state.uri.queryParameters['requestId'];
          return NewConversationPage(requestId: requestId);
        },
      ),
      GoRoute(
        path: '/support/complaint/new',
        name: AppRoute.complaintNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) {
          final String? requestId = state.uri.queryParameters['requestId'];
          return NewComplaintPage(requestId: requestId);
        },
      ),
      GoRoute(
        path: '/support/conversation/:conversationId',
        name: AppRoute.conversationMessages.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            ConversationPage(
              conversationId: state.pathParameters['conversationId']!,
              subject: state.uri.queryParameters['subject'],
            ),
      ),
      GoRoute(
        path: '/orders',
        name: AppRoute.orders.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const OrdersPage(),
      ),
      GoRoute(
        path: '/orders/:requestId',
        name: AppRoute.orderTracking.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            OrderTrackingPage(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: '/properties/new',
        name: AppRoute.propertyNew.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const ComingSoonScreen(title: ''),
      ),
      GoRoute(
        path: '/properties/:propertyId',
        name: AppRoute.propertyDetail.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            const ComingSoonScreen(title: ''),
      ),
      GoRoute(
        path: '/properties/:propertyId/history',
        name: AppRoute.propertyHistory.name,
        parentNavigatorKey: rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            PropertyHistoryPage(
              propertyId: state.pathParameters['propertyId']!,
            ),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        Scaffold(body: Center(child: Text(state.uri.toString()))),
  );
});
