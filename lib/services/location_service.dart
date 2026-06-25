// location_service.dart — GPS position, speed, and permission handling.
// Wraps geolocator behind one interface so platform details never leak into
// screens. Background-capable: stream settings request continued updates.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../constants.dart';
import 'location_filter.dart';

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
  ///
  /// Raw fixes are passed through a [LocationKalmanFilter] so the lat/lng we
  /// emit is a smoothed, outlier-rejected coordinate line. Everything
  /// downstream (avatar, camera, speed-limit, family sharing) gets the clean
  /// version transparently.
  Stream<Position> positionStream() {
    final LocationSettings settings = _navigationLocationSettings();
    final LocationKalmanFilter filter = LocationKalmanFilter();
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((Position raw) {
      final List<double> smoothed = filter.process(
        raw.latitude,
        raw.longitude,
        raw.accuracy,
        raw.timestamp.millisecondsSinceEpoch,
      );
      return _withLatLng(raw, smoothed[0], smoothed[1]);
    });
  }

  /// Platform-specific, navigation-grade location settings: highest accuracy,
  /// no distance filter, and a ~1s time interval so fixes arrive steadily (like
  /// a turn-by-turn app). On Android we keep the Google fused provider
  /// (forceLocationManager: false); on Apple we use the automotive activity
  /// type so iOS optimizes for driving.
  LocationSettings _navigationLocationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: locationIntervalMs),
          forceLocationManager: false,
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );
    }
  }

  /// Returns a copy of [p] with its latitude/longitude replaced by the
  /// Kalman-smoothed values, preserving every other field (speed, heading,
  /// accuracy, timestamp, etc.).
  Position _withLatLng(Position p, double lat, double lng) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: p.timestamp,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      heading: p.heading,
      headingAccuracy: p.headingAccuracy,
      speed: p.speed,
      speedAccuracy: p.speedAccuracy,
      floor: p.floor,
      isMocked: p.isMocked,
    );
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
