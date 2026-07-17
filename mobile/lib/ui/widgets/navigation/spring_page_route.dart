import 'package:flutter/material.dart';

/// Lightweight page transition used across the app.
///
/// Kept short and fade-only so the route can snapshot the outgoing page and
/// avoid rebuilding heavy trees (Home header, Vault map) mid-animation —
/// the main source of Home ↔ Vault micro-stutters.
class SpringPageRoute<T> extends PageRouteBuilder<T> {
  SpringPageRoute({
    required Widget page,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          opaque: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(opacity: curved, child: child);
          },
        );

  @override
  bool get allowSnapshotting => true;

  @override
  bool get maintainState => true;
}
