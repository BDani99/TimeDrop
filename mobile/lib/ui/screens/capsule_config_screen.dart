import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/config/system_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/utils/date_format_helper.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/glass/glass_bottom_sheet.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/rituals/seal_ritual_overlay.dart';
import '../widgets/primary_button.dart';
import 'paywall_screen.dart';
import 'share_screen.dart';

/// "Where to hide it" / "When to open it" configuration screen shown right
/// after recording. Captures the current GPS position for the pin and lets
/// the user pick a future unlock time, then hands off to
/// `CapsuleProvider.createCapsule`.
class CapsuleConfigScreen extends StatefulWidget {
  const CapsuleConfigScreen({
    super.key,
    required this.videoPath,
    required this.mimeType,
    required this.durationMs,
  });

  final String videoPath;
  final String mimeType;
  final int durationMs;

  @override
  State<CapsuleConfigScreen> createState() => _CapsuleConfigScreenState();
}

class _CapsuleConfigScreenState extends State<CapsuleConfigScreen> {
  Position? _position;
  bool _isLoadingLocation = true;
  Object? _locationError;

  /// The location where the capsule will actually be hidden. Seeded from GPS
  /// but refined as the user pans the map under the fixed centre pin.
  LatLng? _selectedLatLng;
  final _mapController = MapController();
  bool _mapEditing = false;
  DateTime? _unlockTime;
  final _noteController = TextEditingController();
  final _nameController = TextEditingController();
  final List<String> _photoPaths = [];
  int? _coverPhotoIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocation();
      _prefillName();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _prefillName() {
    final saved = context.read<SettingsProvider>().displayName;
    final linked = context.read<AuthProvider>().user?.userMetadata?['full_name'] as String?;
    final prefill = (saved != null && saved.isNotEmpty) ? saved : (linked ?? '');
    if (prefill.isNotEmpty) _nameController.text = prefill;
  }

  Future<void> _addPhoto() async {
    if (_photoPaths.length >= AppConstants.maxCapsulePhotos) return;
    final source = await GlassBottomSheet.show<ImageSource>(
      context: context,
      builder: (_) => const _PhotoSourceSheet(),
    );
    if (source == null) return;
    // Taking a photo is the primary path; the gallery is the secondary option.
    if (source == ImageSource.camera) {
      await _captureFromCamera();
    } else {
      await _pickFromGallery();
    }
  }

