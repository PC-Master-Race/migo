// poi_service.dart — Points of Interest via Overpass API (OSM).
// Only fetches when zoom >= 14 to avoid hammering the public endpoint.
// Results are cached per 0.05° bounding box (~3.5mi) for the session.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/poi_model.dart';

// OSM amenity tag → PoiCategory mapping
const Map<String, PoiCategory> _amenityMap = <String, PoiCategory>{
  'restaurant':  PoiCategory.restaurant,
  'fast_food':   PoiCategory.restaurant,
  'food_court':  PoiCategory.restaurant,
  'cafe':        PoiCategory.cafe,
  'coffee_shop': PoiCategory.cafe,
  'parking':     PoiCategory.parking,
  'pharmacy':    PoiCategory.pharmacy,
  'chemist':     PoiCategory.pharmacy,
  'atm':         PoiCategory.atm,
  'bank':        PoiCategory.atm,
  'hospital':    PoiCategory.hospital,
  'clinic':      PoiCategory.hospital,
  'fuel':        PoiCategory.gasStation,
  'hotel':       PoiCategory.hotel,
  'motel':       PoiCategory.hotel,
  'guest_house': PoiCategory.hotel,
  'supermarket': PoiCategory.grocery,
  'convenience': PoiCategory.grocery,
};

const Map<String, PoiCategory> _leisureMap = <String, PoiCategory>{
  'park':    PoiCategory.park,
  'garden':  PoiCategory.park,
  'nature_reserve': PoiCategory.park,
};

const Map<String, PoiCategory> _shopMap = <String, PoiCategory>{
  'supermarket':  PoiCategory.grocery,
  'convenience':  PoiCategory.grocery,
  'grocery':      PoiCategory.grocery,
};

class PoiService {
  PoiService._();
  static final PoiService instance = PoiService._();

  final Map<String, List<PointOfInterest>> _cache =
      <String, List<PointOfInterest>>{};

  static const double _minZoomForFetch = 14.0;
  static const double _fetchRadiusMeters = 1200; // ~0.75mi at street level

  /// Fetches nearby POIs. Returns empty list if [zoom] < [_minZoomForFetch]
  /// to avoid Overpass load at wide zoom levels.
  Future<List<PointOfInterest>> fetchNearby(
    LatLng center, {
    required double zoom,
    Set<PoiCategory> categories = const <PoiCategory>{
      PoiCategory.restaurant,
      PoiCategory.cafe,
      PoiCategory.parking,
      PoiCategory.park,
      PoiCategory.pharmacy,
    },
  }) async {
    if (zoom < _minZoomForFetch) return <PointOfInterest>[];

    final String cacheKey = _cacheKey(center, categories);
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // Build Overpass union query for all requested categories.
    final StringBuffer query = StringBuffer('[out:json][timeout:12];(');

    for (final PoiCategory cat in categories) {
      switch (cat) {
        case PoiCategory.park:
          query.write(
            'node["leisure"~"park|garden"](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});'
            'way["leisure"~"park|garden"](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});',
          );
        case PoiCategory.parking:
          query.write(
            'node["amenity"="parking"](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});'
            'way["amenity"="parking"](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});',
          );
        case PoiCategory.grocery:
          query.write(
            'node["shop"~"supermarket|convenience|grocery"](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});',
          );
        default:
          final List<String> tags = _amenityMap.entries
              .where((MapEntry<String, PoiCategory> e) => e.value == cat)
              .map((MapEntry<String, PoiCategory> e) => e.key)
              .toList();
          if (tags.isEmpty) continue;
          final String tagFilter = tags.length == 1
              ? '"amenity"="${tags.first}"'
              : '"amenity"~"${tags.join('|')}"';
          query.write(
            'node[$tagFilter](around:${_fetchRadiusMeters.round()},${center.latitude},${center.longitude});',
          );
      }
    }

    query.write(');out center body;');

    final List<PointOfInterest> pois = <PointOfInterest>[];
    try {
      final http.Response resp = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: query.toString(),
            headers: <String, String>{'User-Agent': osmUserAgent},
          )
          .timeout(const Duration(seconds: 14));

      if (resp.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(resp.body) as Map<String, dynamic>;
        final List<dynamic> elements =
            data['elements'] as List<dynamic>? ?? <dynamic>[];

        for (final dynamic el in elements) {
          final Map<String, dynamic> element = el as Map<String, dynamic>;
          final Map<String, dynamic> tags =
              element['tags'] as Map<String, dynamic>? ?? <String, dynamic>{};

          PoiCategory? cat =
              _amenityMap[tags['amenity'] as String? ?? ''] ??
              _leisureMap[tags['leisure'] as String? ?? ''] ??
              _shopMap[tags['shop'] as String? ?? ''];

          if (cat == null || !categories.contains(cat)) continue;

          // Skip POIs with no coordinates.
          final double lat = (element['lat'] as num?)?.toDouble() ??
              ((element['center'] as Map?)
                      ?.cast<String, dynamic>()['lat'] as num?)
                  ?.toDouble() ??
              0;
          if (lat == 0) continue;

          pois.add(PointOfInterest.fromOverpass(element, cat));
        }
      }
    } catch (_) {
      // Overpass failure — return whatever we have (possibly empty).
    }

    _cache[cacheKey] = pois;
    return pois;
  }

  void clearCache() => _cache.clear();

  String _cacheKey(LatLng p, Set<PoiCategory> cats) {
    final double lat = (p.latitude / 0.05).roundToDouble() * 0.05;
    final double lon = (p.longitude / 0.05).roundToDouble() * 0.05;
    final String catKey = (cats.map((PoiCategory c) => c.name).toList()
          ..sort())
        .join(',');
    return '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}:$catKey';
  }
}
