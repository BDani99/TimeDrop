import 'package:flutter/material.dart';

/// Opaque, non-fading route for screens that host a [VideoPlayer] / platform
/// texture.
///
/// Fade / Opacity transitions and route snapshotting break Android video
/// surfaces (the texture never attaches, so playback appears stuck forever).
/// This route swaps instantly with no opacity animation.
class OpaquePageRoute<T> extends PageRouteBuilder<T> {
  OpaquePageRoute({
    required Widget page,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        );

  @override
  bool get allowSnapshotting => false;

  @override
  bool get maintainState => true;
}
