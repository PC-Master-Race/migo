// location_service.dart — GPS position, speed, and permission handling.
// Wraps geolocator behind one interface so platform details never leak into
// screens. Background-capable: stream settings request continued updates.

import 'package:geolocator/geolocator.dart';

import '../constants.dart';

// --- PLATFORM PARITY NOTE ---
// geolocator is cross-platform: the same calls work on Android and iOS.
// Background location requires per-platform manifest entries, NOT Dart code:
//   • Android: ACCESS_BACKGROUND_LOCATION + foregroundServiceType="location"
//   • iOS: UIBackgroundModes "location" + NSLocationAlwaysAndWhenInUse keys
// TODO: [add both manifest/plist entries after 'flutter create .' generates
// the platform folders] [deferred: platform folders don't exist yet — this
// is the iOS stub-parity obligation from PRODUCT_BRIEF]

// --- SERVICE ---

/// Provides the device's position stream and permission flow.
class LocationService {
  /// Requests location permission if not already granted.
  /// Returns true when the app may read location. Never nags: if the user
  /// permanently denied, this returns false and the map simply stays on the
  /// fallback center — privacy-first means location is optional too.
  Future<bool> ensurePermissionGranted() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Continuous position updates, at most every
  /// [locationDistanceFilterMeters] of movement. Each [Position] carries
  /// speed in meters/second — the HUD converts via gpsSpeedToDisplayMph.
  Stream<Position> positionStream() {
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: locationDistanceFilterMeters,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// One-shot current position for initial map centering, or null when
  /// permission is missing — callers fall back to the default center.
  Future<Position?> currentPositionOrNull() async {
    final bool allowed = await ensurePermissionGranted();
    if (!allowed) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }
}
