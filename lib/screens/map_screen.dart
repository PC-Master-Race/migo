// map_screen.dart — The main navigation screen: live map, follow-user
// camera, three zoom modes (cartoon -> hybrid -> street/satellite), the
// user's position marker, the speed HUD, and required tile attribution.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../providers/location_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/map_service.dart';
import '../theme/migo_theme.dart';
import '../widgets/cartoon_avatar/user_location_marker.dart';
import '../widgets/hud/speed_hud.dart';
import '../widgets/map_controls/recenter_button.dart';

// --- LOCAL CONSTANTS ---

/// Opacity of the warm amber tint applied in cartoon mode. Low enough to keep
/// map labels readable while nudging the OSM palette toward warm coral/amber.
const double cartoonTintOpacity = 0.18;

/// Weaker tint for hybrid mode — warmth without obscuring road details.
const double hybridTintOpacity = 0.08;

// --- SCREEN ---

/// Main map screen. Follows the user's GPS position until they pan manually,
/// then shows a recenter button to resume following.
class MapScreen extends ConsumerStatefulWidget {
  /// Creates the map screen.
  const MapScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/map';

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Controls programmatic camera moves (follow-user, recenter).
  final MapController _mapController = MapController();

  /// True while the camera follows GPS. A user pan pauses following; the
  /// recenter button resumes it.
  bool _isFollowingUser = true;

  /// True once the home-region tile prefetch has been kicked off this run.
  bool _prefetchStarted = false;

  // --- EVENT HANDLING ---

  /// Syncs zoom changes into the provider and pauses follow mode on any
  /// user-initiated gesture (drag or pinch).
  void _handleMapEvent(MapEvent event) {
    ref.read(currentZoomProvider.notifier).state = event.camera.zoom;
    final bool isUserGesture =
        event.source == MapEventSource.onDrag ||
        event.source == MapEventSource.multiFingerGestureStart;
    if (isUserGesture && _isFollowingUser) {
      setState(() => _isFollowingUser = false);
    }
  }

  /// Moves the camera to [position] when follow mode is active.
  void _followPositionIfEnabled(Position position) {
    if (!_isFollowingUser) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _mapController.camera.zoom,
    );
  }

  /// Re-enables follow mode and snaps the camera back to the user.
  void _recenterOnUser() {
    setState(() => _isFollowingUser = true);
    final Position? latest = ref.read(positionStreamProvider).valueOrNull;
    if (latest != null) _followPositionIfEnabled(latest);
  }

  /// Triggers the home-region prefetch once after the first GPS fix.
  /// The prefetcher enforces WiFi-only and weekly-cadence rules internally.
  void _startPrefetchOnce(Position position) {
    if (_prefetchStarted) return;
    _prefetchStarted = true;
    TilePrefetcher.prefetchHomeRegion(
      LatLng(position.latitude, position.longitude),
      wifiOnlyAllowed: ref.read(wifiOnlyTileSyncProvider),
    );
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final MapZoomMode zoomMode = ref.watch(zoomModeProvider);
    final Position? position = ref.watch(positionStreamProvider).valueOrNull;

    if (position != null) {
      _startPrefetchOnce(position);
      // Schedule camera move after frame to avoid setState-during-build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _followPositionIfEnabled(position),
      );
    }

    return Scaffold(
      body: Stack(
        children: <Widget>[
          _buildMap(zoomMode, position),
          _buildAttributionBadge(zoomMode),
          const Positioned(top: 48, left: 16, child: SpeedHud()),
          if (!_isFollowingUser)
            Positioned(
              bottom: 32,
              right: 16,
              child: RecenterButton(onPressed: _recenterOnUser),
            ),
          // TODO: [hazard markers layer] [deferred to Phase 3]
          // TODO: [family/anonymous avatar layer] [deferred to Phases 4-5]
        ],
      ),
    );
  }

  // --- MAP LAYERS ---

  /// Builds the FlutterMap with the correct tile source, cartoon tint
  /// overlay, and the user's position marker (once GPS has a fix).
  Widget _buildMap(MapZoomMode zoomMode, Position? position) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            const LatLng(fallbackCenterLatitude, fallbackCenterLongitude),
        initialZoom: mapDefaultZoom,
        minZoom: mapMinZoom,
        maxZoom: mapMaxZoom,
        onMapEvent: _handleMapEvent,
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: MapService.tileUrlTemplateForMode(zoomMode),
          userAgentPackageName: osmUserAgent,
          // OSM modes: offline-first provider. Satellite: network-only.
          tileProvider: zoomMode == MapZoomMode.street
              ? NetworkTileProvider()
              : OfflineFirstTileProvider(),
        ),
        _buildCartoonTintOverlay(zoomMode),
        if (position != null) _buildUserMarkerLayer(position),
      ],
    );
  }

  /// Paints the marker layer with the user's current position dot.
  Widget _buildUserMarkerLayer(Position position) {
    return MarkerLayer(
      markers: <Marker>[
        Marker(
          point: LatLng(position.latitude, position.longitude),
          width: userMarkerSize,
          height: userMarkerSize,
          child: const UserLocationMarker(),
        ),
      ],
    );
  }

  /// Overlays a warm amber tint in cartoon/hybrid modes. Street mode gets
  /// no tint so satellite imagery stays true to life.
  Widget _buildCartoonTintOverlay(MapZoomMode zoomMode) {
    final double opacity = switch (zoomMode) {
      MapZoomMode.cartoon => cartoonTintOpacity,
      MapZoomMode.hybrid => hybridTintOpacity,
      MapZoomMode.street => 0.0,
    };
    return IgnorePointer(
      child: Container(color: migoAmber.withValues(alpha: opacity)),
    );
  }

  // --- ATTRIBUTION ---

  /// Renders the attribution badge required by OSM and Esri usage policies.
  Widget _buildAttributionBadge(MapZoomMode zoomMode) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: migoCream.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            MapService.attributionForMode(zoomMode),
            style: const TextStyle(fontSize: 11, color: migoInk),
          ),
        ),
      ),
    );
  }
}
