import 'package:flutter/services.dart';

/// Centralized haptic feedback patterns for premium micro-interactions.
class AppHaptics {
  AppHaptics._();

  static Future<void> light() => HapticFeedback.lightImpact();

  static Future<void> medium() => HapticFeedback.mediumImpact();

  static Future<void> heavy() => HapticFeedback.heavyImpact();

  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Short burst for success moments (unlock, seal complete).
  static Future<void> successBurst() async {
    await heavy();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await medium();
  }

  /// Record start/stop, seal, share copy.
  static Future<void> action() => medium();

  /// Countdown reached zero.
  static Future<void> countdownComplete() async {
    await medium();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await heavy();
  }
}
