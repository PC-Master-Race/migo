// speed_limit_provider.dart — Riverpod state for the current road's speed
// limit, throttled so Overpass isn't hammered on every GPS tick.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/map_service.dart';
import 'location_provider.dart';

// --- LOCAL CONSTANTS ---

/// Minimum movement (meters) before a fresh Overpass speed-limit query runs.
/// 120 m ≈ a city block: limits rarely change more often, and this keeps the
/// public Overpass instance well within polite usage.
const double speedLimitRequeryDistanceMeters = 120;

// --- PROVIDERS ---

/// Display label for the current road's speed limit ("45" or "Unknown").
/// Re-queries only after the user has moved [speedLimitRequeryDistanceMeters].
final Provider<String> speedLimitLabelProvider = Provider<String>((Ref ref) {
  final AsyncValue<String> latestLookup = ref.watch(_speedLimitLookupProvider);
  return latestLookup.valueOrNull ?? speedLimitUnknownLabel;
});

/// Internal: tracks the last position a lookup ran for and performs the
/// throttled Overpass fetch.
final FutureProvider<String> _speedLimitLookupProvider =
    FutureProvider<String>((Ref ref) async {
  final Position? position =
      ref.watch(positionStreamProvider).valueOrNull;
  if (position == null) {
    return speedLimitUnknownLabel;
  }

  final LatLng currentPoint = LatLng(position.latitude, position.longitude);
  final LatLng? lastQueriedPoint = ref.read(_lastQueriedPointProvider);

  // Throttle: skip the network call until we've moved a block away.
  if (lastQueriedPoint != null) {
    const Distance geodesicDistance = Distance();
    final double movedMeters =
        geodesicDistance(lastQueriedPoint, currentPoint);
    if (movedMeters < speedLimitRequeryDistanceMeters) {
      return ref.read(_lastKnownLabelProvider);
    }
  }

  final String freshLabel =
      await MapService.fetchSpeedLimitLabelNear(currentPoint);
  ref.read(_lastQueriedPointProvider.notifier).state = currentPoint;
  ref.read(_lastKnownLabelProvider.notifier).state = freshLabel;
  return freshLabel;
});

/// Internal: where the last Overpass query was made.
final StateProvider<LatLng?> _lastQueriedPointProvider =
    StateProvider<LatLng?>((Ref ref) => null);

/// Internal: the last label returned, reused while inside the throttle radius.
final StateProvider<String> _lastKnownLabelProvider =
    StateProvider<String>((Ref ref) => speedLimitUnknownLabel);
