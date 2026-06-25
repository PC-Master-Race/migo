// alpr_service.dart — ALPR (automated license plate reader) location data.
// Not being surveilled is treated as a human right in this codebase.
//
// SINGLE SOURCE OF TRUTH: the Supabase `alpr_locations` table. It holds both
// OSM/DeFlock-imported cameras (source='osm', bulk-loaded once via
// importOsmAlprForRegion) and community reports. The map layer and routing both
// read from this table — fast, complete, and offline-friendly, with no live
// Overpass dependency at drive time.
//
// Privacy: the one-time OSM import is the only call that hits Overpass, and it
// sends a coarse bounding box, no user identity. ALPR data never leaves to any
// third party.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'supabase_service.dart';

/// Outcome of a one-time OSM import — carries enough detail to diagnose a
/// "0 cameras" result instead of failing silently.
class AlprImportResult {
  const AlprImportResult({
    required this.added,
    required this.fetched,
    this.error,
  });

  /// Rows newly inserted into the DB.
  final int added;

  /// Cameras pulled from OSM (before de-dupe).
  final int fetched;

  /// Human-readable failure reason, or null on success.
  final String? error;
}

/// Reads ALPR cameras from the DB and runs the one-time OSM import.
class AlprService {
  // --- DB READS (map display + routing) ---

  /// Validated ALPR cameras within the given lat/long box.
  Future<List<LatLng>> fetchAlprInBbox(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
  ) async {
    if (!SupabaseService.isConnected) return <LatLng>[];
    try {
      final List<dynamic> rows = await SupabaseService.client
          .from(tableAlprLocations)
          .select('latitude, longitude')
          .eq('is_validated', true)
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLon)
          .lte('longitude', maxLon)
          .limit(2000);
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

  /// Cameras within [radiusMiles] of [center] — for the map display layer.
  Future<List<LatLng>> fetchAlprNear(LatLng center, {double radiusMiles = 12}) {
    final (double minLat, double maxLat, double minLon, double maxLon) =
        _boundingBox(center, radiusMiles);
    return fetchAlprInBbox(minLat, maxLat, minLon, maxLon);
  }

  /// Cameras in the corridor between [origin] and [destination] (their bounding
  /// box, padded) — lets routing avoid every camera on the route in one pass.
  Future<List<LatLng>> fetchAlprForRoute(LatLng origin, LatLng destination) {
    const double padDeg = 0.1; // ~7 mi padding around the O-D box
    final double minLat =
        math.min(origin.latitude, destination.latitude) - padDeg;
    final double maxLat =
        math.max(origin.latitude, destination.latitude) + padDeg;
    final double minLon =
        math.min(origin.longitude, destination.longitude) - padDeg;
    final double maxLon =
        math.max(origin.longitude, destination.longitude) + padDeg;
    return fetchAlprInBbox(minLat, maxLat, minLon, maxLon);
  }

  // --- ONE-TIME OSM IMPORT (app-driven) ---

  /// Fetches OSM-tagged ALPR camera nodes (with ids) inside a bbox via Overpass.
  Future<List<Map<String, dynamic>>> _fetchOsmAlprNodes(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
  ) async {
    // Overpass bbox order is (south,west,north,east).
    final String query = '[out:json][timeout:120];'
        'node["surveillance:type"="ALPR"]($minLat,$minLon,$maxLat,$maxLon);'
        'out;';
    final http.Response response = await http
          .post(
            Uri.parse(overpassApiUrl),
            headers: <String, String>{'User-Agent': osmUserAgent},
            body: <String, String>{'data': query},
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw Exception('Overpass returned HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> elements =
          decoded['elements'] as List<dynamic>? ?? <dynamic>[];
      return elements
          .map((dynamic e) {
            final Map<String, dynamic> n = e as Map<String, dynamic>;
            return <String, dynamic>{
              'id': n['id'],
              'lat': (n['lat'] as num).toDouble(),
              'lon': (n['lon'] as num).toDouble(),
            };
          })
          .where((Map<String, dynamic> m) => m['id'] != null)
          .toList();
  }

  /// One-time sync: pulls OSM ALPR cameras within [radiusMiles] of [center] and
  /// bulk-loads them into alpr_locations via the upsert_osm_alpr RPC. Returns a
  /// diagnostic result so a "0 cameras" outcome explains itself.
  Future<AlprImportResult> importOsmAlprForRegion(
    LatLng center, {
    double radiusMiles = 70,
  }) async {
    if (!SupabaseService.isConnected) {
      return const AlprImportResult(
          added: 0, fetched: 0, error: 'Offline — no Supabase connection.');
    }
    if (SupabaseService.client.auth.currentUser == null) {
      return const AlprImportResult(
          added: 0, fetched: 0, error: 'Not signed in yet — reopen the app.');
    }
    final (double minLat, double maxLat, double minLon, double maxLon) =
        _boundingBox(center, radiusMiles);

    // 1. Pull cameras from OSM.
    List<Map<String, dynamic>> nodes;
    try {
      nodes = await _fetchOsmAlprNodes(minLat, maxLat, minLon, maxLon);
    } catch (e) {
      return AlprImportResult(added: 0, fetched: 0, error: 'OSM fetch failed: $e');
    }
    if (nodes.isEmpty) {
      return const AlprImportResult(
          added: 0, fetched: 0, error: 'OSM returned no cameras for this area.');
    }

    // 2. Bulk-load into the DB.
    try {
      final dynamic added = await SupabaseService.client.rpc(
        'upsert_osm_alpr',
        params: <String, dynamic>{'p_cameras': nodes},
      );
      return AlprImportResult(
        added: (added as num?)?.toInt() ?? 0,
        fetched: nodes.length,
      );
    } catch (e) {
      return AlprImportResult(
          added: 0, fetched: nodes.length, error: 'DB import failed: $e');
    }
  }

  // --- COMMUNITY REPORT ---

  /// Reports a newly spotted ALPR camera at [position]. Starts unvalidated;
  /// community votes push it toward is_validated = true.
  Future<void> reportAlprLocation(
    LatLng position, {
    String? description,
  }) async {
    if (!SupabaseService.isConnected) return;
    final String? uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) return;

    await SupabaseService.client
        .from(tableAlprLocations)
        .insert(<String, dynamic>{
      'reporter_id': uid,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'source': 'community',
      if (description != null) 'description': description,
    });
  }

  // --- HELPERS ---

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
