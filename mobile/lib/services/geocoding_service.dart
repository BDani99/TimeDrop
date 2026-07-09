import 'package:geocoding/geocoding.dart';

/// Reverse-geocodes a capsule's coordinates into a human city label for the
/// Vault cards. Best-effort: the native geocoder can fail (offline, no
/// result) — callers treat a null return as "no city, show name only".
class GeocodingService {
  GeocodingService._();

  static Future<String?> cityFor(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final city = p.locality?.trim();
      if (city != null && city.isNotEmpty) return city;
      // Fall back to a coarser administrative level if there's no locality.
      final area = p.subAdministrativeArea?.trim();
      if (area != null && area.isNotEmpty) return area;
      final admin = p.administrativeArea?.trim();
      if (admin != null && admin.isNotEmpty) return admin;
      return null;
    } catch (_) {
      return null;
    }
  }
}
