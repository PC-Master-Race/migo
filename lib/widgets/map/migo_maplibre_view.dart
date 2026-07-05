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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../constants.dart';
import '../../models/archetype_model.dart';
import '../../models/bravo_model.dart';
import '../../models/gas_model.dart';
import '../../models/hazard_model.dart';
import '../../models/poi_model.dart';
import '../../models/route_model.dart';
import '../../providers/alpr_provider.dart';
import '../../providers/archetype_provider.dart';
import '../../providers/bravo_provider.dart';
import '../../providers/gas_poi_provider.dart';
import '../../providers/hazard_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import '../../providers/routing_provider.dart';
import '../../providers/vector_tiles_provider.dart';
import '../../screens/report_gas_price_screen.dart';
import '../../theme/bravo_theme.dart';
import '../avatar/avatar_painter.dart';
import '../avatar/mystery_egg.dart';
import '../hazard_icons/hazard_icon.dart';

class MigoMapLibreView extends ConsumerStatefulWidget {
  const MigoMapLibreView({super.key, this.onLongPress});

  /// Long-press anywhere on the map — map_screen opens the save-location
  /// sheet for that exact point (alley spots, rear entrances: places whose
  /// street address points somewhere the car doesn't go).
  final void Function(ll.LatLng point)? onLongPress;

  @override
  ConsumerState<MigoMapLibreView> createState() => _MigoMapLibreViewState();
}

