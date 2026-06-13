// route_model.dart — A calculated route plus the preference toggles that
// produced it. Mirrors no single table; routes are computed client-side by
// routing_service.dart (Phase 2) and only summaries are ever persisted.

import 'package:latlong2/latlong.dart';

// --- ROUTE PREFERENCES ---

/// Every route option the user can toggle, all changeable mid-route
/// (PRODUCT_BRIEF Phase 2: any change triggers instant recalculation).
class RoutePreferences {
  /// Creates a preference set. Defaults match PRODUCT_BRIEF: fastest route,
  /// everything else off, ALPR avoidance off by default.
  const RoutePreferences({
    this.optimizeFor = RouteOptimization.fastest,
    this.avoidFreeways = false,
    this.avoidTolls = false,
    this.avoidPopularRoutes = false,
    this.avoidAlprCameras = false,
  });

  /// The primary optimization target (fastest, shortest, etc.).
  final RouteOptimization optimizeFor;

  /// Avoid freeways entirely.
  final bool avoidFreeways;

  /// Avoid toll roads.
  final bool avoidTolls;

  /// Deprioritize high-traffic corridors favored by Google/Waze.
  final bool avoidPopularRoutes;

  /// Route around known ALPR camera locations. Off by default.
  final bool avoidAlprCameras;
}

/// Primary optimization targets — mutually exclusive, unlike the avoid flags.
enum RouteOptimization {
  /// Least travel time (default).
  fastest,

  /// Least distance.
  shortest,

  /// Least estimated fuel burn.
  mostFuelEfficient,

  /// Fewest stops (lights, stop signs).
  fewestStops,
}

// --- MODEL ---

/// A computed route ready for turn-by-turn navigation.
class MigoRoute {
  /// Creates a route result.
  const MigoRoute({
    required this.waypoints,
    required this.distanceMeters,
    required this.estimatedSeconds,
    required this.preferencesUsed,
  });

  /// Ordered polyline of the route geometry.
  final List<LatLng> waypoints;

  /// Total route length in meters.
  final double distanceMeters;

  /// Estimated travel time in seconds.
  final double estimatedSeconds;

  /// The preference set that produced this route — kept so mid-route toggle
  /// changes can be diffed and trigger recalculation.
  final RoutePreferences preferencesUsed;
}

// TODO: [turn-by-turn instruction list model] [deferred to Phase 2 when the
// routing engine (OSRM vs Valhalla) is chosen — instruction formats differ]
