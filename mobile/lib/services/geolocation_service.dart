import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/errors/app_exception.dart';

/// Location permission checks + one-shot position capture (Sprint 1,
/// CapsuleConfigScreen) and continuous distance streaming (Sprint 2,
/// RadarScreen). Every screen that uses this MUST call
/// [ensurePermissionGranted] before loading, per the cross-cutting rule.
class GeolocationService {
  GeolocationService._();

  static Future<bool> ensurePermissionGranted() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  static Future<Position> getCurrentPosition() async {
    try {
      final granted = await ensurePermissionGranted();
      if (!granted) {
        throw const LocationException('Location permission is required to place a memory.');
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationException('Please enable location services.');
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException('Could not determine your location.', cause: e);
    }
  }

  /// Continuous position stream for the Radar UI. Caller owns the
  /// subscription and MUST cancel it in `dispose()`.
  static Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    );
  }

  static double distanceInMeters({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }
}
