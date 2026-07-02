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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';

// --- SERVICE ---

/// Calls the Valhalla HTTP API to compute routes, decodes the response, and
/// maps it to [BravoRoute] + [ManeuverStep] list.
class RoutingService {
  // Valhalla's auto costing_options parameters.
  // use_tolls:    0.0 = strongly avoid, 1.0 = prefer.
  // use_highways: 0.0 = strongly avoid, 1.0 = prefer.
  // shortest:     true forces distance-minimizing routing.
  // All other costing knobs left at Valhalla defaults.

  /// Calculates a route from [origin] to [destination] using [preferences].
  ///
  /// Throws [RoutingException] on API errors; callers should handle gracefully.
  Future<BravoRoute> calculateRoute({
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

    final int polygonCount =
        (body['exclude_polygons'] as List<dynamic>?)?.length ?? 0;
    if (polygonCount > 0) {
      debugPrint('[routing] Valhalla request with $polygonCount '
          'exclude_polygons (~${(polygonCount * alprExclusionPerimeterMeters).round()} m '
          'of the ${valhallaExcludePerimeterBudgetMeters.round()} m budget)');
    }

    // The public Valhalla server occasionally throws transient 5xx errors
    // (502 Bad Gateway under load). Retry those a couple of times before
    // giving up — a driver shouldn't see "route failed" for a server blip.
    http.Response response = await _postWithRetry(body);

    if (response.statusCode != 200) {
      // Log the FULL body — Valhalla's rejection reason lives here and losing
      // it is exactly how the "avoidance silently dies" bug stayed hidden.
      debugPrint('[routing] Valhalla HTTP ${response.statusCode}: '
          '${response.body.length > 600 ? response.body.substring(0, 600) : response.body}');
      throw RoutingException(_conciseValhallaError(response));
    }

    return _parseResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
      destination: destination,
      preferences: preferences,
    );
  }

  /// POSTs the route request, retrying up to [valhallaMaxRetries] times on
  /// transient failures (HTTP 5xx). 4xx responses return immediately — those
  /// are OUR fault (bad request) and retrying won't change the answer.
  ///
  /// FALLBACK: the public server has been observed 502-ing POST /route while
  /// answering GET /route?json=... fine (confirmed live 2026-07-01). After a
  /// 5xx on POST we immediately retry the SAME request as a GET when it fits
  /// in a URL (plain routes always do; camera-avoidance payloads may not).
  Future<http.Response> _postWithRetry(Map<String, dynamic> body) async {
    Object? lastError;
    for (int attempt = 0; attempt <= valhallaMaxRetries; attempt++) {
      if (attempt > 0) {
        debugPrint('[routing] retrying Valhalla (attempt ${attempt + 1})');
        await Future<void>.delayed(valhallaRetryDelay * attempt);
      }
      try {
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
        if (response.statusCode < 500) return response; // success or 4xx
        lastError = 'HTTP ${response.statusCode}';
        debugPrint('[routing] Valhalla POST ${response.statusCode} — '
            'trying GET fallback');
      } catch (e) {
        lastError = e; // network error / timeout — also worth a retry
        debugPrint('[routing] Valhalla POST failed ($e) — trying GET fallback');
      }

      // GET fallback for this attempt.
      final http.Response? viaGet = await _tryGet(body);
      if (viaGet != null && viaGet.statusCode < 500) return viaGet;
      if (viaGet != null) lastError = 'HTTP ${viaGet.statusCode} (GET)';
    }
    throw RoutingException(
        'Routing server unavailable after ${valhallaMaxRetries + 1} attempts '
        '($lastError). Try again in a moment.');
  }

  /// Sends the route request as GET /route?json=<encoded>. Returns null when
  /// the payload is too large for a URL or the request throws.
  Future<http.Response?> _tryGet(Map<String, dynamic> body) async {
    final Uri uri = Uri.parse(valhallaApiUrl)
        .replace(queryParameters: <String, String>{'json': jsonEncode(body)});
    if (uri.toString().length > 7500) {
      debugPrint('[routing] GET fallback skipped — payload too large for URL');
      return null;
    }
    try {
      return await http
          .get(uri, headers: <String, String>{'User-Agent': osmUserAgent})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[routing] GET fallback failed: $e');
      return null;
    }
  }

