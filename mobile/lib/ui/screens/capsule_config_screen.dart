import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

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
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
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
    super.dispose();
  }

  void _prefillName() {
    final saved = context.read<SettingsProvider>().displayName;
    final linked = context.read<AuthProvider>().user?.userMetadata?['full_name'] as String?;
    final prefill = (saved != null && saved.isNotEmpty) ? saved : (linked ?? '');
    if (prefill.isNotEmpty) _nameController.text = prefill;
  }

  Future<void> _pickPhotos() async {
    if (_photoPaths.length >= AppConstants.maxCapsulePhotos) return;
    try {
      final picked = await ImagePicker().pickMultiImage(limit: AppConstants.maxCapsulePhotos);
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

  Future<void> _seal() async {
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
    final capsuleProvider = context.read<CapsuleProvider>();
    final authProvider = context.read<AuthProvider>();

    try {
      paymentProvider.requireCanCreateCapsule(freeDropUsed: settingsProvider.freeDropUsed);
    } on PaymentException {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    try {
      final userId = authProvider.userId;
      if (userId == null) {
        throw const AuthException('You need to be signed in to create a memory.');
      }
      // Persist the name so it prefills next time and always feeds ?from=.
      if (settingsProvider.displayName != name) {
        await settingsProvider.setDisplayName(userId, name);
      }
      final info = await capsuleProvider.reserveCapsule(
        mediaPath: widget.videoPath,
        mimeType: widget.mimeType,
        durationMs: widget.durationMs,
        photoPaths: List<String>.from(_photoPaths),
        note: _noteController.text,
        coverPhotoIndex: _coverPhotoIndex,
        latitude: position.latitude,
        longitude: position.longitude,
        unlockTime: unlockTime,
        creatorId: userId,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ShareScreen(
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$mo-$d at $h:$m';
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
            Text('Where to hide it', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _isLoadingLocation
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _position == null
                        ? _LocationErrorRetry(error: _locationError, onRetry: _loadLocation)
                        : FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(_position!.latitude, _position!.longitude),
                          initialZoom: 16,
                          interactionOptions:
                              const InteractionOptions(flags: InteractiveFlag.none),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.timedrop.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(_position!.latitude, _position!.longitude),
                                child: const Icon(
                                  Icons.location_pin,
                                  color: AppColors.primary,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
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
              onAdd: _pickPhotos,
              onRemove: _removePhoto,
              onSetCover: _setCover,
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Seal this Moment',
              isLoading: isCreating,
              onPressed: _seal,
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
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.smRadius,
                        border: Border.all(
                          color: coverIndex == i ? AppColors.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadii.smRadius,
                        child: Image.file(File(paths[i]), width: 88, height: 88, fit: BoxFit.cover),
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
