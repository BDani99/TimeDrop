import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_format_helper.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/clipboard_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/share_service.dart';
import '../../services/supabase_service.dart';
import '../../services/upload_queue_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/primary_button.dart';

/// Detail / re-share / meta-edit screen for a capsule the user created.
/// Media and the encrypted note are not editable (E2EE).
class SentCapsuleDetailScreen extends StatefulWidget {
  const SentCapsuleDetailScreen({super.key, required this.capsule});

  final CapsuleModel capsule;

  @override
  State<SentCapsuleDetailScreen> createState() => _SentCapsuleDetailScreenState();
}

class _SentCapsuleDetailScreenState extends State<SentCapsuleDetailScreen> {
  late CapsuleModel _capsule;
  late DateTime _unlockTime;
  late LatLng _pin;
  late final TextEditingController _nameController;
  final _mapController = MapController();
  String? _encryptionKey;
  bool _saving = false;
  bool _sharing = false;
  bool _mapEditing = false;

  @override
  void initState() {
    super.initState();
    _capsule = widget.capsule;
    _unlockTime = widget.capsule.unlockTime;
    _pin = LatLng(widget.capsule.latitude, widget.capsule.longitude);
    final settings = context.read<SettingsProvider>();
    _nameController = TextEditingController(text: settings.displayName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKey());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await UploadQueueService.keyFor(_capsule.id);
    if (!mounted) return;
    setState(() => _encryptionKey = key);
  }

