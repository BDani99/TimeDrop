import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import 'app_snackbar.dart';
import 'glass/glass_bottom_sheet.dart';
import 'primary_button.dart';

/// Wraps any widget so that ten rapid taps reveal the store-reviewer passcode
/// sheet. Invisible and inert to everyone else — it renders [child] unchanged
/// and only reacts to a deliberate tap burst.
///
/// The passcode itself is never in the app: the sheet posts a candidate to a
/// server-side function that compares it against a salted hash, rate-limits to
/// five tries a day, and can be switched off remotely.
class HiddenReviewerTrigger extends StatefulWidget {
  const HiddenReviewerTrigger({super.key, required this.child});

  final Widget child;

  @override
  State<HiddenReviewerTrigger> createState() => _HiddenReviewerTriggerState();
}

class _HiddenReviewerTriggerState extends State<HiddenReviewerTrigger> {
  static const int _tapsRequired = 10;
  static const Duration _tapWindow = Duration(milliseconds: 800);

  int _taps = 0;
  DateTime? _lastTap;

  void _onTap() {
    final now = DateTime.now();
    // Any pause longer than the window restarts the count, so ordinary taps on
    // a headline can never accumulate into an unlock.
    if (_lastTap == null || now.difference(_lastTap!) > _tapWindow) {
      _taps = 1;
    } else {
      _taps++;
    }
    _lastTap = now;

    if (_taps < _tapsRequired) return;
    _taps = 0;
    HapticFeedback.mediumImpact();
    _openSheet();
  }

  Future<void> _openSheet() async {
    await GlassBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      // Not dismissible by tap or drag: the user's finger is still hammering
      // the screen from the unlock gesture. The X button is the way out.
      isDismissible: false,
      builder: (_) => const _ReviewerPasscodeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}

class _ReviewerPasscodeSheet extends StatefulWidget {
  const _ReviewerPasscodeSheet();

  @override
  State<_ReviewerPasscodeSheet> createState() => _ReviewerPasscodeSheetState();
}

class _ReviewerPasscodeSheetState extends State<_ReviewerPasscodeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final granted = await context.read<AuthProvider>().submitReviewerPasscode(code);
      if (!mounted) return;
      if (granted) {
        Navigator.of(context).pop();
        AppSnackbar.showSuccess(context, 'Reviewer access unlocked.');
      } else {
        setState(() {
          _busy = false;
          // Deliberately vague: a wrong code, a disabled switch and a
          // rate-limit lockout all look the same from here.
          _error = 'That passcode was not accepted.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Reviewer access', style: AppTypography.headlineMd),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter the passcode from the App Store Connect or Play Console '
            'review notes to unlock full access.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Passcode',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Unlock', isLoading: _busy, onPressed: _submit),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
