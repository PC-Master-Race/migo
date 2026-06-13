// route_model.dart — A calculated route, turn-by-turn steps, navigation state,
// and the preference toggles that produced it.
//
// Routing engine: Valhalla (see routing_service.dart for the full decision log).
// Valhalla returns maneuver types as integers (0–38); ManeuverType maps the
// subset Migo uses to a readable enum. Full type list in Valhalla docs at
// https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/

import 'package:latlong2/latlong.dart';

// --- ROUTE PREFERENCES ---

/// Every route option the user can toggle. Any change triggers instant
/// recalculation per PRODUCT_BRIEF Phase 2.
class RoutePreferences {
  /// Defaults: fastest route, all avoids off, ALPR avoidance off by default.
  const RoutePreferences({
    this.optimizeFor = RouteOptimization.fastest,
    this.avoidFreeways = false,
    this.avoidTolls = false,
    this.avoidPopularRoutes = false,
    this.avoidAlprCameras = false,
  });

  /// The primary optimization target (fastest, shortest, etc.).
  final RouteOptimization optimizeFor;

  /// Avoid freeways/motorways entirely.
  /// Mapped to Valhalla: use_highways = 0.0
  final bool avoidFreeways;

  /// Avoid toll roads.
  /// Mapped to Valhalla: use_tolls = 0.0
  final bool avoidTolls;

  /// Prefer surface streets over high-traffic arterials. Approximated via
  /// Valhalla's use_highways = 0.1 (strong but not total highway avoidance).
  /// NOTE: Valhalla has no "avoid popular routes" concept directly — this is
  /// the closest approximation. A production version could weight by live
  /// traffic density once a traffic data source is integrated.
  final bool avoidPopularRoutes;

  /// Route around known ALPR camera locations.
  /// Implemented via Valhalla exclude_polygons: small circles around each
  /// validated ALPR location fetched from Supabase. Off by default per spec.
  final bool avoidAlprCameras;

