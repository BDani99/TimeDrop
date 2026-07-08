import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
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
    required this.videoBytes,
    required this.mimeType,
    required this.durationMs,
  });

  final Uint8List videoBytes;
  final String mimeType;
  final int durationMs;

  @override
  State<CapsuleConfigScreen> createState() => _CapsuleConfigScreenState();
}

class _CapsuleConfigScreenState extends State<CapsuleConfigScreen> {
  Position? _position;
  bool _isLoadingLocation = true;
  DateTime? _unlockTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocation());
  }

  Future<void> _loadLocation() async {
    try {
      final position = await GeolocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _position = position;
        _isLoadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
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
      final info = await capsuleProvider.createCapsule(
        mediaBytes: widget.videoBytes,
        mimeType: widget.mimeType,
        durationMs: widget.durationMs,
        latitude: position.latitude,
        longitude: position.longitude,
        unlockTime: unlockTime,
        creatorId: userId,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ShareScreen(shareId: info.shareId, encryptionKey: info.encryptionKey),
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
                child: _isLoadingLocation || _position == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
