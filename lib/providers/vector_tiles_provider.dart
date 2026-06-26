// vector_tiles_provider.dart — Client-side vector basemap source + theme.
//
// The style is built INLINE in Dart (not loaded from an asset) on purpose:
// asset-bundle reloading proved unreliable during development, so embedding the
// style in code guarantees a hot restart always picks up changes. The style is
// deliberately simple — only the syntax the Dart `vector_tile_renderer`
// supports (constant paints, simple == / in / has filters, get-name labels) —
// because Protomaps' own modern style uses expressions the renderer can't read.
//
// SOURCE: a Protomaps PMTiles file (OpenStreetMap data, ODbL). Range Requests
// fetch only the tiles in view. DEV source for now (a dated planet build);
// Session 3 swaps it for a regional file we host/bundle for offline + privacy.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Temporary hosted source — a Protomaps dated daily planet build.
/// Bump this date from https://maps.protomaps.com/builds/ if it ever 404s.
const String vectorTilesPmtilesUrl =
    'https://build.protomaps.com/20260624.pmtiles';

/// Everything the vector map layer needs: the tile source + both themes.
typedef MapVectorBundle = ({
  PmTilesVectorTileProvider tiles,
  vtr.Theme light,
  vtr.Theme dark,
});

final FutureProvider<MapVectorBundle> mapVectorBundleProvider =
    FutureProvider<MapVectorBundle>((Ref ref) async {
  final PmTilesVectorTileProvider tiles =
      await PmTilesVectorTileProvider.fromSource(vectorTilesPmtilesUrl);
  return (
    tiles: tiles,
    light: vtr.ThemeReader().read(_baseStyle(dark: false)),
    dark: vtr.ThemeReader().read(_baseStyle(dark: true)),
  );
});

/// Minimal Protomaps-schema style using only renderer-supported syntax.
Map<String, dynamic> _baseStyle({required bool dark}) {
  final Map<String, String> c = dark
      ? <String, String>{
          'bg': '#13110f', 'earth': '#1b1815', 'water': '#0e1d2b',
          'park': '#152318', 'other': '#3a3a3a', 'minor': '#565656',
          'major': '#777777', 'hwy': '#b58a34', 'rail': '#3a3a3a',
          'label': '#ffffff', 'halo': '#0a0a0a',
        }
      : <String, String>{
          'bg': '#f4efe7', 'earth': '#faf7f0', 'water': '#a9d3e6',
          'park': '#cfe6c8', 'other': '#e3ddd2', 'minor': '#ffffff',
          'major': '#ffffff', 'hwy': '#f6d27a', 'rail': '#cfc7ba',
          'label': '#1c1712', 'halo': '#ffffff',
        };

  Map<String, dynamic> road(
          String id, String kind, String color, double width) =>
      <String, dynamic>{
        'id': id,
        'type': 'line',
        'source': 'protomaps',
        'source-layer': 'roads',
        'filter': <dynamic>['==', 'kind', kind],
        'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
        'paint': <String, dynamic>{'line-color': color, 'line-width': width},
      };

  return <String, dynamic>{
    'version': 8,
    'sources': <String, dynamic>{
      'protomaps': <String, dynamic>{'type': 'vector', 'url': 'pmtiles://migo'},
    },
    'layers': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'bg',
        'type': 'background',
        'paint': <String, dynamic>{'background-color': c['bg']},
      },
      <String, dynamic>{
        'id': 'earth',
        'type': 'fill',
        'source': 'protomaps',
        'source-layer': 'earth',
        'paint': <String, dynamic>{'fill-color': c['earth']},
      },
      <String, dynamic>{
        'id': 'park',
        'type': 'fill',
        'source': 'protomaps',
        'source-layer': 'landuse',
        'filter': <dynamic>[
          'in', 'kind', 'park', 'forest', 'wood', 'grass', 'meadow',
          'nature_reserve', 'golf_course', 'recreation_ground',
        ],
        'paint': <String, dynamic>{'fill-color': c['park']},
      },
      <String, dynamic>{
        'id': 'water',
        'type': 'fill',
        'source': 'protomaps',
        'source-layer': 'water',
        'paint': <String, dynamic>{'fill-color': c['water']},
      },
      road('r_other', 'other', c['other']!, 1.5),
      road('r_minor', 'minor_road', c['minor']!, 2.5),
      road('r_major', 'major_road', c['major']!, 3.5),
      road('r_rail', 'rail', c['rail']!, 1.0),
      road('r_hwy', 'highway', c['hwy']!, 4.5),
      <String, dynamic>{
        'id': 'road_labels',
        'type': 'symbol',
        'source': 'protomaps',
        'source-layer': 'roads',
        'filter': <dynamic>['has', 'name'],
        'layout': <String, dynamic>{
          'symbol-placement': 'line',
          'text-field': <dynamic>['get', 'name'],
          'text-font': <String>['Noto Sans Medium'],
          'text-size': 15,
        },
        'paint': <String, dynamic>{
          'text-color': c['label'],
          'text-halo-color': c['halo'],
          'text-halo-width': 1.6,
        },
      },
      <String, dynamic>{
        'id': 'place_labels',
        'type': 'symbol',
        'source': 'protomaps',
        'source-layer': 'places',
        'filter': <dynamic>['has', 'name'],
        'layout': <String, dynamic>{
          'text-field': <dynamic>['get', 'name'],
          'text-font': <String>['Noto Sans Regular'],
          'text-size': 16,
        },
        'paint': <String, dynamic>{
          'text-color': c['label'],
          'text-halo-color': c['halo'],
          'text-halo-width': 1.8,
        },
      },
    ],
  };
}
