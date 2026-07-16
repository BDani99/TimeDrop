/// Distance-based motivational copy for the sci-fi radar experience.
class DistanceMotivation {
  DistanceMotivation._();

  static String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  static String messageFor(double? meters) {
    if (meters == null) return 'Locating the signal...';
    if (meters >= 5000) return 'The memory is far — but it\'s waiting for you.';
    if (meters >= 2000) return 'Keep going. Something precious is ahead.';
    if (meters >= 1000) return 'You are getting closer.';
    if (meters >= 500) return 'The signal is growing stronger.';
    if (meters >= 250) return 'Almost there. Follow the pulse.';
    if (meters >= 100) return 'So close you can feel it.';
    if (meters >= 50) return 'The moment is near.';
    return 'You\'ve found it.';
  }

  static String titleFor(double? meters, {required bool isClosing}) {
    if (isClosing) return 'You are getting closer...';
    if (meters != null && meters < 100) return 'The memory is within reach.';
    return 'Find the spot to unlock it.';
  }
}
