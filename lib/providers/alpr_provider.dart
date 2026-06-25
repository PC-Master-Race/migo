// alpr_provider.dart — Riverpod state for ALPR camera locations.
//
// Surveillance data is shown only when the user opts in (the layer defaults
// off). Locations come from AlprService, which merges DeFlock/OSM-tagged
// cameras (Overpass) with community reports (Supabase). Fetches are throttled
// to a coarse grid so we don't hammer Overpass on every GPS tick.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/alpr_service.dart';
import 'location_provider.dart';

/// Singleton ALPR service. Also used by routing for avoidance.
final Provider<AlprService> alprServiceProvider =
    Provider<AlprService>((Ref ref) => AlprService());

/// Whether ALPR camera markers are shown on the map. OFF by default — the user
/// opts in (privacy-first: nothing surveillance-related appears unbidden).
final StateProvider<bool> alprLayerEnabledProvider =
    StateProvider<bool>((Ref ref) => false);

/// Coarse grid cell for the user's position. The ALPR fetch keys off this, so
/// it re-queries only when the user crosses into a new ~1.4-mile cell.
final Provider<String?> _alprCellProvider = Provider<String?>((Ref ref) {
  final dynamic pos = ref.watch(positionStreamProvider).valueOrNull;
  if (pos == null) return null;
  final int latCell = ((pos.latitude as double) / alprFetchGridDegrees).round();
  final int lonCell = ((pos.longitude as double) / alprFetchGridDegrees).round();
  return '$latCell,$lonCell';
});

/// ALPR camera locations near the user, for the MAP DISPLAY. Fetched only while
/// the layer is enabled, and only when the grid cell changes (on-demand).
final FutureProvider<List<LatLng>> nearbyAlprProvider =
    FutureProvider<List<LatLng>>((Ref ref) async {
  if (!ref.watch(alprLayerEnabledProvider)) return <LatLng>[];
  final String? cell = ref.watch(_alprCellProvider);
  if (cell == null) return <LatLng>[];

  final dynamic pos = ref.read(positionStreamProvider).valueOrNull;
  if (pos == null) return <LatLng>[];

  return ref.read(alprServiceProvider).fetchAllAlprLocations(
        LatLng(pos.latitude as double, pos.longitude as double),
      );
});
