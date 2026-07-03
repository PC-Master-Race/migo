// migo_maplibre_view.dart — The MapLibre GL basemap (migration in progress).
//
// WHY: flutter_map is a 2D raster/canvas renderer — it cannot tilt. The
// Google/Waze angled navigation view needs a real GL engine with a pitched
// camera. MapLibre GL Native renders our exact MapTiler styles (dark matter /
// bright) on the GPU with proper fonts, and its camera has bearing + TILT.
//
// STATUS (phased port, flag: USE_MAPLIBRE in env.json):
//   ✅ Phase 1 — style rendering, dark/light switching
//   ✅ Phase 2 — camera: follow, heading-up bearing, 55° tilt during nav
//   ✅ Phase 3 — neon route as native line layers (glow/body/core)
//   ✅ placeholder user puck + destination dot (circle layers)
//   ⬜ Phase 4 — avatar images as symbols (Tux included), hazard/ALPR/gas/POI
//                markers, tap handling
//   ⬜ Phase 5 — gesture-aware follow pause/resume parity, zoom-mode sync,
//                then flip the default and retire the flutter_map path
//
// This widget is deliberately SELF-CONTAINED: it manages its own camera and
// layers from the same providers the flutter_map path uses, so map_screen
// only has to choose which map widget to build.

import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../constants.dart';
import '../../models/route_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/routing_provider.dart';
import '../../providers/vector_tiles_provider.dart';
import '../../theme/bravo_theme.dart';

class MigoMapLibreView extends ConsumerStatefulWidget {
  const MigoMapLibreView({super.key});

  @override
  ConsumerState<MigoMapLibreView> createState() => _MigoMapLibreViewState();
}