  Future<void> _captureFromCamera() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null || !mounted) return;
      setState(() {
        if (_photoPaths.length < AppConstants.maxCapsulePhotos) {
          _photoPaths.add(image.path);
        }
        _coverPhotoIndex ??= 0;
      });
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final remaining = AppConstants.maxCapsulePhotos - _photoPaths.length;
      if (remaining <= 0) return;
      final picked = await ImagePicker().pickMultiImage(limit: remaining);
      if (picked.isEmpty || !mounted) return;
      setState(() {
        for (final image in picked) {
          if (_photoPaths.length < AppConstants.maxCapsulePhotos) {
            _photoPaths.add(image.path);
          }
        }
        // Default the cover to the first photo once any exist.
        _coverPhotoIndex ??= _photoPaths.isEmpty ? null : 0;
      });
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photoPaths.removeAt(index);
      if (_photoPaths.isEmpty) {
        _coverPhotoIndex = null;
      } else if (_coverPhotoIndex != null && _coverPhotoIndex! >= _photoPaths.length) {
        _coverPhotoIndex = _photoPaths.length - 1;
      }
    });
  }

  void _setCover(int index) {
    setState(() => _coverPhotoIndex = index);
  }

  Future<void> _loadLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });
    try {
      final position = await GeolocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _position = position;
        _selectedLatLng = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _locationError = e;
      });
      AppSnackbar.showError(context, e);
    }
  }

  Future<void> _pickUnlockTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!combined.isAfter(DateTime.now())) {
      AppSnackbar.showError(
        context,
        const CapsuleException('Please choose a time in the future.'),
      );
      return;
    }
    setState(() => _unlockTime = combined);
  }

  Future<void> _onSealPressed() async {
    final position = _position;
    final unlockTime = _unlockTime;
    if (position == null) {
      AppSnackbar.showError(
        context,
        const LocationException('Still finding your location — try again in a moment.'),
      );
      return;
    }
    if (unlockTime == null) {
      AppSnackbar.showError(
        context,
        const CapsuleException('Please choose when this memory should open.'),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppSnackbar.showError(
        context,
        const CapsuleException('Add your name so they know who it\'s from.'),
      );
      return;
    }

    final settingsProvider = context.read<SettingsProvider>();
    final paymentProvider = context.read<PaymentProvider>();
    try {
      paymentProvider.requireCanCreateCapsule(
        dropsUsed: settingsProvider.freeDropsUsed,
        freeDropLimit: SystemConfig.instance.freeDropLimit,
      );
    } on PaymentException {
      if (!mounted) return;
      Navigator.push(context, SpringPageRoute(page: const PaywallScreen()));
      return;
    }

    ImageProvider? preview;
    if (_coverPhotoIndex != null && _photoPaths.isNotEmpty) {
      preview = FileImage(File(_photoPaths[_coverPhotoIndex!]));
    }

    // Ritual first (no button spinner), then reserve + navigate — never stack
    // the overlay with the PrimaryButton loading state.
    await SealRitualOverlay.show(context, previewImage: preview);
    if (!mounted) return;
    await _seal();
  }

  Future<void> _seal() async {
    final position = _position;
    final unlockTime = _unlockTime;
    final chosen = _selectedLatLng ??
        (position == null ? null : LatLng(position.latitude, position.longitude));
    final name = _nameController.text.trim();

    final settingsProvider = context.read<SettingsProvider>();
    final capsuleProvider = context.read<CapsuleProvider>();
    final authProvider = context.read<AuthProvider>();

    // Capture before async gaps; navigate immediately after reserve so the
    // config screen's isCreating spinner never sits under ShareScreen.
    try {
      final userId = authProvider.userId;
      if (userId == null) {
        throw const AuthException('You need to be signed in to create a memory.');
      }
      if (settingsProvider.displayName != name) {
        await settingsProvider.setDisplayName(userId, name);
      }
      if (!mounted) return;
      final info = await capsuleProvider.reserveCapsule(
        mediaPath: widget.videoPath,
        mimeType: widget.mimeType,
        durationMs: widget.durationMs,
        photoPaths: List<String>.from(_photoPaths),
        note: _noteController.text,
        coverPhotoIndex: _coverPhotoIndex,
        latitude: chosen!.latitude,
        longitude: chosen.longitude,
        unlockTime: unlockTime!,
        creatorId: userId,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        SpringPageRoute(
          page: ShareScreen(
            shareId: info.shareId,
            encryptionKey: info.encryptionKey,
            fromName: name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    }
  }

  String _formatDateTime(DateTime dt) {
    final use24h = context.read<SettingsProvider>().use24HourTime;
    return formatCapsuleDateTime(dt, use24h: use24h);
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = context.watch<CapsuleProvider>().isCreating;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Seal this Moment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          children: [
            Row(
              children: [
                Expanded(child: Text('Where to hide it', style: AppTypography.headlineMd)),
                TextButton.icon(
                  onPressed: () => setState(() => _mapEditing = !_mapEditing),
                  icon: Icon(_mapEditing ? Icons.lock_open_outlined : Icons.edit_location_alt_outlined,
                      size: 18),
                  label: Text(_mapEditing ? 'Done' : 'Edit'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _isLoadingLocation
                    ? const Center(child: SkeletonBox(width: double.infinity, height: 220, borderRadius: 24))
                    : _position == null
                        ? _LocationErrorRetry(error: _locationError, onRetry: _loadLocation)
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _selectedLatLng ??
                                      LatLng(_position!.latitude, _position!.longitude),
                                  initialZoom: 16,
                                  interactionOptions: InteractionOptions(
                                    flags: _mapEditing
                                        ? InteractiveFlag.drag |
                                            InteractiveFlag.pinchZoom |
                                            InteractiveFlag.flingAnimation |
                                            InteractiveFlag.doubleTapZoom
                                        : InteractiveFlag.none,
                                  ),
                                  onPositionChanged: (camera, hasGesture) {
                                    if (hasGesture) _selectedLatLng = camera.center;
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                                    userAgentPackageName: 'com.timedrop.app',
                                    retinaMode: RetinaMode.isHighDensity(context),
                                  ),
                                ],
                              ),
                              const IgnorePointer(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 40),
                                  child: Icon(
                                    Icons.location_pin,
                                    color: AppColors.primary,
                                    size: 40,
                                  ),
                                ),
                              ),
                              if (!_mapEditing)
                                Positioned.fill(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setState(() => _mapEditing = true),
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.edit_location_alt_outlined,
                                                    color: Colors.white, size: 16),
                                                SizedBox(width: 6),
                                                Text('Tap to edit location',
                                                    style: TextStyle(color: Colors.white, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _mapEditing
                  ? 'Drag the map to move the pin, then tap Done.'
                  : 'Tap the map to change where this memory is hidden.',
              style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('When to open it', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _pickUnlockTime,
              child: Text(
                _unlockTime == null ? 'Choose a date & time' : _formatDateTime(_unlockTime!),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Letter to the future', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _noteController,
              maxLength: AppConstants.maxNoteLength,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Add a note (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Your name', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'So they know who it\'s from'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Photos', style: AppTypography.headlineMd),
            if (_photoPaths.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tap a photo to set it as the cover.',
                style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _PhotoStrip(
              paths: _photoPaths,
              coverIndex: _coverPhotoIndex,
              onAdd: _addPhoto,
              onRemove: _removePhoto,
              onSetCover: _setCover,
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Seal this Moment',
              isLoading: isCreating,
              onPressed: _onSealPressed,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the map when location couldn't be determined (denied
/// permission, disabled location services, etc.) — replaces what used to be
/// an indefinite spinner, since `_isLoadingLocation == false` with
/// `_position == null` means the fetch already failed, not that it's still
/// in flight.
class _LocationErrorRetry extends StatelessWidget {
  const _LocationErrorRetry({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, color: AppColors.onSurfaceVariant),
              const SizedBox(height: AppSpacing.xs),
              Text(
                error != null ? mapErrorToMessage(error!) : 'Couldn\'t get your location.',
                textAlign: TextAlign.center,
                style: AppTypography.labelMd,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
              // Covers the "already permanently denied" case, where
              // re-requesting the permission silently returns denied again
              // with no OS dialog — Settings is the only way out.
              TextButton(onPressed: openAppSettings, child: const Text('Open Settings')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for choosing how to attach a photo — taking one is the
/// primary action, the gallery is the secondary option. Returns the chosen
/// [ImageSource] (or null if dismissed).
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Add a photo', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.md),
            _PhotoSourceTile(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              subtitle: 'Capture the moment now',
              emphasized: true,
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PhotoSourceTile(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              subtitle: 'Pick an existing photo',
              emphasized: false,
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceTile extends StatelessWidget {
  const _PhotoSourceTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.emphasized,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = emphasized ? AppColors.onPrimary : AppColors.onSurface;
    final subFg = emphasized ? AppColors.onPrimary.withValues(alpha: 0.8) : AppColors.onSurfaceVariant;
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: emphasized ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: AppRadii.mdRadius,
          border: emphasized ? null : Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelMd.copyWith(color: fg)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.labelSm.copyWith(color: subFg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of attached photo thumbnails + an "add" tile (up to
/// [AppConstants.maxCapsulePhotos]). Tapping a thumbnail sets it as the
/// cover (star badge); each has a remove button.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.paths,
    required this.coverIndex,
    required this.onAdd,
    required this.onRemove,
    required this.onSetCover,
  });

  final List<String> paths;
  final int? coverIndex;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(int index) onSetCover;

  @override
  Widget build(BuildContext context) {
    final canAdd = paths.length < AppConstants.maxCapsulePhotos;
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < paths.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: GestureDetector(
                onTap: () => onSetCover(i),
                child: Stack(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.smRadius,
                        border: Border.all(
                          color: coverIndex == i ? AppColors.primary : Colors.transparent,
                          width: 3,
                        ),
                        image: DecorationImage(
                          image: FileImage(File(paths[i])),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (coverIndex == i)
                      const Positioned(
                        bottom: 4,
                        left: 4,
                        child: Icon(Icons.star, size: 18, color: AppColors.primary),
                      ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (canAdd)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: AppRadii.smRadius,
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: const Icon(Icons.add_a_photo_outlined, color: AppColors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
