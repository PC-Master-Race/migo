// vector_tiles_provider.dart — Vector basemap: hosted styles + label boosting.
//
// HISTORY: the first pipeline used Protomaps PMTiles + an inline Dart style.
// Fill layers rendered but the Dart renderer never drew LINES or SYMBOLS from
// those tiles — even with a dead-simple style (see HANDOFF_FABLE.md, problem
// 3). Rather than fight the renderer, we switched to the combo the
// vector_map_tiles README explicitly verifies: OpenMapTiles-schema tiles +
// hosted styles from MapTiler, read via StyleReader (which resolves the
// style's sources/sprites automatically).
//
//   dark:  Dark Matter — a true dark basemap (the Google/Waze look)
//   light: OSM Bright
//
// (MapTiler over Stadia: Stadia slashed its free tier in early 2026;
// MapTiler's free plan is 100k requests + 5k sessions/month, and overruns
// suspend rather than bill. Both are README-verified — switching providers
// is only a matter of these two URLs.)
//
// LABEL BOOSTING: Ruben drives with a 7" screen; default label sizes are too
// small to read at a glance. We fetch the style JSON, enlarge + brighten the
// text layers in Dart (street names get fixed zoom-scaled sizes; everything
// else gets multiplied), then build the Theme from the modified JSON.
// StyleReader still supplies the tile providers + sprites.
//
// API KEY: comes from --dart-define MAPTILER_API_KEY (add it to env.json).
// Without a key the map silently stays on the raster fallback — same graceful
// degradation as Supabase-less offline mode. Free key: cloud.maptiler.com
// (no credit card).
//
// OFFLINE/PRIVACY: hosted tiles send viewport coords to MapTiler (same class
// of exposure as OSM raster tiles today). Revisit self-hosted/offline PMTiles
// once the renderer supports Protomaps tiles or we host OpenMapTiles-schema
// tiles ourselves. TODO: [self-host tiles for production privacy]

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// MapTiler API key, injected at run time. Empty string = not configured.
const String maptilerApiKey = String.fromEnvironment('MAPTILER_API_KEY');

/// True when a MapTiler key is present — gates the whole vector pipeline.
bool get vectorTilesConfigured => maptilerApiKey.isNotEmpty;

/// Hosted style URLs ({key} is substituted by StyleReader / our own fetch).
const String _darkStyleUrl =
    'https://api.maptiler.com/maps/darkmatter/style.json?key={key}';
const String _lightStyleUrl =
    'https://api.maptiler.com/maps/bright/style.json?key={key}';

/// One ready-to-render style: boosted theme + tile providers + sprites.
typedef VectorStyle = ({
  vtr.Theme theme,
  TileProviders providers,
  SpriteStyle? sprites,
});

/// Both themes, loaded once at startup (hot restart to re-run).
typedef VectorStylePair = ({VectorStyle light, VectorStyle dark});

final FutureProvider<VectorStylePair> mapVectorStylesProvider =
    FutureProvider<VectorStylePair>((Ref ref) async {
  final VectorStyle dark = await _readBoostedStyle(_darkStyleUrl, dark: true);
  final VectorStyle light =
      await _readBoostedStyle(_lightStyleUrl, dark: false);
  return (light: light, dark: dark);
});

/// Reads a hosted style twice: once via StyleReader (providers + sprites,
/// with all source/TileJSON resolution handled for us) and once raw (so we
/// can boost the labels before building the Theme).
Future<VectorStyle> _readBoostedStyle(String uri, {required bool dark}) async {
  final Style base = await StyleReader(
    uri: uri,
    apiKey: maptilerApiKey,
  ).read();

  vtr.Theme theme = base.theme;
  try {
    final String resolved = uri.replaceAll('{key}', maptilerApiKey);
    final http.Response response =
        await http.get(Uri.parse(resolved)).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final Map<String, dynamic> styleJson =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (dark) {
        _applyGoogleNightPalette(styleJson);
        _injectParkLayersIfMissing(styleJson);
      }
      _boostLabels(styleJson, dark: dark);
      theme = vtr.ThemeReader().read(styleJson);
    }
  } catch (e) {
    // Boosting is progressive enhancement — the un-boosted theme still works.
    debugPrint('[vector] label boost failed, using stock theme: $e');
  }

  return (theme: theme, providers: base.providers, sprites: base.sprites);
}

