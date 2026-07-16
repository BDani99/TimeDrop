import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Frosted glass bottom sheet wrapper used app-wide.
class GlassBottomSheet {
  GlassBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest.withValues(alpha: 0.88),
                border: Border(
                  top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.containerMargin,
                      AppSpacing.sm,
                      AppSpacing.containerMargin,
                      AppSpacing.md,
                    ),
                    child: builder(ctx),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
