import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/constants/request_status.dart';

void main() {
  group('AppRequestStatus.fromCode', () {
    test('parses the wire codes the backend sends', () {
      expect(
        AppRequestStatus.fromCode('ON_THE_WAY'),
        AppRequestStatus.onTheWay,
      );
      expect(
        AppRequestStatus.fromCode('SERVICE_COMPLETED'),
        AppRequestStatus.serviceCompleted,
      );
      expect(
        AppRequestStatus.fromCode('AWAITING_CUSTOMER_APPROVAL'),
        AppRequestStatus.awaitingCustomerApproval,
      );
    });

    test('tolerates casing and padding', () {
      expect(
        AppRequestStatus.fromCode('  on_the_way '),
        AppRequestStatus.onTheWay,
      );
      expect(AppRequestStatus.fromCode('closed'), AppRequestStatus.closed);
    });

    test('returns null for a status the client does not know', () {
      expect(AppRequestStatus.fromCode('TELEPORTED'), isNull);
      expect(AppRequestStatus.fromCode(''), isNull);
      expect(AppRequestStatus.fromCode(null), isNull);
    });
  });

  group('code round trip', () {
    test('every enum member has a distinct wire code', () {
      final codes = AppRequestStatus.values.map((s) => s.code).toSet();
      expect(codes.length, AppRequestStatus.values.length);
    });

    test('every member is reachable by parsing its own code', () {
      for (final status in AppRequestStatus.values) {
        expect(AppRequestStatus.fromCode(status.code), status);
      }
    });
  });

  group('terminal states', () {
    test('only CLOSED and CANCELLED are terminal', () {
      expect(AppRequestStatus.closed.isTerminal, isTrue);
      expect(AppRequestStatus.cancelled.isTerminal, isTrue);
      // RESOLVED is deliberately NOT terminal: the backend still allows
      // RESOLVED -> CLOSED and RESOLVED -> REVISIT_SCHEDULED, so treating it
      // as final would hide a real action from the customer.
      expect(AppRequestStatus.resolved.isTerminal, isFalse);
      expect(AppRequestStatus.workInProgress.isTerminal, isFalse);
      expect(AppRequestStatus.quoteSent.isTerminal, isFalse);
    });

    test('terminal set matches the backend TERMINAL_REQUEST_STATUSES', () {
      final Set<AppRequestStatus> terminal = AppRequestStatus.values
          .where((AppRequestStatus s) => s.isTerminal)
          .toSet();
      expect(terminal, <AppRequestStatus>{
        AppRequestStatus.closed,
        AppRequestStatus.cancelled,
      });
    });

    // These mirrors exist only for optimistic rendering. The server publishes
    // can_cancel / can_rate / can_open_complaint on GET /orders/{id} and
    // enforces the same sets, so these must not drift from those lists.
    test('canCancelOptimistically matches backend CANCELLABLE_STATUSES', () {
      final Set<AppRequestStatus> cancellable = AppRequestStatus.values
          .where((AppRequestStatus s) => s.canCancelOptimistically)
          .toSet();
      expect(cancellable, <AppRequestStatus>{
        AppRequestStatus.draft,
        AppRequestStatus.submitted,
        AppRequestStatus.underReview,
        AppRequestStatus.needMoreInformation,
        AppRequestStatus.inspectionRequired,
        AppRequestStatus.inspectionScheduled,
        AppRequestStatus.quotePreparation,
        AppRequestStatus.quoteSent,
        AppRequestStatus.awaitingCustomerApproval,
        AppRequestStatus.depositPending,
        AppRequestStatus.depositVerification,
        AppRequestStatus.confirmed,
        AppRequestStatus.technicianAssignmentPending,
        AppRequestStatus.technicianAssigned,
        AppRequestStatus.onTheWay,
        AppRequestStatus.arrived,
      });
      // 16 statuses, and none of them may be terminal.
      expect(cancellable.length, 16);
      expect(cancellable.where((AppRequestStatus s) => s.isTerminal), isEmpty);
    });

    test('canRateOptimistically matches backend can_rate', () {
      final Set<AppRequestStatus> ratable = AppRequestStatus.values
          .where((AppRequestStatus s) => s.canRateOptimistically)
          .toSet();
      expect(ratable, <AppRequestStatus>{
        AppRequestStatus.paid,
        AppRequestStatus.awaitingRating,
      });
    });

    test('canComplainOptimistically matches backend can_open_complaint', () {
      final Set<AppRequestStatus> complainable = AppRequestStatus.values
          .where((AppRequestStatus s) => s.canComplainOptimistically)
          .toSet();
      expect(complainable, <AppRequestStatus>{
        AppRequestStatus.workInProgress,
        AppRequestStatus.serviceCompleted,
        AppRequestStatus.paymentPending,
        AppRequestStatus.paymentVerification,
        AppRequestStatus.paid,
        AppRequestStatus.awaitingRating,
        AppRequestStatus.closed,
      });
    });
  });

  group('tones', () {
    test('cancellation and complaints read as danger', () {
      expect(AppRequestStatus.cancelled.tone, StatusTone.danger);
      expect(AppRequestStatus.complaintOpen.tone, StatusTone.danger);
    });

    test('money and approval steps read as attention', () {
      expect(AppRequestStatus.quoteSent.tone, StatusTone.attention);
      expect(AppRequestStatus.depositPending.tone, StatusTone.attention);
    });

    test('completed work reads as success', () {
      expect(AppRequestStatus.serviceCompleted.tone, StatusTone.success);
      expect(AppRequestStatus.paid.tone, StatusTone.success);
    });
  });
}
