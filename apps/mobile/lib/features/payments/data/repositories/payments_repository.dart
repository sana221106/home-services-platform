import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../datasources/payments_remote_data_source.dart';
import '../models/payment_models.dart';

/// Repository for the payment view, deposits, receipts and refunds.
class PaymentsRepository {
  PaymentsRepository(this._payments, this._client);

  final PaymentsRemoteDataSource _payments;
  final ApiClient _client;

  Future<PaymentView> view(String requestId) =>
      _guard(() => _payments.view(requestId));

  Future<List<PaymentRecord>> payments(String requestId) =>
      _guard(() => _payments.payments(requestId));

  Future<List<RefundRecord>> refunds(String requestId) =>
      _guard(() => _payments.refunds(requestId));

  Future<List<PaymentMethodOption>> paymentMethods() =>
      _guard(_payments.paymentMethods);

  Future<PaymentRecord> submit({
    required String requestId,
    required String method,
    required double amount,
    String? referenceNumber,
    required bool isDeposit,
    required String idempotencyKey,
  }) => _guard(
    () => _payments.submit(
      requestId: requestId,
      method: method,
      amount: amount,
      referenceNumber: referenceNumber,
      isDeposit: isDeposit,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<void> uploadProof({
    required String requestId,
    required String paymentId,
    required String filePath,
    required String fileName,
  }) => _guard(
    () => _payments.uploadProof(
      requestId: requestId,
      paymentId: paymentId,
      filePath: filePath,
      fileName: fileName,
    ),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiFailure {
      rethrow;
    } on DioException catch (error) {
      throw _client.translate(error);
    } catch (error) {
      throw ApiFailure(
        code: 'UNEXPECTED',
        message: 'حدث خطأ غير متوقع.',
        details: <String, String>{'reason': error.runtimeType.toString()},
      );
    }
  }
}

final Provider<PaymentsRepository> paymentsRepositoryProvider =
    Provider<PaymentsRepository>(
      (Ref ref) => PaymentsRepository(
        ref.watch(paymentsRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'paymentsRepository',
    );
