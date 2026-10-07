import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../auth/data/models/auth_models.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/models/profile_models.dart';
import '../../data/repositories/profile_repository.dart';

enum ProfileStatus { initial, loading, ready, failed }

class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.profile,
    this.errorMessage,
    this.isSaving = false,
    this.saved = false,
  });

  final ProfileStatus status;
  final ProfileDetails? profile;
  final String? errorMessage;
  final bool isSaving;

  /// Set once a save succeeds, so the form can close on the confirmation rather
  /// than on the request merely being sent.
  final bool saved;

  ProfileState copyWith({
    ProfileStatus? status,
    ProfileDetails? profile,
    String? errorMessage,
    bool? isSaving,
    bool? saved,
    bool clearError = false,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
      saved: saved ?? this.saved,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    profile,
    errorMessage,
    isSaving,
    saved,
  ];
}

/// Owns the account screen's profile and edits to it.
class ProfileController extends Notifier<ProfileState> {
  @override
  ProfileState build() => const ProfileState();

  Future<void> load() async {
    state = state.copyWith(status: ProfileStatus.loading, clearError: true);
    try {
      final ProfileDetails profile = await ref
          .read(profileRepositoryProvider)
          .profile();
      state = state.copyWith(status: ProfileStatus.ready, profile: profile);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: ProfileStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  /// Saves the editable fields, then mirrors the new name and email into the
  /// auth state so the home greeting cannot keep showing the old name.
  Future<bool> save({
    String? fullName,
    String? email,
    String? preferredLanguage,
  }) async {
    if (state.isSaving) return false;

    state = state.copyWith(isSaving: true, saved: false, clearError: true);
    try {
      final ProfileDetails profile = await ref
          .read(profileRepositoryProvider)
          .update(
            fullName: fullName,
            email: email,
            preferredLanguage: preferredLanguage,
          );
      state = state.copyWith(
        status: ProfileStatus.ready,
        profile: profile,
        isSaving: false,
        saved: true,
      );
      _mirrorToAuth(profile);
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return false;
    }
  }

  void acknowledgeSaved() {
    if (state.saved) state = state.copyWith(saved: false);
  }

  void _mirrorToAuth(ProfileDetails profile) {
    final CustomerProfile? current = ref.read(authProvider).customer;
    if (current == null) return;
    ref
        .read(authProvider.notifier)
        .applyCustomer(
          CustomerProfile(
            id: current.id,
            fullName: profile.fullName,
            // The profile endpoint sends an empty string for a customer who
            // never volunteered a number, which is not the same as having one.
            phone: profile.phone.isEmpty ? null : profile.phone,
            email: profile.email,
            avatarUrl: profile.avatarUrl,
            preferredLanguage: profile.preferredLanguage,
          ),
        );
  }
}

final NotifierProvider<ProfileController, ProfileState> profileProvider =
    NotifierProvider<ProfileController, ProfileState>(
      ProfileController.new,
      name: 'profile',
    );