class _MigoMapLibreViewState extends ConsumerState<MigoMapLibreView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;

  /// Phase 5 parity: touching the map pauses following (glFollowingProvider
  /// → map_screen shows the recenter button); the button bumps
  /// glRecenterSignalProvider and we snap back.
  bool get _following => ref.read(glFollowingProvider);

  /// Last fix, kept so the recenter button can snap immediately.
  Position? _lastFix;

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
  static const String _avatarImage = 'migo-avatar';
  static const String _alprSource = 'migo-alpr';
  static const String _hazardSource = 'migo-hazards';
  static const String _gasSource = 'migo-gas';
  static const String _poiSource = 'migo-pois';

  /// POIs hide below this zoom (mirrors map_screen's _poiMinZoom gating).
  static const double _poiMinZoom = 14.0;

  /// Renders a circular pin (colored disc, white ring, white icon glyph) to
  /// a PNG and registers it — the GL twin of the widget-based map pins.
  Future<void> _addPinImage(String name, Color color, IconData glyph,
      {double size = 84}) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double r = size / 2;
    canvas.drawCircle(
      Offset(r, r + 2),
      r - 5,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(Offset(r, r), r - 5, Paint()..color = color);
    canvas.drawCircle(
      Offset(r, r),
      r - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.055
        ..color = Colors.white,
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontSize: size * 0.5,
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r - tp.width / 2, r - tp.height / 2));
    final ui.Image img =
        await recorder.endRecording().toImage(size.round(), size.round());
    final ByteData? bytes =
        await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null && _controller != null) {
      await _controller!.addImage(name, bytes.buffer.asUint8List());
    }
  }

  /// Pre-rendered bob-cycle frames + the timer that flips them. The GL map
  /// can't run a CustomPainter per frame, so we do what cartoons do: bake
  /// the animation into frames and cycle the symbol image (~9 fps, tiny
  /// texture uploads — the head bob lives on).
  List<Uint8List> _avatarFrames = <Uint8List>[];
  int _avatarFrameIndex = 0;
  Timer? _avatarTimer;

  /// Paints the CURRENT avatar (Tux / egg / archetype, same rules as
  /// UserLocationMarker) offscreen as a full bob cycle and starts the flip
  /// timer. Re-run whenever the profile or equipped cosmetic changes.
  Future<void> _refreshAvatarImage() async {
    if (_controller == null) return;

    final ArchetypeProfile? profile =
        ref.read(archetypeNotifierProvider).valueOrNull;

    // Painter factory — phase 0..1 drives the bob (or the egg's rock).
    const double h = 240; // 3x the 80-logical-px avatar → crisp at iconSize .5
    const double w = h * 0.8;
    CustomPainter painterFor(double phase) {
      if (creatorMode && (profile?.selectedArchetype == null)) {
        return AvatarPainter(
            archetype: DrivingArchetype.zenMaster, tux: true, bob: phase);
      }
      // Egg ONLY when the user hasn't explicitly picked an avatar — an
      // explicit pick must always win (the egg was hiding selections).
      if (profile != null &&
          profile.selectedArchetype == null &&
          profile.rareArchetype == null &&
          profile.sessionCount < archetypeRevealSessionCount) {
        return MysteryEggPainter(rock: phase);
      }
      final List<UnlockedCosmetic> cosmetics =
          ref.read(cosmeticsProvider).valueOrNull ?? <UnlockedCosmetic>[];
      final UnlockedCosmetic? equipped = cosmetics
          .where((UnlockedCosmetic c) => c.isEquipped)
          .toList()
          .firstOrNull;
      return AvatarPainter(
        archetype: profile?.displayArchetype ?? DrivingArchetype.zenMaster,
        rareArchetype: profile?.rareArchetype,
        equippedCosmetic: equipped?.cosmeticId,
        bob: phase,
      );
    }

    // Bake the cycle.
    const int frameCount = 10;
    final List<Uint8List> frames = <Uint8List>[];
    for (int i = 0; i < frameCount; i++) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painterFor(i / frameCount).paint(Canvas(recorder), const Size(w, h));
      final ui.Image img =
          await recorder.endRecording().toImage(w.round(), h.round());
      final ByteData? bytes =
          await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) frames.add(bytes.buffer.asUint8List());
    }
    if (frames.isEmpty || _controller == null) return;
    _avatarFrames = frames;
    await _controller!.addImage(_avatarImage, frames.first);

    // Flip frames — re-registering under the same name updates the symbol.
    // 110 ms × 10 frames = the original 1.1 s bob cycle.
    _avatarTimer?.cancel();
    _avatarTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted || _controller == null || _avatarFrames.isEmpty) return;
      _avatarFrameIndex = (_avatarFrameIndex + 1) % _avatarFrames.length;
      unawaited(
          _controller!.addImage(_avatarImage, _avatarFrames[_avatarFrameIndex]));
    });
  }

  @override
  void dispose() {
    _avatarTimer?.cancel();
    super.dispose();
  }

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

    // Destination flag (matches the old map's coral flag pin).
    await _addPinImage('mg-dest', migoCoral, Icons.flag_rounded, size: 96);
    await c.addSymbolLayer(
      _destSource,
      'migo-dest-pin',
      const SymbolLayerProperties(
        iconImage: 'mg-dest',
        iconSize: 1.0,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );

    // --- Overlay marker layers (Phase 4) ---
    // Pin images: ALPR camera, every hazard type, gas, every POI category.
    await _addPinImage('mg-alpr', migoPlum, Icons.no_photography_rounded,
        size: 66);
    for (final HazardType t in HazardType.values) {
      await _addPinImage(
          'mg-hz-${t.name}', HazardIcon.colorFor(t), HazardIcon.iconFor(t),
          size: 84);
    }
    await _addPinImage('mg-gas', migoAmber, Icons.local_gas_station_rounded,
        size: 84);
    for (final PoiCategory cat in PoiCategory.values) {
      await _addPinImage('mg-poi-${cat.name}', cat.color, cat.icon, size: 66);
    }

    // Sources + symbol layers. iconImage reads the per-feature 'icon'
    // property, so one layer serves all hazard types / POI categories.
    for (final String src in <String>[
      _alprSource,
      _hazardSource,
      _gasSource,
      _poiSource,
    ]) {
      await c.addSource(
          src, const GeojsonSourceProperties(data: _emptyCollection));
    }
    await c.addSymbolLayer(
      _alprSource,
      'migo-alpr-pins',
      const SymbolLayerProperties(
          iconImage: 'mg-alpr', iconSize: 1.0, iconAllowOverlap: true),
    );
    await c.addSymbolLayer(
      _hazardSource,
      'migo-hazard-pins',
      const SymbolLayerProperties(
          iconImage: <Object>['get', 'icon'],
          iconSize: 1.0,
          iconAllowOverlap: true),
    );
    await c.addSymbolLayer(
      _gasSource,
      'migo-gas-pins',
      const SymbolLayerProperties(
          iconImage: 'mg-gas', iconSize: 1.0, iconAllowOverlap: true),
    );
    await c.addSymbolLayer(
      _poiSource,
      'migo-poi-pins',
      const SymbolLayerProperties(
        iconImage: <Object>['get', 'icon'],
        iconSize: 1.0,
        textField: <Object>['get', 'name'],
        textSize: 11.0,
        textOffset: <Object>[0, 1.7],
        textColor: '#FFFFFF',
        textHaloColor: '#101722',
        textHaloWidth: 1.4,
        textOptional: true,
      ),
    );

    // THE AVATAR — the chibi painters render offscreen to a PNG which rides
    // the map as a GL symbol. Tux, egg, archetypes: full parity with the
    // flutter_map marker (minus the bob animation — symbols are static).
    await _refreshAvatarImage();
    await c.addSymbolLayer(
      _meSource,
      'migo-me-avatar',
      const SymbolLayerProperties(
        iconImage: _avatarImage,
        // Rendered at 240px (3x). 1.0 was still small on the road test —
        // +25% per Ruben.
        iconSize: 1.25,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconRotationAlignment: 'viewport', // stays upright under rotation
      ),
    );

    _styleReady = true;
    // Draw whatever state already exists (style loads after first data often).
    _syncRoute(ref.read(activeRouteProvider).valueOrNull);
    unawaited(_syncOverlays());
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

  Map<String, dynamic> _collection(List<Map<String, dynamic>> features) =>
      <String, dynamic>{'type': 'FeatureCollection', 'features': features};

  Map<String, dynamic> _feature(double lat, double lon,
          [Map<String, dynamic> props = const <String, dynamic>{}]) =>
      <String, dynamic>{
        'type': 'Feature',
        'properties': props,
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[lon, lat],
        },
      };

  /// Pushes ALPR / hazard / gas / POI data into their sources, honoring the
  /// layer toggles (off → empty collection) and the POI zoom gate.
  Future<void> _syncOverlays() async {
    if (!_styleReady || _controller == null) return;
    final MapLibreMapController c = _controller!;

    // ALPR cameras.
    final List<ll.LatLng> cams = ref.read(alprLayerEnabledProvider)
        ? (ref.read(nearbyAlprProvider).valueOrNull ?? <ll.LatLng>[])
        : <ll.LatLng>[];
    await c.setGeoJsonSource(
      _alprSource,
      _collection(<Map<String, dynamic>>[
        for (final ll.LatLng p in cams) _feature(p.latitude, p.longitude),
      ]),
    );

    // Hazards — per-type icon via the 'icon' property.
    final List<Hazard> hazards = ref.read(hazardLayerEnabledProvider)
        ? (ref.read(nearbyHazardsProvider).valueOrNull ?? <Hazard>[])
        : <Hazard>[];
    await c.setGeoJsonSource(
      _hazardSource,
      _collection(<Map<String, dynamic>>[
        for (final Hazard h in hazards)
          _feature(h.position.latitude, h.position.longitude,
              <String, dynamic>{
                'icon': 'mg-hz-${h.type.name}',
                'label': HazardIcon.labelFor(h.type),
              }),
      ]),
    );

    // Gas stations — id carried so taps can find the station object.
    final List<GasStation> stations = ref.read(gasLayerEnabledProvider)
        ? (ref.read(nearbyGasStationsProvider).valueOrNull ?? <GasStation>[])
        : <GasStation>[];
    await c.setGeoJsonSource(
      _gasSource,
      _collection(<Map<String, dynamic>>[
        for (final GasStation s in stations)
          _feature(s.latitude, s.longitude, <String, dynamic>{'id': s.id}),
      ]),
    );

    // POIs — hidden below _poiMinZoom so the map doesn't flood at city zoom.
    final double zoom = ref.read(currentZoomProvider);
    final Set<PoiCategory> active = ref.read(activePoisProvider);
    final List<PointOfInterest> pois =
        (zoom >= _poiMinZoom && active.isNotEmpty)
            ? (ref.read(nearbyPoisProvider).valueOrNull ??
                <PointOfInterest>[])
            : <PointOfInterest>[];
    await c.setGeoJsonSource(
      _poiSource,
      _collection(<Map<String, dynamic>>[
        for (final PointOfInterest p in pois)
          _feature(p.latitude, p.longitude, <String, dynamic>{
            'icon': 'mg-poi-${p.category.name}',
            'name': p.displayName,
          }),
      ]),
    );
  }

  /// Tap handling: query our pin layers at the tap point and act like the
  /// old map's markers did.
  Future<void> _onMapClick(Point<double> point, LatLng latLng) async {
    if (_controller == null || !mounted) return;
    final List<dynamic> hits = await _controller!.queryRenderedFeatures(
      point,
      <String>[
        'migo-gas-pins',
        'migo-hazard-pins',
        'migo-alpr-pins',
        'migo-poi-pins',
      ],
      null,
    );
    if (hits.isEmpty || !mounted) return;
    final Map<String, dynamic> feature =
        (hits.first as Map<Object?, Object?>).cast<String, dynamic>();
    final Map<String, dynamic> props =
        ((feature['properties'] ?? <Object?, Object?>{})
                as Map<Object?, Object?>)
            .cast<String, dynamic>();

    if (props.containsKey('id')) {
      // Gas station → same report/price sheet as the old map.
      final List<GasStation> stations =
          ref.read(nearbyGasStationsProvider).valueOrNull ?? <GasStation>[];
      GasStation? station;
      for (final GasStation s in stations) {
        if (s.id == props['id']) {
          station = s;
          break;
        }
      }
      if (station != null && mounted) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ReportGasPriceSheet(station: station!),
        );
      }
    } else if (props.containsKey('label')) {
      // Hazard → identify it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Hazard: ${props['label']}'),
          duration: const Duration(seconds: 2)));
    } else if (props.containsKey('name')) {
      // POI → name card.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(props['name'] as String),
          duration: const Duration(seconds: 2)));
    } else {
      // ALPR camera.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ALPR camera reported at this location'),
          duration: Duration(seconds: 2)));
    }
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  /// One camera update per GPS fix (~1 Hz). The NATIVE side interpolates the
  /// movement over the animation duration — that's what makes MapLibre feel
  /// silky without any per-frame Dart work.
  Future<void> _onFix(Position p) async {
    _lastFix = p;
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

    // CHASE FIX ("avatar drives off the screen"): the puck GeoJSON updates
    // instantly each fix, but the camera ANIMATES there — at speed the car
    // outruns the still-animating camera and exits the top of the screen.
    // Two counters: (1) target a point AHEAD of the car (speed × ~2s +
    // margin), which both keeps the avatar in the lower third and gives the
    // camera lag headroom; (2) animate in ~one fix interval so the camera
    // never falls a full cycle behind.
    LatLng camTarget = LatLng(p.latitude, p.longitude);
    if (navigating && heading != null && p.speed.isFinite && p.speed > 1) {
      final double aheadMeters = (p.speed * 2.0) + 50.0;
      final ll.LatLng ahead =
          const ll.Distance().offset(here, aheadMeters, heading);
      camTarget = LatLng(ahead.latitude, ahead.longitude);
    }

    final CameraPosition target = CameraPosition(
      target: camTarget,
      zoom: navigating ? mapNavigationZoom : (_controller!
              .cameraPosition?.zoom ??
          mapFirstFixZoom),
      bearing: bearing,
      tilt: tilt,
    );
    unawaited(_controller!.animateCamera(
      CameraUpdate.newCameraPosition(target),
      duration: const Duration(milliseconds: 600),
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
    // Avatar changes (hatch, picker choice, cosmetic equip) → repaint symbol.
    ref.listen<AsyncValue<ArchetypeProfile>>(archetypeNotifierProvider,
        (AsyncValue<ArchetypeProfile>? prev,
            AsyncValue<ArchetypeProfile> next) {
      if (_styleReady) _refreshAvatarImage();
    });

    // Overlay data / toggles / zoom-gate changes → resync pins. Watching
    // rebuilds this widget cheaply (the MapLibreMap child is unchanged);
    // the post-frame sync pushes fresh GeoJSON.
    ref.watch(alprLayerEnabledProvider);
    ref.watch(nearbyAlprProvider);
    ref.watch(hazardLayerEnabledProvider);
    ref.watch(nearbyHazardsProvider);
    ref.watch(gasLayerEnabledProvider);
    ref.watch(nearbyGasStationsProvider);
    ref.watch(activePoisProvider);
    ref.watch(nearbyPoisProvider);
    ref.watch(currentZoomProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlays());

    // Recenter button (map_screen overlay) → resume following + snap back.
    ref.listen<int>(glRecenterSignalProvider, (int? prev, int next) {
      ref.read(glFollowingProvider.notifier).state = true;
      final Position? p = _lastFix ?? ref.read(positionStreamProvider).valueOrNull;
      if (p != null) _onFix(p);
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

    // DRAGGING the map pauses following (recenter button resumes it).
    // Deliberately onPointerMove, not onPointerDown: incidental TAPS — a
    // finger graze in the car mount, tapping a gas pin — must not silently
    // stop the camera (that read as "the avatar drove off the screen").
    return Listener(
      onPointerMove: (_) =>
          ref.read(glFollowingProvider.notifier).state = false,
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
        onMapClick: _onMapClick,
        onMapLongClick: (Point<double> pt, LatLng p) =>
            widget.onLongPress?.call(ll.LatLng(p.latitude, p.longitude)),
        // Keep currentZoomProvider honest so zoom-dependent logic (POI gate,
        // settings previews) works on the GL path too.
        onCameraIdle: () {
          final double? z = _controller?.cameraPosition?.zoom;
          if (z != null) {
            ref.read(currentZoomProvider.notifier).state = z;
          }
        },
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
