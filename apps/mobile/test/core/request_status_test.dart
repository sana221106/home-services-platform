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
    test('only finished states are terminal', () {
      expect(AppRequestStatus.closed.isTerminal, isTrue);
      expect(AppRequestStatus.cancelled.isTerminal, isTrue);
      expect(AppRequestStatus.resolved.isTerminal, isTrue);
      expect(AppRequestStatus.workInProgress.isTerminal, isFalse);
      expect(AppRequestStatus.quoteSent.isTerminal, isFalse);
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
