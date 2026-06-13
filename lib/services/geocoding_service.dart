// geocoding_service.dart — Address search via Nominatim (OpenStreetMap).
//
// Privacy: Nominatim is operated by the OSM community. No user account, no
// API key, no tracking. The search string and a coarse bounding box are sent;
// no user identity leaves the device. Usage policy requires the osmUserAgent
// header and a request limit of max 1 request/second — enforced by the
// debounce in the UI layer (not here, to keep this service stateless).
// TODO: [proxy through Migo server so destination queries never leave to OSM]
// [deferred: same as Overpass proxy — needs server infrastructure]

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';

// --- SERVICE ---

/// Geocodes free-text queries to coordinates using the Nominatim API.
class GeocodingService {
  /// Searches for places matching [query].
  ///
  /// Returns up to [nominatimMaxResults] results ordered by Nominatim's
  /// relevance score. Returns an empty list on any network or parse error so
  /// callers can degrade gracefully.
  Future<List<GeocodingResult>> search(String query) async {
    if (query.trim().isEmpty) return <GeocodingResult>[];

    final Uri uri = Uri.parse(nominatimSearchUrl).replace(
      queryParameters: <String, String>{
        'q': query,
        'format': 'json',
        'limit': '$nominatimMaxResults',
        'addressdetails': '1',
      },
    );

    try {
      final http.Response response = await http
          .get(
            uri,
            headers: <String, String>{'User-Agent': osmUserAgent},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return <GeocodingResult>[];
      final List<dynamic> items = jsonDecode(response.body) as List<dynamic>;
      return items
          .map((dynamic item) =>
              _parseResult(item as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();
    } catch (_) {
      return <GeocodingResult>[];
    }
  }

  GeocodingResult? _parseResult(Map<String, dynamic> item) {
    final String? latStr = item['lat'] as String?;
    final String? lonStr = item['lon'] as String?;
    final String? displayName = item['display_name'] as String?;
    if (latStr == null || lonStr == null || displayName == null) return null;

    final double? lat = double.tryParse(latStr);
    final double? lon = double.tryParse(lonStr);
    if (lat == null || lon == null) return null;

    // Build a short label: first two comma-separated parts of the display name.
    final List<String> parts = displayName.split(', ');
    final String shortName = parts.length >= 2
        ? '${parts[0]}, ${parts[1]}'
        : parts[0];

    return GeocodingResult(
      displayName: displayName,
      shortName: shortName,
      position: LatLng(lat, lon),
    );
  }
}
