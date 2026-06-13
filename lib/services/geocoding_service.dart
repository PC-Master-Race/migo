// geocoding_service.dart — Address search via Nominatim (OpenStreetMap).
//
// Privacy: Nominatim is operated by the OSM community. No user account, no
// API key, no tracking. The search string and a coarse bounding box are sent;
// no user identity leaves the device. Usage policy requires the osmUserAgent
// header and a request limit of max 1 request/second — enforced by the
// debounce in the UI layer (not here, to keep this service stateless).
// TODO: [proxy through Bravo server so destination queries never leave to OSM]
// [deferred: same as Overpass proxy — needs server infrastructure]

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';

// --- SERVICE ---

/// Geocodes free-text queries to coordinates using the Nominatim API.
///
/// Search strategy (two-pass + distance sort):
///
///  Pass 1 — strict local box (bounded=1, ~50 km radius).
///    Nominatim only returns results inside the viewbox.
///    If at least one result is found, stop here and sort by distance.
///
///  Pass 2 — soft global fallback (bounded=0, same box).
///    Used when the strict box returns nothing — e.g. the user typed a
///    specific place that genuinely doesn't exist nearby ("Yoshinoya Beverly
///    Hills" from Upland). Results are still sorted by distance so the closest
///    one leads.
///
/// Why two passes instead of bounded=0 alone:
///   Nominatim's "importance" score (based on Wikipedia links, OSM node rank,
///   etc.) can push a globally famous branch to the top even when there's one
///   50 metres away. bounded=1 completely prevents that for the common case.
class GeocodingService {
  /// Searches for places matching [query], biased toward [userPosition].
  ///
  /// Returns up to [nominatimMaxResults] results sorted closest-first.
  /// Returns an empty list on any network or parse error.
  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? userPosition,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return <GeocodingResult>[];

    if (userPosition == null) {
      // No GPS — single pass, no box.
      return _fetch(q, userPosition: null, bounded: false);
    }

    // Pass 1: strict local box.
    final List<GeocodingResult> local =
        await _fetch(q, userPosition: userPosition, bounded: true);
    if (local.isNotEmpty) {
      return _sortByDistance(local, userPosition);
    }

    // Pass 2: global fallback — sort so closest still leads.
    final List<GeocodingResult> global =
        await _fetch(q, userPosition: userPosition, bounded: false);
    return _sortByDistance(global, userPosition);
  }

  // --- INTERNAL ---

  Future<List<GeocodingResult>> _fetch(
    String query, {
    required LatLng? userPosition,
    required bool bounded,
  }) async {
    // Nominatim viewbox: lon_left,lat_top,lon_right,lat_bottom (NW → SE).
    // 0.45 ° ≈ 50 km at US latitudes — wide enough for a metro area.
    const double viewboxDeg = 0.45;

    final Map<String, String> params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '$nominatimMaxResults',
      'addressdetails': '1',
      'countrycodes': 'us', // keep results in the US by default
    };

    if (userPosition != null) {
      final double lat = userPosition.latitude;
      final double lon = userPosition.longitude;
      params['viewbox'] =
          '${lon - viewboxDeg},${lat + viewboxDeg},${lon + viewboxDeg},${lat - viewboxDeg}';
      params['bounded'] = bounded ? '1' : '0';
    }

    final Uri uri =
        Uri.parse(nominatimSearchUrl).replace(queryParameters: params);

    try {
      final http.Response response = await http
          .get(uri, headers: <String, String>{'User-Agent': osmUserAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return <GeocodingResult>[];
      final List<dynamic> items = jsonDecode(response.body) as List<dynamic>;
      return items
          .map((dynamic item) => _parseResult(item as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();
    } catch (_) {
      return <GeocodingResult>[];
    }
  }

  /// Sort [results] by straight-line distance from [user], closest first.
  List<GeocodingResult> _sortByDistance(
    List<GeocodingResult> results,
    LatLng user,
  ) {
    const Distance dist = Distance();
    results.sort((GeocodingResult a, GeocodingResult b) {
      final double da =
          dist.as(LengthUnit.Meter, user, a.position);
      final double db =
          dist.as(LengthUnit.Meter, user, b.position);
      return da.compareTo(db);
    });
    return results;
  }

  GeocodingResult? _parseResult(Map<String, dynamic> item) {
    final String? latStr = item['lat'] as String?;
    final String? lonStr = item['lon'] as String?;
    final String? displayName = item['display_name'] as String?;
    if (latStr == null || lonStr == null || displayName == null) return null;

    final double? lat = double.tryParse(latStr);
    final double? lon = double.tryParse(lonStr);
    if (lat == null || lon == null) return null;

    // Short label: first two comma-separated parts of the Nominatim display name.
    final List<String> parts = displayName.split(', ');
    final String shortName =
        parts.length >= 2 ? '${parts[0]}, ${parts[1]}' : parts[0];

    return GeocodingResult(
      displayName: displayName,
      shortName: shortName,
      position: LatLng(lat, lon),
    );
  }
}
