import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/payment_models.dart';

/// Payment, deposit and refund reads and writes for one request.
class PaymentsRemoteDataSource {
  const PaymentsRemoteDataSource(this._client);

  final ApiClient _client;

  /// The single call the Payment screen renders from: totals, deposit, payments,
  /// the offered methods and the finance instructions all arrive together.
  Future<PaymentView> view(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.requestPayment(requestId),
    );
    return PaymentView.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<PaymentRecord>> payments(String requestId) async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.requestPayments(requestId),
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(PaymentRecord.fromJson)
        .toList(growable: false);
  }

  Future<List<RefundRecord>> refunds(String requestId) async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.requestRefunds(requestId),
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(RefundRecord.fromJson)
        .toList(growable: false);
  }

  /// The method catalogue, which is what tells the app whether a receipt is
  /// expected for the chosen method.
  Future<List<PaymentMethodOption>> paymentMethods() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.paymentMethods,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(PaymentMethodOption.fromJson)
        .toList(growable: false);
  }

  /// Submits payment evidence. The response is never treated as verified: the
  /// backend only marks that once finance has looked at it.
  Future<PaymentRecord> submit({
    required String requestId,
    required String method,
    required double amount,
    String? referenceNumber,
    required bool isDeposit,
    required String idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.requestPayments(requestId),
      data: <String, dynamic>{
        'method': method,
        'amount': amount,
        if (referenceNumber != null && referenceNumber.isNotEmpty)
          'reference_number': referenceNumber,
        'is_deposit': isDeposit,
        // A double-tap or a retried request must not become two payments.
        'idempotency_key': idempotencyKey,
      },
    );
    return PaymentRecord.fromJson(response.data ?? const <String, dynamic>{});
  }

  /// Attaches the receipt image to an already-submitted payment.
  Future<void> uploadProof({
    required String requestId,
    required String paymentId,
    required String filePath,
    required String fileName,
  }) async {
    await _client.upload(
      ApiEndpoints.paymentProof(requestId, paymentId),
      formData: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      }),
    );
  }
}

final Provider<PaymentsRemoteDataSource> paymentsRemoteDataSourceProvider =
    Provider<PaymentsRemoteDataSource>(
      (Ref ref) => PaymentsRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'paymentsRemoteDataSource',
    );