  /// Returns a copy of these preferences with the given fields overridden.
  RoutePreferences copyWith({
    RouteOptimization? optimizeFor,
    bool? avoidFreeways,
    bool? avoidTolls,
    bool? avoidPopularRoutes,
    bool? avoidAlprCameras,
  }) {
    return RoutePreferences(
      optimizeFor: optimizeFor ?? this.optimizeFor,
      avoidFreeways: avoidFreeways ?? this.avoidFreeways,
      avoidTolls: avoidTolls ?? this.avoidTolls,
      avoidPopularRoutes: avoidPopularRoutes ?? this.avoidPopularRoutes,
      avoidAlprCameras: avoidAlprCameras ?? this.avoidAlprCameras,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoutePreferences &&
      other.optimizeFor == optimizeFor &&
      other.avoidFreeways == avoidFreeways &&
      other.avoidTolls == avoidTolls &&
      other.avoidPopularRoutes == avoidPopularRoutes &&
      other.avoidAlprCameras == avoidAlprCameras;

  @override
  int get hashCode => Object.hash(
        optimizeFor,
        avoidFreeways,
        avoidTolls,
        avoidPopularRoutes,
        avoidAlprCameras,
      );
}

/// Primary optimization target — mutually exclusive unlike the avoid flags.
enum RouteOptimization {
  /// Least travel time (default). Valhalla: standard auto costing.
  fastest,

  /// Least distance. Valhalla: costing_options.auto.shortest = true.
  shortest,

  /// Minimize estimated fuel burn. Approximated via Valhalla's auto costing
  /// with moderate highway use (steady speeds) and penalty on stop-and-go.
  /// NOTE: Valhalla has no dedicated fuel-efficiency model; this is a
  /// best-effort approximation.
  mostFuelEfficient,

  /// Favor roads with fewer intersections. Approximated via Valhalla's auto
  /// costing with elevated use_highways (highways have fewer stops/signals).
  fewestStops,
}

// --- MANEUVER ---

/// Subset of Valhalla maneuver types used in the turn-by-turn HUD.
/// Integer values match Valhalla's ManeuverType enum so they can be compared
/// directly to the `type` field in the API response.
enum ManeuverType {
  start(1),
  destination(4),
  continueStr(8),
  slightRight(9),
  right(10),
  sharpRight(11),
  uTurn(12),
  sharpLeft(14),
  left(15),
  slightLeft(16),
  rampRight(18),
  rampLeft(19),
  merge(25),
  roundaboutEnter(26),
  roundaboutExit(27),
  unknown(0);

  const ManeuverType(this.valhallaCode);
  final int valhallaCode;

  /// Returns the [ManeuverType] for a Valhalla type integer. Falls back to
  /// [unknown] for types Migo doesn't explicitly handle.
  static ManeuverType fromCode(int code) {
    return ManeuverType.values.firstWhere(
      (ManeuverType t) => t.valhallaCode == code,
      orElse: () => ManeuverType.unknown,
    );
  }
}

/// A single turn-by-turn step in the route.
class ManeuverStep {
  /// Creates a maneuver step.
  const ManeuverStep({
    required this.type,
    required this.instruction,
    required this.verbalInstruction,
    required this.distanceMiles,
    required this.durationSeconds,
    required this.shapeIndex,
    required this.streetNames,
  });

  /// The type of maneuver (turn direction, merge, roundabout, etc.).
  final ManeuverType type;

  /// Human-readable instruction shown in the banner, e.g. "Turn right onto
  /// Main St". Provided by Valhalla.
  final String instruction;

  /// TTS-optimized instruction string from Valhalla
  /// (verbal_pre_transition_instruction). Slightly different phrasing tuned
  /// for audio playback.
  final String verbalInstruction;

  /// Distance in miles from the current position to this maneuver.
  final double distanceMiles;

  /// Estimated time in seconds to reach this maneuver.
  final double durationSeconds;

  /// Index into [BravoRoute.waypoints] where this maneuver occurs.
  /// Used to compute the map position of each turn marker.
  final int shapeIndex;

  /// Street names at this maneuver location (may be empty for ramps, etc.).
  final List<String> streetNames;
}

// --- ROUTE ---

/// A complete computed route ready for turn-by-turn navigation.
class BravoRoute {
  /// Creates a route result.
  const BravoRoute({
    required this.waypoints,
    required this.distanceMeters,
    required this.estimatedSeconds,
    required this.steps,
    required this.preferencesUsed,
    required this.destination,
  });

  /// Full route polyline decoded from Valhalla's polyline6 shape.
  final List<LatLng> waypoints;

  /// Total route length in meters.
  final double distanceMeters;

  /// Estimated total travel time in seconds.
  final double estimatedSeconds;

  /// Ordered list of turn-by-turn maneuver steps.
  /// Empty only when the route has no meaningful turns (e.g. straight highway).
  final List<ManeuverStep> steps;

  /// The preference set that produced this route. Stored so mid-route toggle
  /// changes can be diffed and trigger recalculation selectively.
  final RoutePreferences preferencesUsed;

  /// The destination coordinate this route was calculated to.
  final LatLng destination;
}

// --- NAVIGATION STATE ---

/// Snapshot of where the user is within the active route right now.
/// Derived each GPS tick by [navigationStateProvider].
class NavigationState {
  /// Creates a navigation state snapshot.
  const NavigationState({
    required this.currentStepIndex,
    required this.currentStep,
    required this.distanceToNextManeuverMeters,
    required this.isLastStep,
    required this.distanceRemainingMeters,
    required this.timeRemainingSeconds,
  });

  /// Index of the step currently being navigated.
  final int currentStepIndex;

  /// The active step (instruction, type, etc.).
  final ManeuverStep currentStep;

  /// Distance in meters from the user's position to the next maneuver point.
  /// Shown in the HUD.
  final double distanceToNextManeuverMeters;

  /// True when this is the last step (destination arrival).
  final bool isLastStep;

  /// Remaining route distance from current position to destination, in meters.
  final double distanceRemainingMeters;

  /// Remaining travel time estimate in seconds. Simple: step durations summed.
  final double timeRemainingSeconds;
}

// --- GEOCODING RESULT ---

/// A Nominatim geocoding result.
class GeocodingResult {
  /// Creates a geocoding result.
  const GeocodingResult({
    required this.displayName,
    required this.shortName,
    required this.position,
  });

  /// Full formatted address from Nominatim (e.g. "Golden Gate Bridge, ...").
  final String displayName;

  /// Shortened label for the suggestion list (first two comma-separated parts).
  final String shortName;

  /// Geographic coordinates of this result.
  final LatLng position;
}
