import 'package:flutter/material.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/theme/app_colors.dart';

/// Central error/success feedback helper — the cross-cutting rule in
/// terv.md §6 requires every caught async error to surface via a SnackBar,
/// so all call sites should go through this instead of building their own.
class AppSnackbar {
  AppSnackbar._();

  static void showError(BuildContext context, Object error) {
    _show(
      context,
      message: mapErrorToMessage(error),
      backgroundColor: AppColors.error,
      textColor: AppColors.onError,
    );
  }

  static void showMessage(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.inverseSurface,
      textColor: AppColors.inverseOnSurface,
    );
  }

  static void showSuccess(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.primary,
      textColor: AppColors.onPrimary,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required Color textColor,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: textColor)),
          backgroundColor: backgroundColor,
        ),
      );
  }
}