// --- GOOGLE-NIGHT RECOLORING ---
// Dark Matter's roads are near-black on black — invisible while driving.
// Palette sampled from a real Google Maps dark-mode NAVIGATION screenshot
// (Ruben provided it): deep desaturated navy ground, minor streets clearly
// lighter blue-gray, water darker than ground, parks dark TEAL (not green),
// and highways just a lighter blue-gray (nav mode has no gold highways —
// that's Google's older embedded-map palette).

const String _nightBg = '#1e2836'; // ground / generic land (deep navy)
const String _nightWater = '#0f1c2e'; // darker than ground
const String _nightPark = '#2b4f4a'; // teal-green, brightened per feedback
const String _nightBuilding = '#26303f';
const String _nightRoad = '#4b5f78'; // minor streets — brightened per feedback
const String _nightRoadCasing = '#18202c';
const String _nightHighway = '#647894'; // majors: one step lighter again
const String _nightHighwayCasing = '#18202c';
const String _nightBoundary = '#4b6878';

/// True when a fill layer draws parks/greenery. OpenMapTiles puts parks in a
/// dedicated 'park' source-layer; other vegetation hides in 'landcover' /
/// 'landuse' layers whose id often says nothing — the vegetation class lives
/// in the layer's FILTER. So we keyword-match the id AND the encoded filter.
bool _isVegetation(
  Map<String, dynamic> layer, {
  required String sourceLayer,
  required String id,
}) {
  if (sourceLayer == 'park') return true;
  if (sourceLayer != 'landcover' && sourceLayer != 'landuse' &&
      !id.contains('park')) {
    return false;
  }
  const List<String> keywords = <String>[
    'park', 'wood', 'forest', 'grass', 'meadow', 'garden', 'golf',
    'cemetery', 'zoo', 'green', 'nature_reserve', 'recreation', 'wetland',
    'vegetation', 'scrub', 'farmland', 'orchard',
  ];
  final String haystack =
      '$id ${jsonEncode(layer['filter'] ?? '')}'.toLowerCase();
  return keywords.any(haystack.contains);
}

