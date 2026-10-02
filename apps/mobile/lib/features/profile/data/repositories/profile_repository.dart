import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../datasources/profile_remote_data_source.dart';
import '../models/profile_models.dart';

/// Repository for the customer's account.
class ProfileRepository {
  ProfileRepository(this._profile, this._client);

  final ProfileRemoteDataSource _profile;
  final ApiClient _client;

  Future<ProfileDetails> profile() => _guard(_profile.profile);

  Future<ProfileDetails> update({
    String? fullName,
    String? email,
    String? preferredLanguage,
  }) => _guard(
    () => _profile.update(
      fullName: fullName,
      email: email,
      preferredLanguage: preferredLanguage,
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

final Provider<ProfileRemoteDataSource> profileRemoteDataSourceProvider =
    Provider<ProfileRemoteDataSource>(
      (Ref ref) => ProfileRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'profileRemoteDataSource',
    );

final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
      (Ref ref) => ProfileRepository(
        ref.watch(profileRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'profileRepository',
    );