class _MigoMapLibreViewState extends ConsumerState<MigoMapLibreView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;

  /// Camera follow pauses for a few seconds after ANY user touch on the map
  /// (simple + reliable gesture detection; Phase 5 refines this to match the
  /// flutter_map path's recenter-button flow).
  DateTime _lastUserTouch = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _following =>
      DateTime.now().difference(_lastUserTouch).inSeconds > 8;

  /// Last route we drew, so we only rewrite the GeoJSON when it changes.
  BravoRoute? _drawnRoute;

  /// Last camera state we commanded — used as a DEADBAND: a stationary car's
  /// GPS jitter must not re-animate the camera every second, because constant
  /// camera motion makes the label engine endlessly re-run collision
  /// placement (street names blinking in/out and flipping orientation).
  ll.LatLng? _lastCamTarget;
  double _lastCamBearing = 0;
  double _lastCamTilt = -1;

  // ---------------------------------------------------------------------------
  // Sources / layers
  // ---------------------------------------------------------------------------

  static const String _routeSource = 'migo-route';
  static const String _meSource = 'migo-me';
  static const String _destSource = 'migo-dest';

  Future<void> _onStyleLoaded() async {
    final MapLibreMapController c = _controller!;

    // Empty GeoJSON shells — updated in place as data arrives.
    await c.addSource(_routeSource,
        const GeojsonSourceProperties(data: _emptyCollection));
    await c.addSource(
        _meSource, const GeojsonSourceProperties(data: _emptyCollection));
    await c.addSource(
        _destSource, const GeojsonSourceProperties(data: _emptyCollection));

    // Neon route tube — same three-layer trick as the flutter_map path:
    // soft glow halo, bright body, hot near-white core.
    await c.addLineLayer(
      _routeSource,
      'migo-route-glow',
      LineLayerProperties(
        lineColor: _hex(migoRouteNeon),
        lineWidth: routePolylineWidthDp + 7,
        lineOpacity: 0.28,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addLineLayer(
      _routeSource,
      'migo-route-body',
      LineLayerProperties(
        lineColor: _hex(migoRouteNeon),
        lineWidth: routePolylineWidthDp,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addLineLayer(
      _routeSource,
      'migo-route-core',
      LineLayerProperties(
        lineColor: _hex(migoRouteNeonCore),
        lineWidth: routePolylineWidthDp * 0.35,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // Destination dot (coral, white ring).
    await c.addCircleLayer(
      _destSource,
      'migo-dest-dot',
      CircleLayerProperties(
        circleColor: _hex(migoCoral),
        circleRadius: 9,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.5,
      ),
    );

    // Placeholder user puck (Phase 4 replaces with the avatar/Tux symbol):
    // white ring + neon center, always screen-upright.
    await c.addCircleLayer(
      _meSource,
      'migo-me-dot',
      CircleLayerProperties(
        circleColor: _hex(migoRouteNeon),
        circleRadius: 10,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );

    _styleReady = true;
    // Draw whatever state already exists (style loads after first data often).
    _syncRoute(ref.read(activeRouteProvider).valueOrNull);
    final Position? p = ref.read(positionStreamProvider).valueOrNull;
    if (p != null) _syncMe(ll.LatLng(p.latitude, p.longitude));
  }

  // ---------------------------------------------------------------------------
  // Data sync
  // ---------------------------------------------------------------------------

  static const Map<String, dynamic> _emptyCollection = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  Map<String, dynamic> _pointFeature(ll.LatLng p) => <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <dynamic>[
          <String, dynamic>{
            'type': 'Feature',
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[p.longitude, p.latitude],
            },
          },
        ],
      };

  Future<void> _syncRoute(BravoRoute? route) async {
    if (!_styleReady || _controller == null) return;
    if (identical(route, _drawnRoute)) return;
    _drawnRoute = route;

    if (route == null || route.waypoints.isEmpty) {
      await _controller!.setGeoJsonSource(_routeSource, _emptyCollection);
      await _controller!.setGeoJsonSource(_destSource, _emptyCollection);
      return;
    }
    await _controller!.setGeoJsonSource(_routeSource, <String, dynamic>{
      'type': 'FeatureCollection',
      'features': <dynamic>[
        <String, dynamic>{
          'type': 'Feature',
          'geometry': <String, dynamic>{
            'type': 'LineString',
            'coordinates': route.waypoints
                .map((ll.LatLng p) => <double>[p.longitude, p.latitude])
                .toList(),
          },
        },
      ],
    });
    await _controller!
        .setGeoJsonSource(_destSource, _pointFeature(route.destination));
  }

  Future<void> _syncMe(ll.LatLng p) async {
    if (!_styleReady || _controller == null) return;
    await _controller!.setGeoJsonSource(_meSource, _pointFeature(p));
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  /// One camera update per GPS fix (~1 Hz). The NATIVE side interpolates the
  /// movement over the animation duration — that's what makes MapLibre feel
  /// silky without any per-frame Dart work.
  Future<void> _onFix(Position p) async {
    final ll.LatLng here = ll.LatLng(p.latitude, p.longitude);
    unawaited(_syncMe(here));
    if (!_following || _controller == null) return;

    final bool navigating = ref.read(destinationProvider) != null;
    final double? heading = ref.read(displayedHeadingProvider) ??
        ((p.heading.isFinite && p.heading >= 0) ? p.heading : null);

    final double bearing = navigating && heading != null ? heading : 0;
    final double tilt =
        navigating ? navCameraTiltDegrees : browseCameraTiltDegrees;

    // DEADBAND: skip the update entirely when nothing meaningful changed —
    // under ~5 m of movement, ~3° of bearing, same tilt. A parked car's
    // jitter otherwise keeps the camera in perpetual motion and the street
    // labels in perpetual re-placement (the blinking).
    final bool moved = _lastCamTarget == null ||
        const ll.Distance().as(ll.LengthUnit.Meter, _lastCamTarget!, here) >
            5.0;
    final double bearingDelta =
        ((bearing - _lastCamBearing).abs() + 360) % 360;
    final bool turned = bearingDelta > 3 && bearingDelta < 357;
    final bool tilted = tilt != _lastCamTilt;
    if (!moved && !turned && !tilted) return;
    _lastCamTarget = here;
    _lastCamBearing = bearing;
    _lastCamTilt = tilt;

    final CameraPosition target = CameraPosition(
      target: LatLng(p.latitude, p.longitude),
      zoom: navigating ? mapNavigationZoom : (_controller!
              .cameraPosition?.zoom ??
          mapFirstFixZoom),
      bearing: bearing,
      // THE ANGLED VIEW: pitch the camera during navigation. With tilt, the
      // visible map extends far ahead of the puck naturally — no manual
      // look-ahead offset needed like on the flat map.
      tilt: tilt,
    );
    unawaited(_controller!.animateCamera(
      CameraUpdate.newCameraPosition(target),
      duration: const Duration(milliseconds: 900),
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // React to new fixes + route changes.
    ref.listen<AsyncValue<Position>>(positionStreamProvider,
        (AsyncValue<Position>? prev, AsyncValue<Position> next) {
      final Position? p = next.valueOrNull;
      if (p != null) _onFix(p);
    });
    ref.listen<AsyncValue<BravoRoute?>>(activeRouteProvider,
        (AsyncValue<BravoRoute?>? prev, AsyncValue<BravoRoute?> next) {
      _syncRoute(next.valueOrNull);
    });

    final Position? p = ref.read(positionStreamProvider).valueOrNull;

    // Style JSON with Migo's treatments (Google-night recolor, park
    // injection, label boost) — stock Dark Matter is unreadably black.
    final AsyncValue<String> styleAsync = ref.watch(
        dark ? maplibreDarkStyleProvider : maplibreLightStyleProvider);
    final String? styleJson = styleAsync.valueOrNull;
    if (styleJson == null) {
      // Style still downloading (or failed): show a quiet placeholder in the
      // right base color rather than flashing the raw unstyled map.
      return Container(
        color: dark ? const Color(0xFF1E2836) : migoCream,
        alignment: Alignment.center,
        child: styleAsync.hasError
            ? Text('Map style failed to load — check connection',
                style: TextStyle(
                    color: dark ? Colors.white70 : Colors.black54))
            : const CircularProgressIndicator(color: migoRouteNeon),
      );
    }

    // Pausing follow on touch: any pointer contact holds the camera still
    // for 8 s so the user can look around; following resumes automatically.
    return Listener(
      onPointerDown: (_) => _lastUserTouch = DateTime.now(),
      child: MapLibreMap(
        key: ValueKey<bool>(dark), // rebuild on theme flip → style reloads
        styleString: styleJson,
        initialCameraPosition: CameraPosition(
          target: p != null
              ? LatLng(p.latitude, p.longitude)
              : const LatLng(34.0975, -117.6484), // Upland fallback
          zoom: mapFirstFixZoom,
        ),
        onMapCreated: (MapLibreMapController c) {
          _controller = c;
          _styleReady = false; // theme flip recreates the map — re-add layers
          _drawnRoute = null;
        },
        onStyleLoadedCallback: _onStyleLoaded,
        myLocationEnabled: false, // we draw our own puck/avatar
        // Compass button appears when the map is rotated; tapping it snaps
        // back to north — the only way home after a two-finger rotate.
        compassEnabled: true,
        compassViewMargins: const Point<num>(16, 160),
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: true,
        trackCameraPosition: true,
        attributionButtonPosition: AttributionButtonPosition.bottomRight,
      ),
    );
  }
}

/// '#RRGGBB' for MapLibre style properties.
String _hex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
