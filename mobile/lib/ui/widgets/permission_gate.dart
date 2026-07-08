import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'primary_button.dart';

enum _GateState { pending, granted, denied }

/// Cross-cutting rule (terv.md §6): `CameraScreen` and `RadarScreen` must run
/// a permission check and gate their content load on it *before* touching
/// the camera/location stream. This widget owns that check + retry UX so
/// both screens share one implementation.
class PermissionGate extends StatefulWidget {
  const PermissionGate({
    super.key,
    required this.requestPermission,
    required this.child,
    required this.deniedMessage,
  });

  /// Should request the OS permission and resolve to whether it was granted.
  final Future<bool> Function() requestPermission;
  final Widget child;
  final String deniedMessage;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  _GateState _state = _GateState.pending;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _state = _GateState.pending);
    final granted = await widget.requestPermission();
    if (!mounted) return;
    setState(() => _state = granted ? _GateState.granted : _GateState.denied);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.pending:
        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
      case _GateState.granted:
        return widget.child;
      case _GateState.denied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.deniedMessage,
                  style: AppTypography.bodyMd,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'Try Again', onPressed: _check),
              ],
            ),
          ),
        );
    }
  }
}
