import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The app's single pill-shaped CTA button. `ElevatedButton` is already
/// pill-shaped + colored via [AppTheme], so this just adds a shared
/// loading/icon affordance so screens don't hand-roll spinner-vs-label logic.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onPrimary,
              ),
            )
          : icon == null
              ? Text(label)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                ),
    );
  }
}