  /// Extracts a short human-readable error from a Valhalla error response
  /// (they return JSON like {"error_code":171,"error":"..."}). Falls back to
  /// the status code alone so the UI message stays snackbar-sized.
  String _conciseValhallaError(http.Response response) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? msg = json['error'] as String?;
      if (msg != null && msg.isNotEmpty) {
        return 'Valhalla ${response.statusCode}: $msg';
      }
    } catch (_) {/* not JSON — fall through */}
    return 'Valhalla returned HTTP ${response.statusCode}';
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

  BravoRoute _parseResponse(
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

    return BravoRoute(
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

// --- ALPR EXCLUSION SELECTION ---
// The public Valhalla server rejects requests whose exclude_polygons exceed
// ~10,000 m of TOTAL ring perimeter (service_limits.max_exclude_polygons_length).
// These helpers spend that budget on the cameras that actually matter: the
// ones near the candidate route, nearest-first, with overlapping cameras
// merged into one circle.

/// Perimeter (meters) of one ALPR exclusion N-gon: 2·n·r·sin(π/n).
final double alprExclusionPerimeterMeters = 2 *
    alprExcludePolygonVertices *
    alprExcludeRadiusMeters *
    math.sin(math.pi / alprExcludePolygonVertices);

/// Picks which cameras to exclude, given the [cameras] in the corridor and the
/// [routePolyline] of a candidate route:
///
/// 1. Keep only cameras within [alprAvoidCorridorMeters] of the polyline —
///    a camera 5 miles off the route can't affect the drive.
/// 2. Sort nearest-to-route first (those most certainly ON the route).
/// 3. Skip cameras within [alprAvoidMergeMeters] of an already-picked one
///    (its 150 m circle already covers them).
/// 4. Stop when [valhallaExcludePerimeterBudgetMeters] is spent.
///
/// [alreadySelected] cameras are kept (and count against the budget) — used by
/// the refinement pass so the re-route never un-avoids a camera.
List<LatLng> selectAlprExclusions({
  required List<LatLng> cameras,
  required List<LatLng> routePolyline,
  List<LatLng> alreadySelected = const <LatLng>[],
}) {
  if (cameras.isEmpty || routePolyline.length < 2) {
    return List<LatLng>.of(alreadySelected);
  }

  // Decimate long polylines so the distance scan stays cheap (2,000 cameras ×
  // thousands of polyline6 points would jank the UI isolate). Corner-cutting
  // error from skipping points is far below the 250 m corridor tolerance.
  const int maxPolyPoints = 800;
  List<LatLng> poly = routePolyline;
  if (poly.length > maxPolyPoints) {
    final int step = (poly.length / maxPolyPoints).ceil();
    poly = <LatLng>[
      for (int i = 0; i < poly.length; i += step) poly[i],
      poly.last,
    ];
  }

  // Rank corridor cameras by distance to the route.
  final List<(double, LatLng)> ranked = <(double, LatLng)>[];
  for (final LatLng cam in cameras) {
    final double d = distanceToPolylineMeters(cam, poly);
    if (d <= alprAvoidCorridorMeters) ranked.add((d, cam));
  }
  ranked.sort(((double, LatLng) a, (double, LatLng) b) =>
      a.$1.compareTo(b.$1));

  final List<LatLng> selected = List<LatLng>.of(alreadySelected);
  double budget = valhallaExcludePerimeterBudgetMeters -
      selected.length * alprExclusionPerimeterMeters;
  const Distance dist = Distance();

  for (final (double, LatLng) entry in ranked) {
    if (budget < alprExclusionPerimeterMeters) break;
    final LatLng cam = entry.$2;
    final bool covered = selected.any((LatLng s) =>
        dist.as(LengthUnit.Meter, s, cam) < alprAvoidMergeMeters);
    if (covered) continue;
    selected.add(cam);
    budget -= alprExclusionPerimeterMeters;
  }

  debugPrint('[routing] ALPR selection: ${cameras.length} in corridor bbox → '
      '${ranked.length} within ${alprAvoidCorridorMeters.round()} m of route → '
      '${selected.length} excluded (budget cap '
      '${(valhallaExcludePerimeterBudgetMeters / alprExclusionPerimeterMeters).floor()})');
  return selected;
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

/// Returns the START index of the polyline segment nearest to [point]. This is
/// the user's position ALONG the route — used to decide which maneuver is next
/// (the first one whose vertex is past this index), so navigation advances as
/// the user passes each turn instead of snapping to whichever turn is closest.
int nearestSegmentIndex(LatLng point, List<LatLng> polyline) {
  if (polyline.length < 2) return 0;
  int best = 0;
  double minDist = double.infinity;
  for (int i = 0; i < polyline.length - 1; i++) {
    final double d =
        _distanceToSegmentMeters(point, polyline[i], polyline[i + 1]);
    if (d < minDist) {
      minDist = d;
      best = i;
    }
  }
  return best;
}

/// Sums the along-route distance (meters) between polyline indices
/// [fromIdx] and [toIdx]. Used for "distance to the next maneuver" and
/// "distance remaining" so they follow the road, not a straight line.
double routeDistanceMeters(List<LatLng> polyline, int fromIdx, int toIdx) {
  if (polyline.length < 2) return 0;
  final int start = fromIdx.clamp(0, polyline.length - 1);
  final int end = toIdx.clamp(0, polyline.length - 1);
  double sum = 0;
  for (int i = start; i < end; i++) {
    sum += const Distance().as(LengthUnit.Meter, polyline[i], polyline[i + 1]);
  }
  return sum;
}

/// Result of projecting a GPS fix onto a route polyline: the on-route point,
/// the road bearing at that point (degrees, 0 = north), and how far the raw
/// fix was from the route.
typedef RouteSnap = ({LatLng point, double headingDeg, double distanceMeters});

/// Projects [p] onto the nearest segment of [polyline] — map-matching for the
/// displayed avatar. Returns the snapped point, the segment's bearing (so the
/// avatar can point along the ROAD instead of along GPS heading jitter), and
/// the snap distance (callers reject snaps beyond [routeSnapMaxDistanceMeters]).
/// Returns null for degenerate polylines.
RouteSnap? snapToPolyline(LatLng p, List<LatLng> polyline) {
  if (polyline.length < 2) return null;

  const double latMeterPerDeg = 111000.0;
  double bestDist = double.infinity;
  LatLng bestPoint = polyline.first;
  double bestHeading = 0;

  for (int i = 0; i < polyline.length - 1; i++) {
    final LatLng a = polyline[i];
    final LatLng b = polyline[i + 1];
    final double cosLat = math.cos(a.latitude * math.pi / 180);

    final double px = (p.longitude - a.longitude) * latMeterPerDeg * cosLat;
    final double py = (p.latitude - a.latitude) * latMeterPerDeg;
    final double bx = (b.longitude - a.longitude) * latMeterPerDeg * cosLat;
    final double by = (b.latitude - a.latitude) * latMeterPerDeg;

    final double lenSq = bx * bx + by * by;
    final double t = lenSq == 0
        ? 0
        : math.max(0.0, math.min(1.0, (px * bx + py * by) / lenSq));
    final double qx = t * bx;
    final double qy = t * by;
    final double dx = px - qx;
    final double dy = py - qy;
    final double d = math.sqrt(dx * dx + dy * dy);

    if (d < bestDist) {
      bestDist = d;
      bestPoint = LatLng(
        a.latitude + qy / latMeterPerDeg,
        a.longitude + qx / (latMeterPerDeg * cosLat),
      );
      if (lenSq > 0) {
        // atan2(east, north) → compass bearing of the segment.
        bestHeading = (math.atan2(bx, by) * 180 / math.pi + 360) % 360;
      }
    }
  }
  return (point: bestPoint, headingDeg: bestHeading, distanceMeters: bestDist);
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
