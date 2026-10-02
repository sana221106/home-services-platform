import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../../../app/router/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../properties/data/models/property_models.dart';
import '../../data/models/photo_annotation.dart';
import '../../data/models/request_models.dart';
import '../../data/repositories/requests_repository.dart';

/// The wizard steps, in order (spec screens 6-10).
enum RequestWizardStep { service, details, photos, location, review }

/// A photo the customer picked but has not uploaded yet.
///
/// The API only accepts media against an existing request id, so the wizard has
/// to create the draft before it can upload. These stay local until then.
class PendingPhoto extends Equatable {
  const PendingPhoto({
    required this.localId,
    required this.filename,
    required this.bytes,
    required this.contentType,
    this.annotations = const <PhotoAnnotation>[],
    this.uploaded,
  });

  /// Stable identity for list keys, since bytes have no id yet.
  final String localId;
  final String filename;
  final Uint8List bytes;
  final String contentType;

  /// Marks drawn over the photo, uploaded once the media has an id.
  final List<PhotoAnnotation> annotations;

  /// Set once the upload succeeds, so a retry can skip this file.
  final RequestMedia? uploaded;

  int get sizeBytes => bytes.length;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  PendingPhoto copyWith({
    List<PhotoAnnotation>? annotations,
    RequestMedia? uploaded,
  }) {
    return PendingPhoto(
      localId: localId,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
      annotations: annotations ?? this.annotations,
      uploaded: uploaded ?? this.uploaded,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    localId,
    filename,
    uploaded?.id,
    annotations,
  ];
}

enum WizardSubmitPhase { idle, creatingDraft, uploading, submitting, done }

class RequestWizardState extends Equatable {
  const RequestWizardState({
    this.step = RequestWizardStep.service,
    this.category,
    this.problemType,
    this.description = '',
    this.notes,
    this.urgency = 'NORMAL',
    this.inspectionOnly = false,
    this.property,
    this.address,
    this.photos = const <PendingPhoto>[],
    this.phase = WizardSubmitPhase.idle,
    this.errorMessage,
    this.createdRequestId,
  });

  final RequestWizardStep step;
  final ServiceCategory? category;
  final ProblemType? problemType;
  final String description;
  final String? notes;
  final String urgency;
  final bool inspectionOnly;
  final Property? property;
  final AddressSnapshot? address;
  final List<PendingPhoto> photos;
  final WizardSubmitPhase phase;
  final String? errorMessage;
  final String? createdRequestId;

  bool get isSubmitting =>
      phase != WizardSubmitPhase.idle && phase != WizardSubmitPhase.done;

  bool get isUrgent => urgency == 'URGENT';

  /// `POST /requests` validates `problem_description` at 10-4000 characters, so
  /// the button is gated on that rather than letting the server 422.
  bool get descriptionIsValid =>
      description.trim().length >= 10 && description.trim().length <= 4000;

  /// The backend rejects `inspection_only` together with `URGENT`, so choosing
  /// inspection-only silently downgrades urgency instead of failing at submit.
  String get effectiveUrgency =>
      inspectionOnly && urgency == 'URGENT' ? 'NORMAL' : urgency;

  /// Submitting needs at least one photo: `POST /requests/{id}/submit` returns
  /// 400 when `media_count == 0`.
  bool get photosSatisfySubmit => photos.isNotEmpty;

  bool get isLocationValid =>
      address != null && address!.isSubmittable && address!.contactPairIsValid;

  /// Whether the final submit button should be enabled.
  bool get canSubmit =>
      category != null &&
      property != null &&
      descriptionIsValid &&
      photosSatisfySubmit &&
      isLocationValid &&
      !isSubmitting;

  /// Why the submit button is disabled, so the review screen can explain itself
  /// instead of leaving a dead button.
  List<String> get blockers => <String>[
    if (category == null) 'service',
    if (property == null || !isLocationValid) 'location',
    if (!descriptionIsValid) 'details',
    if (!photosSatisfySubmit) 'photos',
  ];

  int get uploadedCount =>
      photos.where((PendingPhoto p) => p.uploaded != null).length;

