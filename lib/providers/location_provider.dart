// location_provider.dart — Riverpod state for GPS position and speed.
// One file per domain, per the repo structure.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../utils/speed_utils.dart';

// --- PROVIDERS ---

/// Singleton location service instance.
final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => LocationService());

/// Live GPS position stream. Emits nothing until permission is granted; the
/// UI handles the waiting state by staying on the fallback map center.
final StreamProvider<Position> positionStreamProvider =
    StreamProvider<Position>((Ref ref) async* {
  final LocationService locationService = ref.watch(locationServiceProvider);
  final bool allowed = await locationService.ensurePermissionGranted();
  if (!allowed) {
    return; // No permission: stream stays empty, map stays on fallback.
  }
  yield* locationService.positionStream();
});

/// The avatar's DISPLAYED position — snapped to the route and eased every
/// frame by SmoothUserMarkerLayer. The camera follows THIS (not the raw 1 Hz
/// fix stream) so map movement is continuous instead of jumping once per
/// second. Null until the first fix.
final StateProvider<LatLng?> displayedPositionProvider =
    StateProvider<LatLng?>((Ref ref) => null);

/// The avatar's smoothed heading (degrees, 0 = north), eased the same way as
/// the position so the heading-up camera rotates fluidly instead of snapping
/// on every fix. Road-snapped during navigation. Null before the first fix.
final StateProvider<double?> displayedHeadingProvider =
    StateProvider<double?>((Ref ref) => null);

/// Current display speed in whole mph, jitter-suppressed. 0 when stationary
/// or before the first GPS fix.
final Provider<int> displaySpeedMphProvider = Provider<int>((Ref ref) {
  final AsyncValue<Position> latestPosition =
      ref.watch(positionStreamProvider);
  final Position? position = latestPosition.valueOrNull;
  if (position == null) {
    return 0;
  }
  return gpsSpeedToDisplayMph(position.speed);
});
