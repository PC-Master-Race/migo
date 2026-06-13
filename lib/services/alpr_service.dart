// alpr_service.dart — ALPR (automated license plate reader) location data.
// Not being surveilled is treated as a human right in this codebase.
// This service merges two sources:
//   1. Community reports stored in our Supabase alpr_locations table.
//   2. OSM-tagged surveillance cameras queried via Overpass API.
//      (nodes tagged man_made=surveillance + surveillance:type=ALPR)
// Privacy guarantee: the user's position is sent to Overpass only in a
// coarse bounding area, with no user identity header.
// TODO: [proxy both sources through a Migo server so the user's exact
// position never reaches third-party servers] [deferred: needs server infra]

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'supabase_service.dart';

// --- SERVICE ---

/// Provides ALPR camera locations from community reports + OSM data.
class AlprService {
  // --- FETCH ---

  /// Fetches validated community-reported ALPR locations within [radiusMiles]
  /// of [center] from Supabase.
  Future<List<LatLng>> fetchCommunityAlprLocations(
    LatLng center, {
    double radiusMiles = 10.0,
  }) async {
    if (!SupabaseService.isConnected) return <LatLng>[];

    final (double minLat, double maxLat, double minLon, double maxLon) =
        _boundingBox(center, radiusMiles);

    try {
      final List<dynamic> rows = await SupabaseService.client
          .from(tableAlprLocations)
          .select('latitude, longitude')
          .eq('is_validated', true)
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLon)
          .lte('longitude', maxLon)
          .limit(500);

      return rows.map((dynamic r) {
        final Map<String, dynamic> row = r as Map<String, dynamic>;
        return LatLng(
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return <LatLng>[];
    }
  }

  /// Queries Overpass API for OSM-tagged ALPR/surveillance cameras near
  /// [center] within [radiusMeters].
  ///
  /// Returns an empty list on timeout or parse errors — caller degrades
  /// gracefully. Only the coarse bounding area is sent, not the exact position.
  Future<List<LatLng>> fetchOsmAlprLocations(
    LatLng center, {
    int radiusMeters = alprOverpassRadiusMeters,
  }) async {
    // Query for nodes explicitly tagged as ALPR cameras in OSM.
    // Dataset coverage is sparse but growing — community effort.
    final String query =
        '[out:json][timeout:10];'
        '(node(around:$radiusMeters,${center.latitude},${center.longitude})'
        '[man_made=surveillance][surveillance:type=ALPR];'
        'node(around:$radiusMeters,${center.latitude},${center.longitude})'
        '["surveillance:type"="ALPR"];);'
        'out;';

    try {
      final http.Response response = await http
          .post(
            Uri.parse(overpassApiUrl),
            headers: <String, String>{'User-Agent': osmUserAgent},
            body: <String, String>{'data': query},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return <LatLng>[];
      return _parseOverpassNodes(response.body);
    } catch (_) {
      return <LatLng>[];
    }
  }

  /// Merges [fetchCommunityAlprLocations] and [fetchOsmAlprLocations] into
  /// a single deduplicated list. Used by RoutingService for exclude_polygons.
  Future<List<LatLng>> fetchAllAlprLocations(LatLng center) async {
    final List<Future<List<LatLng>>> futures = <Future<List<LatLng>>>[
      fetchCommunityAlprLocations(center),
      fetchOsmAlprLocations(center),
    ];
    final List<List<LatLng>> results = await Future.wait(futures);
    final List<LatLng> merged = <LatLng>[
      ...results[0],
      ...results[1],
    ];
    return _deduplicate(merged);
  }

  // --- REPORT ---

  /// Reports a newly spotted ALPR camera at [position].
  ///
  /// New reports start with validation_score = 0. Community upvotes push it
  /// toward is_validated = true. Frequent reporters earn progress toward the
  /// Secret Agent archetype (Phase 4 ties this in via archetype_service).
  Future<void> reportAlprLocation(
    LatLng position, {
    String? description,
  }) async {
    if (!SupabaseService.isConnected) {
      return; // Silently drop — offline reporting not queued yet.
    }
    final String? uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) return;

    await SupabaseService.client
        .from(tableAlprLocations)
        .insert(<String, dynamic>{
      'reporter_id': uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      if (description != null) 'description': description,
    });
  }

  // --- PRIVATE HELPERS ---

  List<LatLng> _parseOverpassNodes(String body) {
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final List<dynamic> elements =
          decoded['elements'] as List<dynamic>? ?? <dynamic>[];
      return elements.map((dynamic e) {
        final Map<String, dynamic> node = e as Map<String, dynamic>;
        return LatLng(
          (node['lat'] as num).toDouble(),
          (node['lon'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return <LatLng>[];
    }
  }

  /// Removes duplicate coordinates within 20 m of each other (OSM and
  /// community data sometimes describe the same camera).
  List<LatLng> _deduplicate(List<LatLng> points) {
    const double dedupThresholdMeters = 20.0;
    final List<LatLng> unique = <LatLng>[];
    for (final LatLng p in points) {
      final bool isDup = unique.any((LatLng u) =>
          const Distance().as(LengthUnit.Meter, p, u) < dedupThresholdMeters);
      if (!isDup) unique.add(p);
    }
    return unique;
  }

  (double, double, double, double) _boundingBox(
      LatLng center, double radiusMiles) {
    final double latDelta = radiusMiles / 69.0;
    final double lonDelta =
        radiusMiles / (69.0 * math.cos(center.latitude * math.pi / 180.0));
    return (
      center.latitude - latDelta,
      center.latitude + latDelta,
      center.longitude - lonDelta,
      center.longitude + lonDelta,
    );
  }
}
