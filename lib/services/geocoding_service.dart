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
  /// TIERED-DISTANCE strategy (people mostly navigate nearby):
  ///  1. NEAR — within [geocodeNearRadiusMiles]. Any hit wins outright.
  ///  2. REGION — within [geocodeRegionRadiusMiles].
  ///  3. WIDE — continental US, but ONLY when the query is specific enough
  ///     ([geocodeWideMinQueryChars] chars or [geocodeWideMinTokens] words)
  ///     that a distant match is plausibly what the user meant. A half-typed
  ///     query never surfaces something hundreds of miles away.
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

    // Query tokens, split by kind — declared FIRST because everything below
    // (passes, gate, ranking) uses them.
    final List<String> queryTokens = _tokenize(q);
    final List<String> wordTokens =
        queryTokens.where((String t) => !_isNumeric(t)).toList();
    final List<String> numberTokens =
        queryTokens.where(_isNumeric).toList();

    // PHOTON FIRST, ALWAYS. Photon is an autocomplete geocoder — it matches
    // partial input ("1515 V" → 1515 V-something streets) and handles house
    // numbers. Nominatim needs complete words, so leading with it on
    // address-like input made half-typed searches come back empty nearby and
    // let far-region junk fill the list. Nominatim is the fallback for full
    // addresses Photon fumbles.
    Future<List<GeocodingResult>> runPass(_GeoBBox bbox) async {
      List<GeocodingResult> results =
          await _photonSearch(q, userPosition: userPosition, bbox: bbox);
      String engine = 'photon';

      // PARTIAL-ADDRESS RESCUE: with a house number present, Photon only
      // matches complete address points — "1515 ver" finds nothing even
      // though Verness St is right there. Retry with the street words only,
      // so matching STREETS appear while the user is still typing; the
      // number-aware ranking sorts exact address hits first once they exist.
      if (results.isEmpty && numberTokens.isNotEmpty && wordTokens.isNotEmpty) {
        results = await _photonSearch(wordTokens.join(' '),
            userPosition: userPosition, bbox: bbox);
        engine = 'photon(street-only)';
      }

      if (results.isEmpty) {
        results = await _nominatimSearch(q,
            userPosition: userPosition, bbox: bbox);
        engine = 'nominatim(fallback)';
      }
      for (final GeocodingResult r in results) {
        debugPrint('[geocode] $engine "$q" → "${r.shortName}" @ '
            '${r.position.latitude.toStringAsFixed(6)},'
            '${r.position.longitude.toStringAsFixed(6)}');
      }
      return results;
    }

    // RELEVANCE GATE: geocoders fuzzy-match loosely — "1515 ver" can come
    // back as places containing neither "1515" nor "ver". Every result must
    // actually match what was typed:
    //   • every WORD token must prefix-match a word in the result
    //     ("ver" → Verness ✓, San Fernando Rd ✗)
    //   • NUMBER tokens (house numbers) rank matches first but don't drop
    //     number-less street results — the exact address pin may not exist
    //     in OSM even when the street does.
    bool relevant(GeocodingResult r) {
      final List<String> resultWords =
          _tokenize('${r.displayName} ${r.shortName}');
      // Number-only query ("1515"): the number itself must appear — without
      // this, no word tokens meant EVERYTHING passed (the "1 real result
      // plus irrelevant junk" bug).
      if (wordTokens.isEmpty) {
        return numberTokens.every((String t) =>
            resultWords.any((String w) => w.startsWith(t)));
      }
      return wordTokens.every((String t) =>
          resultWords.any((String w) => w.startsWith(t)));
    }

    bool hasNumbers(GeocodingResult r) {
      if (numberTokens.isEmpty) return false;
      final List<String> resultWords =
          _tokenize('${r.displayName} ${r.shortName}');
      return numberTokens.every((String t) =>
          resultWords.any((String w) => w.startsWith(t)));
    }

    // NEAR matches rank first; REGION matches fill the remaining slots BELOW
    // them (closer stays on top until it stops matching — then the next tier
    // takes over). WIDE only joins for specific-enough queries.
    final List<GeocodingResult> merged = <GeocodingResult>[];
    void addNew(List<GeocodingResult> batch) {
      for (final GeocodingResult r in batch) {
        if (merged.length >= nominatimMaxResults) return;
        if (!relevant(r)) continue; // must match what was actually typed
        final bool duplicate = merged.any((GeocodingResult m) =>
            m.displayName == r.displayName ||
            const Distance().as(LengthUnit.Meter, m.position, r.position) <
                50);
        if (!duplicate) merged.add(r);
      }
    }

    // Hard client-side tier enforcement: the bbox params SHOULD constrain the
    // geocoders, but we've seen distant hits leak through — so each tier's
    // results are also distance-filtered on our side. Trust, but verify.
    List<GeocodingResult> withinMiles(
        List<GeocodingResult> results, double radiusMiles) {
      if (userPosition == null) return results;
      const Distance d = Distance();
      return results
          .where((GeocodingResult r) =>
              d.as(LengthUnit.Meter, userPosition, r.position) <=
              radiusMiles * metersPerMile)
          .toList();
    }

    if (userPosition != null) {
      // --- Pass 1: NEAR — everyday-trip radius. ---
      addNew(withinMiles(
          await runPass(_bboxAround(userPosition, geocodeNearRadiusMiles)),
          geocodeNearRadiusMiles));

      // --- Pass 2: REGION — fill remaining slots from day-trip radius. ---
      if (merged.length < nominatimMaxResults) {
        addNew(withinMiles(
            await runPass(_bboxAround(userPosition, geocodeRegionRadiusMiles)),
            geocodeRegionRadiusMiles));
      }
    }

    // --- Pass 3: WIDE — continental US. ONLY for specific-enough queries,
    // with or without a GPS anchor: a half-typed query must never surface
    // something hundreds of miles away. (No results is better guidance —
    // it says "keep typing" — than a confident wrong city.)
    final bool specificEnough = q.length >= geocodeWideMinQueryChars ||
        q.split(RegExp(r'\s+')).length >= geocodeWideMinTokens;
    if (merged.length < nominatimMaxResults && specificEnough) {
      addNew(await runPass(const _GeoBBox.unitedStates()));
    }
    // TWO-STAGE ADDRESS RESOLVE (Ruben's algorithm): when the user has typed
    // a house number but no result carries it yet, we already KNOW the
    // candidate streets — so compose the full address ourselves
    // ("1515" + "Verness Street, West Covina") and look THAT up directly.
    // Nominatim can't match partials, but it resolves complete composed
    // addresses beautifully. This is what makes "1515 ver" produce
    // "1515 Verness St" without typing the whole thing.
    if (numberTokens.isNotEmpty &&
        merged.isNotEmpty &&
        !merged.any(hasNumbers)) {
      for (final GeocodingResult street
          in merged.where((GeocodingResult r) => !hasNumbers(r)).take(2)) {
        final String composed =
            '${numberTokens.join(' ')} ${street.displayName}';
        final List<GeocodingResult> hits = await _nominatimSearch(
          composed,
          userPosition: userPosition,
          // Tight box around the candidate street — we know where it is.
          bbox: _bboxAround(street.position, 5),
        );
        GeocodingResult? exact;
        for (final GeocodingResult h in hits) {
          if (hasNumbers(h)) {
            exact = h;
            break;
          }
        }
        if (exact != null) {
          debugPrint('[geocode] two-stage resolve: "$composed" → '
              '"${exact.shortName}"');
          merged.insert(0, exact);
          break;
        }
      }
      if (merged.length > nominatimMaxResults) {
        merged.removeRange(nominatimMaxResults, merged.length);
      }
    }

    // CENSUS FALLBACK: if the user typed a house number and nothing above
    // resolved it, ask the US Census geocoder — TIGER address ranges know
    // essentially every US address, including the many OSM is missing
    // (e.g. "2229 S Mountain Ave, Ontario" — real place, absent from OSM).
    if (numberTokens.isNotEmpty &&
        wordTokens.isNotEmpty &&
        !merged.any(hasNumbers)) {
      final GeocodingResult? census = await _censusSearch(q);
      if (census != null) {
        debugPrint('[geocode] census resolved "${census.shortName}"');
        merged.insert(0, census);
        if (merged.length > nominatimMaxResults) {
          merged.removeRange(nominatimMaxResults, merged.length);
        }
      }
    }

    // Final ordering: results matching the typed HOUSE NUMBER outrank ones
    // that only match the street; within each group, nearest first.
    if (userPosition != null) _sortByDistance(merged, userPosition);
    if (numberTokens.isNotEmpty) {
      final List<GeocodingResult> withNumber =
          merged.where(hasNumbers).toList();
      final List<GeocodingResult> withoutNumber =
          merged.where((GeocodingResult r) => !hasNumbers(r)).toList();
      return <GeocodingResult>[...withNumber, ...withoutNumber];
    }
    return merged;
  }

  /// US Census geocoder lookup — returns the best TIGER address-range match,
  /// or null. Only called when OSM couldn't resolve a typed house number.
  Future<GeocodingResult?> _censusSearch(String query) async {
    final Uri uri = Uri.parse(censusGeocoderUrl).replace(
      queryParameters: <String, String>{
        'address': query,
        'benchmark': 'Public_AR_Current',
        'format': 'json',
      },
    );
    try {
      final http.Response response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> matches =
          ((body['result'] as Map<String, dynamic>?)?['addressMatches']
                  as List<dynamic>?) ??
              <dynamic>[];
      if (matches.isEmpty) return null;
      final Map<String, dynamic> m = matches.first as Map<String, dynamic>;
      final Map<String, dynamic> coords =
          m['coordinates'] as Map<String, dynamic>;
      final String matched =
          (m['matchedAddress'] as String?) ?? query.toUpperCase();
      final String pretty = _titleCase(matched);
      return GeocodingResult(
        displayName: '$pretty (US Census)',
        shortName: pretty,
        position: LatLng(
          (coords['y'] as num).toDouble(),
          (coords['x'] as num).toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// "2229 S MOUNTAIN AVE, ONTARIO, CA" → "2229 S Mountain Ave, Ontario, Ca".
  String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((String w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Lowercase word tokens: letters+digits only, split on everything else.
  List<String> _tokenize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList();

  bool _isNumeric(String t) => RegExp(r'^\d+$').hasMatch(t);

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
      // Ask for MORE than we display: Photon's own ranking often buries the
      // exact address match below fuzzy junk — our relevance gate + number
      // ranking then picks the right 5 from a deeper pool.
      'limit': '12',
      'lang': 'en',
    };

    // When lat/lon are provided Photon weights distance —
    // zoom + location_bias_scale strengthen that pull so nearby matches
    // outrank bigger/more-famous distant ones while typing.
    if (userPosition != null) {
      params['lat'] = userPosition.latitude.toStringAsFixed(6);
      params['lon'] = userPosition.longitude.toStringAsFixed(6);
      params['zoom'] = '14';
      params['location_bias_scale'] = '0.5';
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
