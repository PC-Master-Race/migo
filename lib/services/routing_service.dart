// routing_service.dart — Route calculation via the Valhalla routing engine.
//
// --- ROUTING ENGINE DECISION: VALHALLA over OSRM ---
//
// Evaluated criteria per PRODUCT_BRIEF Phase 2:
//
// 1. DYNAMIC COSTING
//    OSRM: requires custom Lua profiles compiled into the graph. The public
//    router.project-osrm.org server uses fixed profiles only — avoid-tolls and
//    avoid-freeways require self-hosting with custom profiles.
//    Valhalla: use_tolls and use_highways are first-class costing_options on
//    every API call. No custom profiles, no self-hosting needed for the
//    options Migo requires in Phase 2.
//    WINNER: Valhalla.
//
// 2. ALPR AVOIDANCE
//    OSRM: no exclusion polygon support on the public API.
//    Valhalla: exclude_polygons is a top-level request parameter. We place
//    small circular polygons around each validated ALPR camera location —
//    exactly the penalty-zone behavior needed.
//    WINNER: Valhalla.
//
// 3. TURN-BY-TURN INSTRUCTIONS
//    Both engines provide step-level maneuvers. Valhalla additionally returns
//    verbal_pre_transition_instruction — a string pre-formatted for speech
//    synthesis ("In 200 meters, turn right onto Market Street."). This feeds
//    directly into TTS with no parsing needed.
//    WINNER: Valhalla.
//
// 4. OFFLINE CAPABILITY
//    OSRM: server-only. No mobile library.
//    Valhalla: has been compiled to run on-device in several projects
//    (e.g., Organic Maps uses it). Adds significant APK size. Deferred.
//    VERDICT: Tie for Phase 2 (both server-side); Valhalla has future upside.
//
// 5. PUBLIC ENDPOINT
//    OSM Community hosts valhalla1.openstreetmap.de — stable, free, no key.
//    OSRM: router.project-osrm.org — also free and stable.
//    VERDICT: Tie.
//
// DECISION: Valhalla (valhalla1.openstreetmap.de) for Phase 2 and beyond.
// TODO: [evaluate self-hosted Valhalla for production privacy guarantee]
// [deferred: OSM's server sees the origin/destination coordinates; a Migo
// server proxy would keep them off third-party logs]

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';

// --- SERVICE ---

/// Calls the Valhalla HTTP API to compute routes, decodes the response, and
/// maps it to [MigoRoute] + [ManeuverStep] list.
class RoutingService {
  // Valhalla's auto costing_options parameters.
  // use_tolls:    0.0 = strongly avoid, 1.0 = prefer.
  // use_highways: 0.0 = strongly avoid, 1.0 = prefer.
  // shortest:     true forces distance-minimizing routing.
  // All other costing knobs left at Valhalla defaults.