void _applyGoogleNightPalette(Map<String, dynamic> styleJson) {
  final List<dynamic> layers =
      (styleJson['layers'] as List<dynamic>?) ?? <dynamic>[];
  for (final dynamic l in layers) {
    if (l is! Map<String, dynamic>) continue;
    final String type = (l['type'] as String?) ?? '';
    final String id = ((l['id'] as String?) ?? '').toLowerCase();
    final String sourceLayer = (l['source-layer'] as String?) ?? '';
    final Map<String, dynamic> paint =
        (l['paint'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    l['paint'] = paint;

    if (type == 'background') {
      paint['background-color'] = _nightBg;
    } else if (type == 'fill') {
      if (sourceLayer == 'water') {
        paint['fill-color'] = _nightWater;
      } else if (sourceLayer == 'building') {
        paint['fill-color'] = _nightBuilding;
      } else if (_isVegetation(l, sourceLayer: sourceLayer, id: id)) {
        paint['fill-color'] = _nightPark;
      } else {
        // All other landuse: flatten to the ground color so no near-black
        // patches survive against the new lighter background.
        paint['fill-color'] = _nightBg;
      }
    } else if (type == 'line') {
      if (sourceLayer == 'transportation') {
        final bool isHighway =
            id.contains('motorway') || id.contains('trunk');
        final bool isCasing = id.contains('casing');
        if (isHighway) {
          paint['line-color'] =
              isCasing ? _nightHighwayCasing : _nightHighway;
        } else {
          paint['line-color'] = isCasing ? _nightRoadCasing : _nightRoad;
        }
      } else if (sourceLayer == 'boundary') {
        paint['line-color'] = _nightBoundary;
      } else if (sourceLayer == 'waterway') {
        paint['line-color'] = _nightWater;
      }
    }
  }
}

// --- PARK LAYER INJECTION ---
// Dark Matter is Carto's DATA-VIZ basemap: deliberately minimal, and it
// mostly omits park/vegetation layers from the STYLE even though MapTiler's
// tiles carry the data (OpenMapTiles schema: 'park' + 'landcover' source
// layers). Recoloring can't paint a layer that doesn't exist — so when the
// style has no park fill, we add our own, inserted below the road lines.

void _injectParkLayersIfMissing(Map<String, dynamic> styleJson) {
  final List<dynamic> layers =
      (styleJson['layers'] as List<dynamic>?) ?? <dynamic>[];

  // Already has a park fill? (Also counts one our recolor just painted.)
  final bool hasPark = layers.any((dynamic l) =>
      l is Map<String, dynamic> &&
      l['type'] == 'fill' &&
      l['source-layer'] == 'park');
  if (hasPark) {
    debugPrint('[vector] style already has a park fill — no injection');
    return;
  }
  debugPrint('[vector] no park fill in style — injecting park layers');

  // The style's vector source name (e.g. 'openmaptiles' / 'maptiler_planet').
  final Map<String, dynamic> sources =
      (styleJson['sources'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  String? sourceName;
  for (final MapEntry<String, dynamic> e in sources.entries) {
    if (e.value is Map<String, dynamic> &&
        (e.value as Map<String, dynamic>)['type'] == 'vector') {
      sourceName = e.key;
      break;
    }
  }
  if (sourceName == null) return;

  final List<Map<String, dynamic>> parkLayers = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'migo_park',
      'type': 'fill',
      'source': sourceName,
      'source-layer': 'park',
      'paint': <String, dynamic>{'fill-color': _nightPark},
    },
    <String, dynamic>{
      'id': 'migo_landcover_green',
      'type': 'fill',
      'source': sourceName,
      'source-layer': 'landcover',
      'filter': <dynamic>['in', 'class', 'wood', 'grass', 'wetland'],
      'paint': <String, dynamic>{'fill-color': _nightPark},
    },
  ];

  // Insert below the first line (road) layer so streets draw on top.
  int insertAt = layers.indexWhere((dynamic l) =>
      l is Map<String, dynamic> && l['type'] == 'line');
  if (insertAt < 0) insertAt = layers.length;
  layers.insertAll(insertAt, parkLayers);
}

// --- LABEL BOOSTING ---
// OpenMapTiles schema: street-name labels live in source-layer
// 'transportation_name'; city/town/suburb labels in 'place'.

/// Street labels: fixed zoom-scaled sizes, deliberately LARGE (readable at a
/// glance on a 7" screen at arm's length while driving).
Map<String, dynamic> _streetTextSize() => <String, dynamic>{
      'base': 1.2,
      'stops': <List<dynamic>>[
        <dynamic>[13, 13],
        <dynamic>[15, 17],
        <dynamic>[17, 22],
      ],
    };

void _boostLabels(Map<String, dynamic> styleJson, {required bool dark}) {
  final List<dynamic> layers =
      (styleJson['layers'] as List<dynamic>?) ?? <dynamic>[];
  for (final dynamic l in layers) {
    if (l is! Map<String, dynamic>) continue;
    if (l['type'] != 'symbol') continue;

    final Map<String, dynamic> layout =
        (l['layout'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> paint =
        (l['paint'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    l['layout'] = layout;
    l['paint'] = paint;

    final String sourceLayer = (l['source-layer'] as String?) ?? '';

    if (sourceLayer == 'transportation_name') {
      // Street names: big and bright. Google's nav labels are Roboto Medium
      // (not heavy bold) — and Roboto is Android's system font, so the
      // renderer resolves it natively.
      layout['text-size'] = _streetTextSize();
      layout['text-font'] = <String>['Roboto Medium'];
      if (dark) {
        paint['text-color'] = '#ffffff';
        paint['text-halo-color'] = '#101722'; // navy-black, per screenshot
        paint['text-halo-width'] = 2.0;
      }
    } else if (sourceLayer == 'place') {
      // Place names: scale up whatever size the style declares (only simple
      // forms — numbers and stops; expression trees are left untouched).
      _scaleTextSize(layout, 1.25);
      layout['text-font'] = <String>['Roboto Medium'];
      if (dark) {
        paint['text-color'] = '#ffffff';
        paint['text-halo-color'] = '#101722';
        paint['text-halo-width'] = 1.8;
      }
    }
  }
}

/// Multiplies layout['text-size'] by [factor] when it's a plain number or a
/// classic {stops: [[zoom, size], ...]} function. Expression arrays are left
/// alone — guessing which numeric leaf is a size corrupts styles.
void _scaleTextSize(Map<String, dynamic> layout, double factor) {
  final dynamic size = layout['text-size'];
  if (size is num) {
    layout['text-size'] = size * factor;
  } else if (size is Map<String, dynamic>) {
    final List<dynamic>? stops = size['stops'] as List<dynamic>?;
    if (stops == null) return;
    for (final dynamic stop in stops) {
      if (stop is List && stop.length == 2 && stop[1] is num) {
        stop[1] = (stop[1] as num) * factor;
      }
    }
  }
}
