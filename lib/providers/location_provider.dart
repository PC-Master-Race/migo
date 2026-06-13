// location_provider.dart — Riverpod state for GPS position and speed.
// One file per domain, per the repo structure.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

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
