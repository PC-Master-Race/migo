// geocoding_service.dart — Address/POI search via Photon (primary) with
// Nominatim fallback for structured addresses.
//
// Why Photon over Nominatim for POI search:
//   Nominatim ranks results by OSM "importance" (Wikipedia links, node rank)
//   which causes globally famous locations to outrank nearby ones even with
//   bounded=1. Photon (photon.komoot.io) uses the same OSM data but actively
//   sorts by distance to the provided lat/lon — so typing "Yoshinoya" returns
//   the nearest one first, not one 1000 miles away.
//
// Privacy: Photon is run by Komoot (open source, no account, no API key).
// The query string and coarse GPS coordinates are sent — no user identity.
// Same privacy level as Nominatim. Both are acceptable per PRODUCT_BRIEF.
//
// TODO: [self-host Photon for production so coordinates stay off third-party
// servers] [deferred: needs server infrastructure decision]

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';

// ---------------------------------------------------------------------------
// GeocodingService
// ---------------------------------------------------------------------------

class GeocodingService {
  /// Searches for [query], biased toward [userPosition].
  ///
  /// Strategy:
  ///  1. Photon with lat/lon — returns nearest OSM matches first.
  ///  2. If Photon returns nothing, fall back to Nominatim (better for
  ///     structured addresses like "1234 Main St").
  ///
  /// Returns up to [nominatimMaxResults] results. Empty list on error.
  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? userPosition,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return <GeocodingResult>[];

    // --- Pass 1: Photon ---
    final List<GeocodingResult> photonResults =
        await _photonSearch(q, userPosition: userPosition);
    if (photonResults.isNotEmpty) return photonResults;

    // --- Pass 2: Nominatim fallback ---
    return _nominatimSearch(q, userPosition: userPosition);
  }

  // -------------------------------------------------------------------------
  // Photon
  // -------------------------------------------------------------------------

  Future<List<GeocodingResult>> _photonSearch(
    String query, {
    LatLng? userPosition,
  }) async {
    final Map<String, String> params = <String, String>{
      'q': query,
      'limit': '$nominatimMaxResults',
      'lang': 'en',
    };

    // When lat/lon are provided Photon weights distance heavily —
    // the nearest matching place almost always comes first.
    if (userPosition != null) {
      params['lat'] = userPosition.latitude.toStringAsFixed(6);
      params['lon'] = userPosition.longitude.toStringAsFixed(6);
    }

    final Uri uri = Uri.parse(photonSearchUrl).replace(queryParameters: params);

    try {
      final http.Response response = await http
          .get(uri, headers: <String, String>{'User-Agent': osmUserAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return <GeocodingResult>[];

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> features =
          (body['features'] as List<dynamic>?) ?? <dynamic>[];

      final List<GeocodingResult> results = features
          .map((dynamic f) =>
              _parsePhotonFeature(f as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();

      // Photon already sorts by distance, but if we have the user position
      // double-sort to handle any ties and confirm ordering.
      if (userPosition != null) {
        _sortByDistance(results, userPosition);
      }
      return results;
    } catch (_) {
      return <GeocodingResult>[];
    }
  }

  GeocodingResult? _parsePhotonFeature(Map<String, dynamic> feature) {
    final Map<String, dynamic>? geometry =
        feature['geometry'] as Map<String, dynamic>?;
    final Map<String, dynamic>? props =
        feature['properties'] as Map<String, dynamic>?;
    if (geometry == null || props == null) return null;

    // Photon coordinates are [lon, lat].
    final List<dynamic>? coords =
        geometry['coordinates'] as List<dynamic>?;
    if (coords == null || coords.length < 2) return null;

    final double? lon = (coords[0] as num?)?.toDouble();
    final double? lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    // Build display name from property fields.
    final String name = (props['name'] as String?) ?? '';
    final String street = (props['street'] as String?) ?? '';
    final String housenumber = (props['housenumber'] as String?) ?? '';
    final String city = (props['city'] as String?) ??
        (props['town'] as String?) ??
        (props['village'] as String?) ??
        '';
    final String state = (props['state'] as String?) ?? '';

    if (name.isEmpty && street.isEmpty) return null;

    // Short name: "Name, City" or "123 Main St, City".
    final String addressPart = <String>[
      if (housenumber.isNotEmpty) housenumber,
      if (street.isNotEmpty) street,
    ].join(' ').trim();

    final String primaryPart = name.isNotEmpty ? name : addressPart;
    final String secondaryPart = name.isNotEmpty
        ? <String>[if (addressPart.isNotEmpty) addressPart, city]
            .where((String s) => s.isNotEmpty)
            .join(', ')
        : city;

    final String shortName = secondaryPart.isNotEmpty
        ? '$primaryPart, $secondaryPart'
        : primaryPart;

    // Full display name.
    final List<String> displayParts = <String>[
      if (name.isNotEmpty) name,
      if (addressPart.isNotEmpty) addressPart,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
    ];
    final String displayName = displayParts.join(', ');

    return GeocodingResult(
      displayName: displayName,
      shortName: shortName,
      position: LatLng(lat, lon),
    );
  }

  // -------------------------------------------------------------------------
  // Nominatim fallback (structured address search)
  // -------------------------------------------------------------------------

  Future<List<GeocodingResult>> _nominatimSearch(
    String query, {
    LatLng? userPosition,
  }) async {
    const double viewboxDeg = 0.45; // ≈ 50 km

    final Map<String, String> params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '$nominatimMaxResults',
      'addressdetails': '1',
      'countrycodes': 'us',
    };

    if (userPosition != null) {
      final double lat = userPosition.latitude;
      final double lon = userPosition.longitude;
      params['viewbox'] =
          '${lon - viewboxDeg},${lat + viewboxDeg},${lon + viewboxDeg},${lat - viewboxDeg}';
      params['bounded'] = '0';
    }

    final Uri uri =
        Uri.parse(nominatimSearchUrl).replace(queryParameters: params);

    try {
      final http.Response response = await http
          .get(uri, headers: <String, String>{'User-Agent': osmUserAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return <GeocodingResult>[];
      final List<dynamic> items = jsonDecode(response.body) as List<dynamic>;
      final List<GeocodingResult> results = items
          .map((dynamic item) =>
              _parseNominatimResult(item as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();

      if (userPosition != null) _sortByDistance(results, userPosition);
      return results;
    } catch (_) {
      return <GeocodingResult>[];
    }
  }

  GeocodingResult? _parseNominatimResult(Map<String, dynamic> item) {
    final String? latStr = item['lat'] as String?;
    final String? lonStr = item['lon'] as String?;
    final String? displayName = item['display_name'] as String?;
    if (latStr == null || lonStr == null || displayName == null) return null;

    final double? lat = double.tryParse(latStr);
    final double? lon = double.tryParse(lonStr);
    if (lat == null || lon == null) return null;

    final List<String> parts = displayName.split(', ');
    final String shortName =
        parts.length >= 2 ? '${parts[0]}, ${parts[1]}' : parts[0];

    return GeocodingResult(
      displayName: displayName,
      shortName: shortName,
      position: LatLng(lat, lon),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _sortByDistance(List<GeocodingResult> results, LatLng user) {
    const Distance dist = Distance();
    results.sort((GeocodingResult a, GeocodingResult b) {
      final double da = dist.as(LengthUnit.Meter, user, a.position);
      final double db = dist.as(LengthUnit.Meter, user, b.position);
      return da.compareTo(db);
    });
  }
}