  /// Calculates a route from [origin] to [destination] using [preferences].
  ///
  /// Throws [RoutingException] on API errors; callers should handle gracefully.
  Future<MigoRoute> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutePreferences preferences,
    List<LatLng> alprLocations = const <LatLng>[],
  }) async {
    final Map<String, dynamic> body = _buildRequestBody(
      origin: origin,
      destination: destination,
      preferences: preferences,
      alprLocations: alprLocations,
    );

    final http.Response response = await http
        .post(
          Uri.parse(valhallaApiUrl),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'User-Agent': osmUserAgent,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw RoutingException(
        'Valhalla returned ${response.statusCode}: ${response.body}',
      );
    }

    return _parseResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
      destination: destination,
      preferences: preferences,
    );
  }

  // --- REQUEST BUILDER ---

  Map<String, dynamic> _buildRequestBody({
    required LatLng origin,
    required LatLng destination,
    required RoutePreferences preferences,
    required List<LatLng> alprLocations,
  }) {
    // Costing options per preference toggles.
    final Map<String, dynamic> costingOptions = _buildCostingOptions(preferences);

    // ALPR exclusion polygons: a circle approximated as an N-gon polygon per
    // camera location. Valhalla excludes any route that enters these polygons.
    final List<Map<String, dynamic>> excludePolygons =
        preferences.avoidAlprCameras
            ? alprLocations
                .map((LatLng loc) => _circlePolygon(loc, alprExcludeRadiusMeters))
                .toList()
            : <Map<String, dynamic>>[];

    return <String, dynamic>{
      'locations': <Map<String, dynamic>>[
        <String, dynamic>{
          'lon': origin.longitude,
          'lat': origin.latitude,
          'type': 'break',
        },
        <String, dynamic>{
          'lon': destination.longitude,
          'lat': destination.latitude,
          'type': 'break',
        },
      ],
      'costing': valhallaCostingModel,
      'costing_options': <String, dynamic>{
        valhallaCostingModel: costingOptions,
      },
      'directions_options': <String, dynamic>{
        'units': 'miles',
        'language': 'en-US',
      },
      if (excludePolygons.isNotEmpty)
        'exclude_polygons': excludePolygons,
    };
  }

  Map<String, dynamic> _buildCostingOptions(RoutePreferences prefs) {
    // use_highways and use_tolls are [0.0, 1.0] penalty scales.
    double useHighways = 1.0;
    double useTolls = 1.0;
    bool shortest = false;

    if (prefs.avoidFreeways) useHighways = 0.0;
    if (prefs.avoidPopularRoutes) {
      // "Avoid popular routes" maps to strong surface-street preference.
      // Not a perfect mapping — see RoutePreferences.avoidPopularRoutes docs.
      useHighways = math.min(useHighways, 0.1);
    }
    if (prefs.avoidTolls) useTolls = 0.0;

    if (prefs.optimizeFor == RouteOptimization.shortest) {
      shortest = true;
    } else if (prefs.optimizeFor == RouteOptimization.fewestStops) {
      // Highways have fewer signals — slightly prefer them when minimizing stops.
      useHighways = math.max(useHighways, 0.8);
    } else if (prefs.optimizeFor == RouteOptimization.mostFuelEfficient) {
      // Steady highway speeds are more efficient than stop-and-go arterials.
      // Moderate preference — doesn't override explicit avoidance settings.
      useHighways = math.max(useHighways, 0.5);
    }

    return <String, dynamic>{
      'use_highways': useHighways,
      'use_tolls': useTolls,
      'shortest': shortest,
    };
  }

  // --- RESPONSE PARSER ---

  MigoRoute _parseResponse(
    Map<String, dynamic> json, {
    required LatLng destination,
    required RoutePreferences preferences,
  }) {
    final Map<String, dynamic> trip =
        json['trip'] as Map<String, dynamic>;
    final Map<String, dynamic> summary =
        trip['summary'] as Map<String, dynamic>;

    // Valhalla reports length in miles (we asked for units:'miles').
    final double distanceMiles =
        (summary['length'] as num).toDouble();
    final double distanceMeters = distanceMiles * metersPerMile;
    final double durationSeconds =
        (summary['time'] as num).toDouble();

    // First (and only, for point-to-point routes) leg.
    final List<dynamic> legs = trip['legs'] as List<dynamic>;
    final Map<String, dynamic> leg = legs.first as Map<String, dynamic>;

    // Decode the polyline6-encoded shape string.
    final String shapeEncoded = leg['shape'] as String;
    final List<LatLng> waypoints = _decodePolyline6(shapeEncoded);

    // Parse maneuver steps.
    final List<dynamic> maneuversJson =
        leg['maneuvers'] as List<dynamic>;
    final List<ManeuverStep> steps = maneuversJson
        .map((dynamic m) => _parseManeuver(m as Map<String, dynamic>))
        .toList();

    return MigoRoute(
      waypoints: waypoints,
      distanceMeters: distanceMeters,
      estimatedSeconds: durationSeconds,
      steps: steps,
      preferencesUsed: preferences,
      destination: destination,
    );
  }

  ManeuverStep _parseManeuver(Map<String, dynamic> m) {
    final int typeCode = (m['type'] as num).toInt();
    final List<String> streets =
        ((m['street_names'] as List<dynamic>?) ?? <dynamic>[])
            .cast<String>();

    return ManeuverStep(
      type: ManeuverType.fromCode(typeCode),
      instruction: (m['instruction'] as String?) ?? '',
      verbalInstruction:
          (m['verbal_pre_transition_instruction'] as String?) ??
              (m['instruction'] as String?) ??
              '',
      distanceMiles: (m['length'] as num).toDouble(),
      durationSeconds: (m['time'] as num).toDouble(),
      shapeIndex: (m['begin_shape_index'] as num).toInt(),
      streetNames: streets,
    );
  }

  // --- POLYLINE6 DECODER ---
  // Valhalla uses Google's polyline encoding algorithm with precision 6
  // (1e6 instead of 1e5), yielding ~0.1 m accuracy — sufficient for lane-level
  // route rendering.

  List<LatLng> _decodePolyline6(String encoded) {
    final List<LatLng> points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decode latitude delta.
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += dlat;

      // Decode longitude delta.
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += dlng;

      points.add(LatLng(lat / 1e6, lng / 1e6));
    }
    return points;
  }

  // --- ALPR EXCLUSION POLYGON BUILDER ---
  // Valhalla exclude_polygons format: a list of polygon rings, each being a
  // list of [lon, lat] coordinate pairs. We approximate a circle as an N-gon.

  Map<String, dynamic> _circlePolygon(LatLng center, double radiusMeters) {
    const int n = alprExcludePolygonVertices;
    // Convert radius from meters to approximate degrees.
    // 1 degree of latitude ≈ 111,000 m. Longitude degree shrinks with cosine.
    final double latDelta = radiusMeters / 111000.0;
    final double lngDelta =
        radiusMeters / (111000.0 * math.cos(center.latitude * math.pi / 180));

    final List<List<double>> ring = <List<double>>[];
    for (int i = 0; i <= n; i++) {
      final double angle = 2 * math.pi * i / n;
      ring.add(<double>[
        center.longitude + lngDelta * math.cos(angle),
        center.latitude + latDelta * math.sin(angle),
      ]);
    }
    return <String, dynamic>{'coordinates': <dynamic>[ring]};
  }
}