  RequestWizardState copyWith({
    RequestWizardStep? step,
    ServiceCategory? category,
    ProblemType? problemType,
    String? description,
    String? notes,
    String? urgency,
    bool? inspectionOnly,
    Property? property,
    AddressSnapshot? address,
    List<PendingPhoto>? photos,
    WizardSubmitPhase? phase,
    String? errorMessage,
    String? createdRequestId,
    bool clearProblemType = false,
    bool clearError = false,
  }) {
    return RequestWizardState(
      step: step ?? this.step,
      category: category ?? this.category,
      problemType: clearProblemType ? null : (problemType ?? this.problemType),
      description: description ?? this.description,
      notes: notes ?? this.notes,
      urgency: urgency ?? this.urgency,
      inspectionOnly: inspectionOnly ?? this.inspectionOnly,
      property: property ?? this.property,
      address: address ?? this.address,
      photos: photos ?? this.photos,
      phase: phase ?? this.phase,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      createdRequestId: createdRequestId ?? this.createdRequestId,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    step,
    category,
    problemType,
    description,
    notes,
    urgency,
    inspectionOnly,
    property,
    address,
    photos,
    phase,
    errorMessage,
    createdRequestId,
  ];
}

/// Drives the five-step request wizard.
///
/// The whole wizard is one controller so a customer can move back and forth
/// between steps without losing what they already typed; per-step controllers
/// would each need their own persistence.
class RequestWizardController extends Notifier<RequestWizardState> {
  @override
  RequestWizardState build() => const RequestWizardState();

  void selectCategory(ServiceCategory category) {
    // Switching service invalidates the problem type: the backend rejects a
    // problem_type_id that belongs to a different category_id.
    state = state.copyWith(
      category: category,
      clearProblemType: true,
      // Prefill the description hint length expectation only; no copy here.
      inspectionOnly: category.requiresInspectionDefault
          ? true
          : state.inspectionOnly,
    );
  }

  void selectProblemType(ProblemType? problem) {
    state = state.copyWith(problemType: problem);
  }

  void setDescription(String value) {
    state = state.copyWith(description: value);
  }

  void setNotes(String? value) {
    state = state.copyWith(notes: value);
  }

  void setUrgency(String value) {
    state = state.copyWith(urgency: value);
  }

  void setInspectionOnly(bool value) {
    state = state.copyWith(inspectionOnly: value);
  }

  /// Selecting a property prefills the address snapshot.
  ///
  /// The API requires a full address on every request, so the wizard copies the
  /// property's fields and lets the customer adjust them on the location step.
  /// The primary contact seeds `contact_name`/`contact_phone`.
  void selectProperty(Property property) {
    final Iterable<PropertyContact> primaries = property.contacts.where(
      (PropertyContact c) => c.isPrimary,
    );
    // Fall back to the first contact when none is flagged primary, otherwise a
    // property saved without is_primary would produce an empty contact pair.
    final PropertyContact? contact = primaries.isNotEmpty
        ? primaries.first
        : (property.contacts.isNotEmpty ? property.contacts.first : null);

    state = state.copyWith(
      property: property,
      address: AddressSnapshot(
        governorate: property.governorate ?? '',
        city: property.city ?? '',
        latitude: property.latitude ?? 0,
        longitude: property.longitude ?? 0,
        zone: property.zone,
        district: property.district,
        street: property.street,
        building: property.building,
        floor: property.floor,
        apartment: property.apartment,
        landmark: property.landmark,
        contactName: contact?.name,
        contactPhone: contact?.phone,
      ),
    );
  }

  void updateAddress(AddressSnapshot address) {
    state = state.copyWith(address: address);
  }

  void addPhotos(List<PendingPhoto> incoming) {
    final List<PendingPhoto> next = <PendingPhoto>[...state.photos];
    for (final PendingPhoto photo in incoming) {
      if (next.length >= RequestMedia.maxPerRequest) break;
      next.add(photo);
    }
    state = state.copyWith(photos: next);
  }

  void removePhoto(String localId) {
    state = state.copyWith(
      photos: state.photos
          .where((PendingPhoto p) => p.localId != localId)
          .toList(growable: false),
    );
  }

  /// Replaces the marks on one pending photo. Annotations are held locally and
  /// uploaded after the media itself, because the endpoint needs a media id.
  void setPhotoAnnotations(String localId, List<PhotoAnnotation> annotations) {
    state = state.copyWith(
      photos: <PendingPhoto>[
        for (final PendingPhoto photo in state.photos)
          if (photo.localId == localId)
            photo.copyWith(annotations: annotations)
          else
            photo,
      ],
    );
  }

  /// Records the step the customer is on.
  ///
  /// Navigation itself is the router's job, so this deliberately does not push
  /// a route. The wizard pages call this alongside their own navigation, and
  /// keeping the two apart means the controller stays testable without a
  /// GoRouter and a mid-flow page rebuild cannot skip a step.
  void goToStep(RequestWizardStep step) {
    state = state.copyWith(step: step, clearError: true);
  }

  /// The route for each step, so navigation is not spelled out per page.
  static String routeFor(RequestWizardStep step) => switch (step) {
    RequestWizardStep.service => AppRoute.requestNew.name,
    RequestWizardStep.details => AppRoute.requestDetails.name,
    RequestWizardStep.photos => AppRoute.requestPhotos.name,
    RequestWizardStep.location => AppRoute.requestLocation.name,
    RequestWizardStep.review => AppRoute.requestReview.name,
  };

