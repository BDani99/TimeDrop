import 'dart:async';

import 'package:flutter/widgets.dart';

/// Waits until the route containing [context] has finished animating in.
///
/// Three separate screens needed this and each had grown its own copy. The
/// reason is always the same: work scheduled in `initState` competes with the
/// incoming transition, and the transition is the thing the user is looking at.
/// Decoding thumbnails, attaching a video texture or raising the keyboard all
/// cost a visible stutter if they land mid-animation.
///
/// Returns immediately when there is no route animation, or when it has already
/// completed. [timeout] is a safety net for an interrupted transition whose
/// status never settles — without it the caller would wait forever.
Future<void> waitForRouteTransition(
  BuildContext context, {
  Duration timeout = const Duration(milliseconds: 400),
}) async {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.isCompleted) return;

  final done = Completer<void>();
  void listener(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (!done.isCompleted) done.complete();
    }
  }

  animation.addStatusListener(listener);
  try {
    await Future.any([done.future, Future<void>.delayed(timeout)]);
  } finally {
    animation.removeStatusListener(listener);
  }
}