// --- EXCEPTION ---

/// Thrown by [RoutingService] when the routing engine returns an error.
class RoutingException implements Exception {
  /// Creates a routing exception with a descriptive [message].
  const RoutingException(this.message);
  final String message;
  @override
  String toString() => 'RoutingException: $message';
}

// --- OFF-ROUTE GEOMETRY ---
// Kept in this file to co-locate all routing geometry logic.

/// Returns the perpendicular distance in meters from [point] to the nearest
/// segment of [polyline]. Used by [offRouteProvider] to detect when the user
/// has left the computed route.
double distanceToPolylineMeters(LatLng point, List<LatLng> polyline) {
  if (polyline.isEmpty) return double.infinity;
  if (polyline.length == 1) {
    return const Distance().as(LengthUnit.Meter, point, polyline.first);
  }

  double minDist = double.infinity;
  for (int i = 0; i < polyline.length - 1; i++) {
    final double d =
        _distanceToSegmentMeters(point, polyline[i], polyline[i + 1]);
    if (d < minDist) minDist = d;
  }
  return minDist;
}

/// Distance from [p] to the segment [a]→[b] in meters, using a flat-earth
/// approximation (accurate to <0.1% for distances under a few km — route
/// geometry is always within a few km of the user).
double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
  // Convert to approximate meters-based coordinates relative to [a].
  const double latMeterPerDeg = 111000.0;
  final double cosLat = math.cos(a.latitude * math.pi / 180);

  final double px = (p.longitude - a.longitude) * latMeterPerDeg * cosLat;
  final double py = (p.latitude - a.latitude) * latMeterPerDeg;
  final double bx = (b.longitude - a.longitude) * latMeterPerDeg * cosLat;
  final double by = (b.latitude - a.latitude) * latMeterPerDeg;

  final double lenSq = bx * bx + by * by;
  if (lenSq == 0) {
    // Segment is a point — just return point-to-point distance.
    return math.sqrt(px * px + py * py);
  }
  // Project p onto the segment, clamped to [0, 1].
  final double t = math.max(0, math.min(1, (px * bx + py * by) / lenSq));
  final double dx = px - t * bx;
  final double dy = py - t * by;
  return math.sqrt(dx * dx + dy * dy);
}