  Future<void> _pickUnlockTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _unlockTime.isAfter(now) ? _unlockTime : now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_unlockTime),
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

  String _formatDateTime(DateTime dt) {
    final use24h = context.read<SettingsProvider>().use24HourTime;
    return formatCapsuleDateTime(dt, use24h: use24h);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppSnackbar.showError(
        context,
        const CapsuleException('Add your name so they know who it\'s from.'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().userId;
      if (userId == null) {
        throw const AuthException('You need to be signed in.');
      }
      final settings = context.read<SettingsProvider>();
      if (settings.displayName != name) {
        await settings.setDisplayName(userId, name);
      }

      String? city = _capsule.city;
      final moved = _pin.latitude != _capsule.latitude ||
          _pin.longitude != _capsule.longitude;
      if (moved) {
        city = await GeocodingService.cityFor(_pin.latitude, _pin.longitude);
      }

      await SupabaseService.updateSentCapsuleMeta(
        capsuleId: _capsule.id,
        unlockTime: _unlockTime,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        city: city,
      );

      if (!mounted) return;
      setState(() {
        _capsule = _capsule.copyWith(
          unlockTime: _unlockTime,
          latitude: _pin.latitude,
          longitude: _pin.longitude,
          city: city ?? _capsule.city,
        );
      });
      await AppHaptics.medium();
      if (mounted) AppSnackbar.showSuccess(context, 'Memory updated.');
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareAgain() async {
    final key = _encryptionKey;
    if (key == null) {
      AppSnackbar.showMessage(
        context,
        'The full link isn\'t on this device anymore — share the original message if you still have it. You can still copy the code below.',
      );
      return;
    }
    setState(() => _sharing = true);
    try {
      final url = ShareService.buildShareUrl(
        shareId: _capsule.shareId,
        encryptionKey: key,
        fromName: _nameController.text.trim(),
      );
      await ShareService.shareCapsuleLink(url);
      await AppHaptics.medium();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Once a drop is discoverable, editing stops being a UI nicety and starts
  /// being a way to move the ground under someone who may already be walking
  /// toward it — a change to the pin or the clock here can land while a
  /// recipient has the Radar open. The server enforces the same rule
  /// (migration 0033); this mirrors it rather than trusting the client alone.
  bool get _isLocked => _capsule.status == 'ready' && _capsule.isUnlocked;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (_capsule.status) {
      'pending' => 'Sealing…',
      'failed' => 'Upload failed',
      _ => _capsule.unlockTime.isAfter(DateTime.now())
          ? 'Waiting for them'
          : 'Ready for them to open',
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Your drop'),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [
          Text(
            _capsule.city?.isNotEmpty == true ? _capsule.city! : 'A hidden place',
            style: AppTypography.headlineLg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            statusLabel,
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassPanel(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _capsule.shareId,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMd.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: AppColors.primary),
                  onPressed: () async {
                    try {
                      await ClipboardService.copyToClipboard(_capsule.shareId);
                      await AppHaptics.medium();
                      if (context.mounted) {
                        AppSnackbar.showMessage(context, 'Code copied!');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppSnackbar.showError(context, e);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Share again',
            isLoading: _sharing,
            onPressed: _shareAgain,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_isLocked) ..._buildLockedDetails() else ..._buildEditableDetails(),
        ],
      ),
    );
  }

  /// Shown once the drop is discoverable: the same three facts, displayed
  /// rather than offered for editing, with a line explaining why. Silently
  /// removing the edit controls would read as a bug — this says outright that
  /// it is a deliberate, permanent state.
  List<Widget> _buildLockedDetails() {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.secondaryContainer,
          borderRadius: AppRadii.mdRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline,
                size: 20, color: AppColors.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This memory is already discoverable, so its time, place and '
                'your name are sealed — someone may already be on their way '
                'to it.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('From', style: AppTypography.headlineMd),
      const SizedBox(height: AppSpacing.sm),
      _ReadOnlyField(
        value: _nameController.text.trim().isEmpty
            ? 'Someone'
            : _nameController.text.trim(),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Opens at', style: AppTypography.headlineMd),
      const SizedBox(height: AppSpacing.sm),
      _ReadOnlyField(value: _formatDateTime(_unlockTime)),
      const SizedBox(height: AppSpacing.lg),
      Text('Hidden at', style: AppTypography.headlineMd),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: AppRadii.lgRadius,
        child: SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _pin,
                  initialZoom: 16,
                  // No onPositionChanged either: this map has nothing left to
                  // report, only to show.
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
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
            ],
          ),
        ),
      ),
    ];
  }

  /// The editable form, offered only before the drop has unlocked.
  List<Widget> _buildEditableDetails() {
    return [
      Text('From', style: AppTypography.headlineMd),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _nameController,
        style: AppTypography.bodyMd,
        decoration: InputDecoration(
          hintText: 'Your name',
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: AppRadii.mdRadius,
            borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdRadius,
            borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdRadius,
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Opens at', style: AppTypography.headlineMd),
      const SizedBox(height: AppSpacing.sm),
      Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdRadius,
          side: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: _pickUnlockTime,
          borderRadius: AppRadii.mdRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatDateTime(_unlockTime),
                    style: AppTypography.bodyMd,
                  ),
                ),
                const Icon(Icons.edit_calendar_outlined, color: AppColors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(child: Text('Hidden at', style: AppTypography.headlineMd)),
          TextButton.icon(
            onPressed: () => setState(() => _mapEditing = !_mapEditing),
            icon: Icon(_mapEditing ? Icons.lock_open_outlined : Icons.edit_location_alt_outlined,
                size: 18),
            label: Text(_mapEditing ? 'Done' : 'Edit'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: AppRadii.lgRadius,
        child: SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _pin,
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
                    if (!hasGesture) return;
                    setState(() => _pin = camera.center);
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
      const SizedBox(height: AppSpacing.xs),
      Text(
        _mapEditing
            ? 'Drag the map to move the pin, then tap Done.'
            : 'Tap the map to change where this memory is hidden.',
        style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(
        label: 'Save changes',
        isLoading: _saving,
        onPressed: _save,
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Video, photos, and the note stay sealed — only time, place, and your name can change.',
        textAlign: TextAlign.center,
        style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
      ),
    ];
  }
}

/// A field shown in place of an editable one, once editing is no longer
/// offered. Same box shape as the editable fields so the layout does not
/// jump between the two states — dimmer fill and muted text are the only
/// difference, which is what reads as "inert" rather than "broken".
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadii.mdRadius,
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(
        value,
        style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
      ),
    );
  }
}
