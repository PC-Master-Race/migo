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
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
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
  /// LOCAL-FIRST strategy:
  ///  1. Search within [localGeocodeRadiusMiles] of the user. Only if that
  ///     finds nothing do we widen.
  ///  2. Widen to the continental US (never worldwide).
  ///
  /// Within each pass: street addresses (query starts with a house number) go
  /// to Nominatim first (it returns the numbered address); everything else goes
  /// to Photon first (distance-first ranking). The other engine is the
  /// fallback if the first finds nothing.
  ///
  /// Returns up to [nominatimMaxResults] results. Empty list on error.
  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? userPosition,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return <GeocodingResult>[];

    // A leading digit means the user is typing a street address.
    final bool looksLikeAddress = RegExp(r'^\s*\d').hasMatch(q);

    // Runs the preferred engine for [q] inside [bbox], falling back to the
    // other engine if the first finds nothing. Logs which engine answered and
    // every coordinate — the diagnostic trail for "pin on the wrong side".
    Future<List<GeocodingResult>> runPass(_GeoBBox bbox) async {
      List<GeocodingResult> results;
      String engine;
      if (looksLikeAddress) {
        results = await _nominatimSearch(q,
            userPosition: userPosition, bbox: bbox);
        engine = 'nominatim';
        if (results.isEmpty) {
          results =
              await _photonSearch(q, userPosition: userPosition, bbox: bbox);
          engine = 'photon(fallback)';
        }
      } else {
        results =
            await _photonSearch(q, userPosition: userPosition, bbox: bbox);
        engine = 'photon';
        if (results.isEmpty) {
          results = await _nominatimSearch(q,
              userPosition: userPosition, bbox: bbox);
          engine = 'nominatim(fallback)';
        }
      }
      for (final GeocodingResult r in results) {
        debugPrint('[geocode] $engine "$q" → "${r.shortName}" @ '
            '${r.position.latitude.toStringAsFixed(6)},'
            '${r.position.longitude.toStringAsFixed(6)}');
      }
      return results;
    }

    // --- Pass 1: LOCAL — within localGeocodeRadiusMiles of the user. ---
    if (userPosition != null) {
      final List<GeocodingResult> local =
          await runPass(_bboxAround(userPosition, localGeocodeRadiusMiles));
      if (local.isNotEmpty) return local;
    }

    // --- Pass 2: WIDE — continental US (never worldwide). ---
    return runPass(const _GeoBBox.unitedStates());
  }

  /// A ~[radiusMiles] bounding box centred on [center]. Longitude degrees are
  /// scaled by latitude so the box stays roughly square in real distance.
  _GeoBBox _bboxAround(LatLng center, double radiusMiles) {
    final double latDelta = radiusMiles * degreesLatitudePerMile;
    final double cosLat = math.cos(center.latitude * math.pi / 180).abs();
    final double lonDelta = cosLat < 0.01 ? latDelta : latDelta / cosLat;
    return _GeoBBox(
      center.longitude - lonDelta,
      center.latitude - latDelta,
      center.longitude + lonDelta,
      center.latitude + latDelta,
    );
  }

  // -------------------------------------------------------------------------
  // Photon
  // -------------------------------------------------------------------------

  Future<List<GeocodingResult>> _photonSearch(
    String query, {
    LatLng? userPosition,
    _GeoBBox? bbox,
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

    // Restrict results to the box (Photon bbox: minLon,minLat,maxLon,maxLat).
    if (bbox != null) {
      params['bbox'] =
          '${bbox.minLon},${bbox.minLat},${bbox.maxLon},${bbox.maxLat}';
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
    _GeoBBox? bbox,
  }) async {
    final Map<String, String> params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '$nominatimMaxResults',
      'addressdetails': '1',
      'countrycodes': 'us',
    };

    // Restrict to the box. Nominatim viewbox is two opposite corners as
    // lon,lat,lon,lat; bounded=1 makes it a hard limit, not just a bias.
    if (bbox != null) {
      params['viewbox'] =
          '${bbox.minLon},${bbox.maxLat},${bbox.maxLon},${bbox.minLat}';
      params['bounded'] = '1';
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

    final String shortName = _nominatimShortName(item, displayName);

    return GeocodingResult(
      displayName: displayName,
      shortName: shortName,
      position: LatLng(lat, lon),
    );
  }

  /// Builds a clean option label like "123 Main St, Springfield" from
  /// Nominatim's structured `address` (so the street NUMBER is visible in the
  /// list). Falls back to the first parts of [displayName] when the structured
  /// fields aren't present (e.g. a place or park).
  String _nominatimShortName(Map<String, dynamic> item, String displayName) {
    final Map<String, dynamic>? addr =
        item['address'] as Map<String, dynamic>?;
    if (addr != null) {
      final String houseNo = (addr['house_number'] as String?) ?? '';
      final String road = (addr['road'] as String?) ?? '';
      final String city = (addr['city'] as String?) ??
          (addr['town'] as String?) ??
          (addr['village'] as String?) ??
          (addr['hamlet'] as String?) ??
          '';
      final String streetLine = <String>[
        if (houseNo.isNotEmpty) houseNo,
        if (road.isNotEmpty) road,
      ].join(' ');
      final String label = <String>[
        if (streetLine.isNotEmpty) streetLine,
        if (city.isNotEmpty) city,
      ].join(', ');
      if (label.isNotEmpty) return label;
    }
    // Fallback: first two comma-parts of the full display name.
    final List<String> parts = displayName.split(', ');
    return parts.length >= 2 ? '${parts[0]}, ${parts[1]}' : parts[0];
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

/// A lon/lat bounding box used to scope geocoder queries (local-first search).
class _GeoBBox {
  const _GeoBBox(this.minLon, this.minLat, this.maxLon, this.maxLat);

  /// The continental-US box — the "wide" fallback so results stay in the USA
  /// instead of going worldwide.
  const _GeoBBox.unitedStates()
      : minLon = usBboxMinLon,
        minLat = usBboxMinLat,
        maxLon = usBboxMaxLon,
        maxLat = usBboxMaxLat;

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;
}
