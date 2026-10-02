import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/photo_annotation.dart';
import '../../data/models/request_models.dart';
import '../controllers/request_wizard_controller.dart';
import '../widgets/photo_annotation_editor.dart';
import '../widgets/request_wizard_scaffold.dart';
import '../widgets/wizard_navigation.dart';

/// Wizard step 3 of 5 (spec screen 8): attach and annotate photos.
///
/// A photo is mandatory, because `POST /requests/{id}/submit` returns 400 when
/// `media_count` is 0. That rule is enforced here so the customer is told
/// before submitting rather than after.
///
/// Picking happens through [ImagePicker]; the images are held as bytes in the
/// wizard controller because the API only accepts media against an existing
/// request id, so upload has to wait until the draft is created.
class PhotoAnnotationPage extends ConsumerStatefulWidget {
  const PhotoAnnotationPage({super.key});

  @override
  ConsumerState<PhotoAnnotationPage> createState() =>
      _PhotoAnnotationPageState();
}

class _PhotoAnnotationPageState extends ConsumerState<PhotoAnnotationPage> {
  final ImagePicker _picker = ImagePicker();
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final RequestWizardState wizard = ref.watch(requestWizardProvider);
    final RequestWizardController controller = ref.read(
      requestWizardProvider.notifier,
    );
    final int remaining = RequestMedia.maxPerRequest - wizard.photos.length;

    return RequestWizardScaffold(
      step: RequestWizardStep.photos,
      onBack: () =>
          wizardGoBack(context, controller, RequestWizardStep.details),
      nextEnabled: wizard.photosSatisfySubmit,
      onNext: () =>
          wizardGoNext(context, controller, RequestWizardStep.location),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: l10n.requestsPhotosTitle,
            actionLabel: l10n.requestsPhotosCount(
              wizard.photos.length,
              RequestMedia.maxPerRequest,
            ),
          ),
          Text(
            l10n.requestsPhotosHintSize,
            style: context.text.caption.copyWith(
              color: AppColors.of(context).textSecondary,
            ),
          ),

          if (!wizard.photosSatisfySubmit) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppChip(
              label: l10n.requestsPhotosRequired,
              icon: 'assets/icons/alert.svg',
              color: AppColors.of(context).warning,
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          if (remaining <= 0)
            AppChip(
              label: l10n.requestsPhotosLimit(RequestMedia.maxPerRequest),
              color: AppColors.of(context).textSecondary,
            )
          else
            _AddPhotoButton(
              enabled: !_picking && remaining > 0,
              onPressed: _pick,
            ),

          const SizedBox(height: AppSpacing.md),
          if (wizard.photos.isEmpty)
            EmptyState(
              title: l10n.requestsPhotosTitle,
              body: l10n.requestsPhotosHint,
              icon: 'assets/icons/camera.svg',
            )
          else
            _PhotoGrid(
              photos: wizard.photos,
              onRemove: (String id) => controller.removePhoto(id),
              onAnnotate: _openEditor,
            ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        // The backend sniffs the real format from magic bytes, but asking for
        // a bounded image keeps uploads on a mobile connection reasonable.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked.isEmpty) return;

      final List<PendingPhoto> accepted = <PendingPhoto>[];
      for (final XFile file in picked) {
        final int length = await file.length();
        if (length > RequestMedia.maxBytes) continue;
        accepted.add(
          PendingPhoto(
            localId: '${file.name}-${DateTime.now().microsecondsSinceEpoch}',
            filename: _safeFilename(file.name),
            bytes: await file.readAsBytes(),
            contentType: _contentTypeFor(file.name),
          ),
        );
      }

      if (!mounted) return;
      if (accepted.isEmpty) {
        _toast(context, context.l10n.requestsPhotosHintSize);
        return;
      }
      ref.read(requestWizardProvider.notifier).addPhotos(accepted);
    } on PlatformException catch (error) {
      if (!mounted) return;
      _toast(context, error.message ?? context.l10n.commonSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Opens the mark-up editor and stores the result on the pending photo.
  Future<void> _openEditor(PendingPhoto photo) async {
    final List<PhotoAnnotation>? result =
        await showDialog<List<PhotoAnnotation>>(
          context: context,
          barrierColor: Colors.black,
          builder: (BuildContext dialogContext) => PhotoAnnotationEditor(
            bytes: photo.bytes,
            initial: photo.annotations,
          ),
        );
    if (result == null || !mounted) return;
    ref
        .read(requestWizardProvider.notifier)
        .setPhotoAnnotations(photo.localId, result);
  }

  /// The backend matches the filename extension against the sniffed format, so
  /// an extensionless or mismatched name is rejected on upload.
  static String _safeFilename(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return name;
    }
    return '$name.jpg';
  }

  static String _contentTypeFor(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? colors.primary : colors.border,
            style: BorderStyle.solid,
          ),
          color: enabled ? colors.primarySoft : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.add_a_photo_outlined,
              size: 20,
              color: enabled ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              context.l10n.requestsPhotosAdd,
              style: context.text.label.copyWith(
                color: enabled ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.photos,
    required this.onRemove,
    required this.onAnnotate,
  });

  final List<PendingPhoto> photos;
  final ValueChanged<String> onRemove;
  final ValueChanged<PendingPhoto> onAnnotate;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: photos.length,
      itemBuilder: (BuildContext context, int index) {
        final PendingPhoto photo = photos[index];
        return _PhotoTile(
          key: Key('request-photo-${photo.localId}'),
          photo: photo,
          onRemove: () => onRemove(photo.localId),
          onAnnotate: () => onAnnotate(photo),
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.onRemove,
    required this.onAnnotate,
    super.key,
  });

  final PendingPhoto photo;
  final VoidCallback onRemove;
  final VoidCallback onAnnotate;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            onTap: onAnnotate,
            child: Image.memory(photo.bytes, fit: BoxFit.cover),
          ),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
          PositionedDirectional(
            top: 2,
            start: 2,
            child: GestureDetector(
              onTap: onAnnotate,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.brush_outlined,
                  size: 14,
                  color: photo.annotations.isEmpty
                      ? Colors.white
                      : colors.primary,
                ),
              ),
            ),
          ),
          if (photo.annotations.isNotEmpty)
            PositionedDirectional(
              bottom: 2,
              end: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${photo.annotations.length}',
                  style: context.text.caption.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          PositionedDirectional(
            bottom: 2,
            start: 4,
            child: Text(
              photo.sizeLabel,
              style: context.text.caption.copyWith(
                color: Colors.white,
                fontSize: 10,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