  /// Whether the customer may leave the current step forward.
  ///
  /// Checked client-side to avoid a guaranteed 422, not to replace server
  /// validation.
  bool canAdvance(RequestWizardStep from) => switch (from) {
    RequestWizardStep.service => state.category != null,
    RequestWizardStep.details => state.descriptionIsValid,
    // A photo is required to submit, so the step cannot be skipped.
    RequestWizardStep.photos => state.photosSatisfySubmit,
    RequestWizardStep.location => state.isLocationValid,
    RequestWizardStep.review => state.canSubmit,
  };

  /// Creates the draft, uploads the photos, then submits.
  ///
  /// Order matters and is enforced by the backend: a request must exist before
  /// media can be attached, and submitting without media returns 400. A partial
  /// failure is not rolled back, because the draft is resumable: the created id
  /// is kept so a retry reuses it instead of creating a second draft.
  Future<ServiceRequest?> submit() async {
    final category = state.category;
    final property = state.property;
    final address = state.address;
    if (category == null || property == null || address == null) {
      state = state.copyWith(
        errorMessage: 'The wizard is incomplete.',
        phase: WizardSubmitPhase.idle,
      );
      return null;
    }
    if (!state.canSubmit) {
      state = state.copyWith(
        errorMessage: 'Some required details are missing.',
      );
      return null;
    }

    final repository = ref.read(requestsRepositoryProvider);

    try {
      // 1. Draft, reusing the id if a previous attempt got this far.
      String requestId = state.createdRequestId ?? '';
      if (requestId.isEmpty) {
        state = state.copyWith(
          phase: WizardSubmitPhase.creatingDraft,
          clearError: true,
        );
        final ServiceRequest draft = await repository.createDraft(
          propertyId: property.id,
          categoryId: category.id,
          problemDescription: state.description.trim(),
          address: address,
          problemTypeId: state.problemType?.id,
          urgency: state.effectiveUrgency,
          inspectionOnly: state.inspectionOnly,
          customerNotes: state.notes,
          // A stable key means a retry after a timeout returns the same draft
          // rather than a duplicate.
          idempotencyKey: _idempotencyKey,
        );
        requestId = draft.id;
        state = state.copyWith(createdRequestId: requestId);
      }

      // 2. Photos, skipping any that already uploaded on a previous attempt.
      state = state.copyWith(phase: WizardSubmitPhase.uploading);
      final List<PendingPhoto> uploaded = <PendingPhoto>[];
      for (final PendingPhoto photo in state.photos) {
        if (photo.uploaded != null) {
          uploaded.add(photo);
          continue;
        }
        final RequestMedia media = await repository.uploadMedia(
          requestId: requestId,
          filename: photo.filename,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
        // Marks can only be attached once the media has an id.
        for (final PhotoAnnotation annotation in photo.annotations) {
          await repository.addAnnotation(
            requestId: requestId,
            mediaId: media.id,
            annotation: annotation,
          );
        }

        uploaded.add(
          PendingPhoto(
            localId: photo.localId,
            filename: photo.filename,
            bytes: photo.bytes,
            contentType: photo.contentType,
            annotations: photo.annotations,
            uploaded: media,
          ),
        );
        // Publish progress so a slow connection shows the photo landing.
        state = state.copyWith(
          photos: List<PendingPhoto>.unmodifiable(uploaded),
        );
      }

      // 3. Submit now that media exists.
      state = state.copyWith(phase: WizardSubmitPhase.submitting);
      final ServiceRequest submitted = await repository.submit(
        requestId,
        idempotencyKey: _idempotencyKey,
      );

      state = state.copyWith(
        phase: WizardSubmitPhase.done,
        photos: List<PendingPhoto>.unmodifiable(uploaded),
        createdRequestId: requestId,
        clearError: true,
      );
      return submitted;
    } on ApiFailure catch (failure) {
      // The draft id is preserved so [submit] can be retried without creating
      // a second request.
      state = state.copyWith(
        phase: WizardSubmitPhase.idle,
        errorMessage: failure.message,
      );
      return null;
    }
  }

  /// Stable for the lifetime of the wizard so retries de-duplicate server side.
  late final String _idempotencyKey =
      'wf-${DateTime.now().microsecondsSinceEpoch}';
}

final NotifierProvider<RequestWizardController, RequestWizardState>
requestWizardProvider =
    NotifierProvider<RequestWizardController, RequestWizardState>(
      RequestWizardController.new,
      name: 'requestWizard',
    );
