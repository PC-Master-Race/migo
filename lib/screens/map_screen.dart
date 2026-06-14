// map_screen.dart — The main navigation screen.
// Phase 1: live map, follow-user camera, three zoom modes, speed HUD.
// Phase 2: destination search bar, route polyline, maneuver banner,
//          off-route recalculation, route options bottom sheet.
// Phase 8 fixes:
//   - prefAutoRecalcProvider infinite-loop removed (flat↔angled flicker fixed)
//   - search bar + results merged into one Positioned (overlap bug fixed)
//   - route info bar at bottom (distance, ETA, Steps, Exit)
//   - full directions sheet (_DirectionsSheet)
//   - POI layer zoom gate — hidden below zoom 14.5


import 'dart:math' as math;

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';
import '../models/saved_location_model.dart';
import '../providers/location_provider.dart';
import '../providers/driving_session_provider.dart';
import '../providers/saved_location_provider.dart';
import '../providers/map_provider.dart';
import '../providers/routing_provider.dart';
import '../providers/settings_provider.dart';
import '../services/map_service.dart';
import '../theme/bravo_theme.dart';
import '../widgets/cartoon_avatar/user_location_marker.dart';
import '../widgets/hud/speed_hud.dart';
import '../widgets/map_controls/recenter_button.dart';
import 'route_options_screen.dart';
import '../models/hazard_model.dart';
import '../providers/hazard_provider.dart';
import '../models/family_model.dart';
import '../providers/family_provider.dart';
import '../widgets/avatar/family_member_marker.dart';
import '../models/poi_model.dart';
import '../models/gas_model.dart';
import '../providers/gas_poi_provider.dart';
import '../widgets/map_controls/gas_station_marker.dart';
import 'report_gas_price_screen.dart';
import '../widgets/hazard_icons/hazard_icon.dart';
import '../widgets/hud/hazard_alert_banner.dart';
import 'report_hazard_screen.dart';
import 'settings_screen.dart';
// BravosHudChip is in user_location_marker.dart (already imported above)

// --- LOCAL CONSTANTS ---

/// Opacity of the warm amber tint applied in cartoon mode.
const double cartoonTintOpacity = 0.18;

/// Weaker tint for hybrid mode.
const double hybridTintOpacity = 0.08;

/// Approximate height of the search pill widget (dp). Used for layout math
/// so the maneuver banner and hazard alerts position correctly below it.
const double _searchBarHeight = 52.0;

/// Minimum zoom level at which POI markers render on the map.
/// Below this they crowd each other and slow rendering unnecessarily.
const double _poiMinZoom = 14.5;

// --- SCREEN ---

/// Main map screen. Follows GPS until the user pans, then shows a recenter
/// button. Hosts the destination search bar and route overlay (Phase 2).
class MapScreen extends ConsumerStatefulWidget {
  /// Creates the map screen.
  const MapScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/map';

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Speech-to-text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  bool _isFollowingUser = true;
  bool _prefetchStarted = false;
  bool _showSearchResults = false;
  bool _hasHadFirstFix = false;

  /// Prevents queueing multiple off-route recalculations per render cycle.
  /// Resets after 10 s so future off-route events can still trigger one.
  bool _recalcQueued = false;

  /// Tracks active-navigation state so we can zoom in/out on transition.
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    // Rebuild whenever the search bar gains/loses focus so the saved-location
    // chips appear immediately when the user taps the bar (before typing).
    _searchFocus.addListener(() => setState(() {}));
    // Initialise STT — check availability once; no permission prompt yet.
    _speech.initialize().then((bool available) {
      if (mounted) setState(() => _speechAvailable = available);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // --- MAP EVENTS ---

  void _handleMapEvent(MapEvent event) {
    ref.read(currentZoomProvider.notifier).state = event.camera.zoom;
    final bool isUserGesture =
        event.source == MapEventSource.onDrag ||
        event.source == MapEventSource.multiFingerGestureStart;
    if (isUserGesture && _isFollowingUser) {
      setState(() => _isFollowingUser = false);
    }
  }

  void _followPositionIfEnabled(Position position) {
    if (!_isFollowingUser) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _mapController.camera.zoom,
    );
  }

  void _recenterOnUser() {
    setState(() => _isFollowingUser = true);
    final Position? latest = ref.read(positionStreamProvider).valueOrNull;
    if (latest != null) _followPositionIfEnabled(latest);
  }

  void _startPrefetchOnce(Position position) {
    if (_prefetchStarted) return;
    _prefetchStarted = true;
    TilePrefetcher.prefetchHomeRegion(
      LatLng(position.latitude, position.longitude),
      wifiOnlyAllowed: ref.read(wifiOnlyTileSyncProvider),
    );
  }

  /// On the first GPS fix, snap the camera to [mapFirstFixZoom] so the
  /// user sees a Waze-like close-up street view rather than a wide overview.
  void _handleFirstFix(Position position) {
    if (_hasHadFirstFix) return;
    _hasHadFirstFix = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        mapFirstFixZoom,
      );
    });
  }

  // --- ZOOM SCALING ---

  /// Returns the marker size (dp) for [zoom].
  /// Base 60 dp at zoom 15 — roughly Waze icon size at street level.
  /// Scales gently: 1.4× per zoom level, clamped 30–100 dp.
  double _markerSizeForZoom(double zoom) {
    const double base = 60.0;
    const double refZoom = 15.0;
    final double scale = math.pow(1.4, zoom - refZoom).toDouble();
    return (base * scale).clamp(30.0, 100.0);
  }

  // --- SAVED LOCATIONS ---

  /// Navigate to a saved place exactly like selecting a search result.
  void _selectSavedLocation(SavedLocation loc) {
    _searchFocus.unfocus();
    _searchController.text = loc.label;
    setState(() => _showSearchResults = false);
    ref.read(destinationProvider.notifier).state = loc.position;
    final Position? pos = ref.read(positionStreamProvider).valueOrNull;
    if (pos != null) {
      ref.read(activeRouteProvider.notifier).calculate(
            destination: loc.position,
          );
    }
    _mapController.move(loc.position, 14.0);
    setState(() => _isFollowingUser = false);
  }

  /// Shows a bottom sheet where the user can save [result] as Home/Work/Favorite.
  void _showSaveLocationSheet(BuildContext context, GeocodingResult result) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SaveLocationSheet(result: result),
    );
  }

  // --- SPEECH TO TEXT ---

  Future<void> _startListening() async {
    if (!_speechAvailable || _isListening) return;
    _searchController.clear();
    ref.read(geocodeQueryProvider.notifier).state = '';
    setState(() {
      _isListening = true;
      _showSearchResults = false;
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        final String words = result.recognizedWords;
        _searchController.text = words;
        ref.read(geocodeQueryProvider.notifier).state = words;
        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _showSearchResults = words.isNotEmpty;
          });
        } else {
          // Show partial result in field while listening.
          setState(() {});
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  // --- SEARCH ---

  void _onSearchChanged(String query) {
    ref.read(geocodeQueryProvider.notifier).state = query;
    setState(() => _showSearchResults = query.isNotEmpty);
  }

  void _onSearchSubmitted(String query) {
    ref.read(geocodeQueryProvider.notifier).state = query;
    setState(() => _showSearchResults = query.isNotEmpty);
  }

  void _selectDestination(GeocodingResult result) {
    _searchFocus.unfocus();
    _searchController.text = result.shortName;
    setState(() => _showSearchResults = false);

    ref.read(destinationProvider.notifier).state = result.position;

    final Position? pos = ref.read(positionStreamProvider).valueOrNull;
    if (pos != null) {
      ref.read(activeRouteProvider.notifier).calculate(
            destination: result.position,
          );
    }

    _mapController.move(result.position, 14.0);
    setState(() => _isFollowingUser = false);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(geocodeQueryProvider.notifier).state = '';
    ref.read(destinationProvider.notifier).state = null;
    ref.read(activeRouteProvider.notifier).clear();
    setState(() {
      _showSearchResults = false;
      _isFollowingUser = true;
      _recalcQueued = false;
    });
  }

  // --- DIRECTIONS ---

  void _showDirectionsSheet(
      BuildContext context, BravoRoute route, NavigationState? navState) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectionsSheet(
        route: route,
        currentStepIndex: navState?.currentStepIndex ?? 0,
      ),
    );
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final MapZoomMode zoomMode = ref.watch(zoomModeProvider);
    final MapZoomMode defaultMode = ref.watch(defaultZoomModeProvider);
    final Position? position = ref.watch(positionStreamProvider).valueOrNull;
    final BravoRoute? route = ref.watch(activeRouteProvider).valueOrNull;
    final NavigationState? navState = ref.watch(navigationStateProvider);

    // Keep side-effect providers alive.
    ref.watch(prefAutoRecalcProvider);
    ref.watch(ttsAnnouncerProvider);
    ref.watch(hazardAlertWatcherProvider);
    // Drives the archetype loop: feeds GPS to the session tracker + POI checks.
    ref.watch(drivingSessionEngineProvider);

    if (position != null) {
      _startPrefetchOnce(position);
      _handleFirstFix(position);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _followPositionIfEnabled(position),
      );
    }

    // Off-route: trigger one recalculation then wait 10 s before allowing
    // another. _recalcQueued prevents multiple calls per render cycle.
    final bool isOffRoute = ref.watch(offRouteProvider);
    if (isOffRoute && route != null && !_recalcQueued) {
      _recalcQueued = true;
      // Count the reroute toward this trip's archetype metrics (Chaos/Scout).
      ref.read(drivingSessionTrackerProvider).noteReroute();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(activeRouteProvider.notifier).recalculate();
        await Future<void>.delayed(const Duration(seconds: 10));
        if (mounted) setState(() => _recalcQueued = false);
      });
    }

    // Auto-zoom when navigation starts/ends so the street level is always
    // readable without a perspective tilt. 18 = individual buildings visible.
    final bool nowNavigating = navState != null;
    if (nowNavigating && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(_mapController.camera.center, 18.0);
        }
      });
    } else if (!nowNavigating && _isNavigating) {
      _isNavigating = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(_mapController.camera.center, mapFirstFixZoom);
        }
      });
    }

    // Layout helpers — all vertical positions derive from status bar height
    // so the UI lands in the right place on every screen size.
    final double statusBarH = MediaQuery.of(context).padding.top;
    final double searchBottom = statusBarH + 8 + _searchBarHeight;
    // Route info bar is ~84 dp; elements at the bottom shift up by this much
    // when a route is active so they don't hide behind the bar.
    final double routeBarH = route != null ? 84.0 : 0.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // Base map — flat, full-screen (the perspective-tilt experiment was
          // removed because it shrank the map to ~1/3 of the screen).
          _buildMap(zoomMode, defaultMode, position, route),

          // Attribution badge (bottom-right corner).
          _buildAttributionBadge(zoomMode),

          // Search bar + inline results dropdown (single Positioned widget so
          // results can never overlap the search pill).
          _buildSearchBar(context, statusBarH),

          // Maneuver banner — below the search bar when navigating.
          if (navState != null)
            Positioned(
              top: searchBottom + 8,
              left: 12,
              right: 12,
              child: _ManeuverBanner(navState: navState),
            ),

          // Off-route recalculating indicator.
          if (isOffRoute && route != null)
            Positioned(
              top: navState != null ? searchBottom + 90 : searchBottom + 8,
              left: 0,
              right: 0,
              child: const _OffRouteBadge(),
            ),

          // Route info bar at the very bottom (distance, ETA, Steps, Exit).
          if (route != null)
            _buildRouteInfoBar(context, route, navState),

          // Speed HUD — raised when the route info bar is visible.
          Positioned(
            bottom: routeBarH + 32,
            left: 16,
            child: const SpeedHud(),
          ),

          // Report hazard FAB.
          Positioned(
            bottom: routeBarH + 100,
            left: 16,
            child: _ReportHazardButton(context: context),
          ),

          // Bravos balance chip.
          Positioned(
            bottom: routeBarH + 88,
            right: 16,
            child: const BravosHudChip(),
          ),

          // Recenter button (only when not following user).
          if (!_isFollowingUser)
            Positioned(
              bottom: routeBarH + 32,
              right: 16,
              child: RecenterButton(onPressed: _recenterOnUser),
            ),

          // Settings gear — below the search bar, not overlapping it.
          Positioned(
            top: statusBarH + 68,
            right: 16,
            child: _SettingsButton(context: context),
          ),

          // Layer toggle panel — stacked below the settings gear.
          Positioned(
            top: statusBarH + 112,
            right: 16,
            child: _buildLayerToggles(context),
          ),

          // Hazard alert banners — below maneuver banner when navigating.
          Positioned(
            top: navState != null ? searchBottom + 96 : searchBottom + 8,
            left: 0,
            right: 0,
            child: const HazardAlertStack(),
          ),
        ],
      ),
    );
  }

  // --- MAP LAYERS ---
  // Navigation uses a flat, full-screen map (auto-zoomed to 18 when a route
  // starts). An earlier perspective-tilt experiment was removed — the
  // Transform shrank the visible map to ~1/3 of the screen.

  Widget _buildMap(
    MapZoomMode zoomMode,
    MapZoomMode defaultMode,
    Position? position,
    BravoRoute? route,
  ) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            const LatLng(fallbackCenterLatitude, fallbackCenterLongitude),
        initialZoom: MapService.startingZoomForMode(defaultMode),
        minZoom: mapMinZoom,
        maxZoom: mapMaxZoom,
        onMapEvent: _handleMapEvent,
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: MapService.tileUrlTemplateForMode(zoomMode),
          userAgentPackageName: osmUserAgent,
          tileProvider: zoomMode == MapZoomMode.street
              ? NetworkTileProvider()
              : OfflineFirstTileProvider(),
        ),
        // In satellite/street mode stack two transparent Esri reference layers
        // on top of the imagery: one for place names, one for road/street names.
        if (zoomMode == MapZoomMode.street) ...<Widget>[
          TileLayer(
            urlTemplate: satelliteRoadsTileUrlTemplate,
            userAgentPackageName: osmUserAgent,
            tileProvider: NetworkTileProvider(),
          ),
          TileLayer(
            urlTemplate: satelliteLabelsTileUrlTemplate,
            userAgentPackageName: osmUserAgent,
            tileProvider: NetworkTileProvider(),
          ),
        ],
        _buildCartoonTintOverlay(zoomMode),

        // Route polyline (below user marker so the dot stays on top).
        if (route != null && route.waypoints.isNotEmpty)
          PolylineLayer(
            polylines: <Polyline>[
              Polyline(
                points: route.waypoints,
                strokeWidth: routePolylineWidthDp,
                color: migoTeal,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),

        // Destination marker.
        if (route != null)
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: route.destination,
                width: 32,
                height: 32,
                child: const _DestinationMarker(),
              ),
            ],
          ),

        _buildHazardLayer(ref),
        _buildFamilyLayer(ref),
        _buildGasLayer(ref),
        _buildPoiLayer(ref),

        if (position != null) _buildUserMarkerLayer(position),
      ],
    );
  }

  Widget _buildFamilyLayer(WidgetRef ref) {
    ref.watch(locationPublisherProvider);

    final List<FamilyLocation> locations =
        ref.watch(familyLocationsProvider).valueOrNull ?? <FamilyLocation>[];
    final Map<String, FamilyMember> memberMap =
        ref.watch(familyMemberMapProvider);

    if (locations.isEmpty) return const SizedBox.shrink();

    final double zoom = ref.watch(currentZoomProvider);
    final double sz = _markerSizeForZoom(zoom);

    return MarkerLayer(
      markers: locations.map((FamilyLocation loc) {
        final FamilyMember? member = memberMap[loc.userId];
        if (member == null) return null;
        return Marker(
          point: LatLng(loc.latitude, loc.longitude),
          width: sz,
          height: sz,
          child: FamilyMemberMarker(member: member, location: loc),
        );
      }).whereType<Marker>().toList(),
    );
  }

  Widget _buildGasLayer(WidgetRef ref) {
    final bool enabled = ref.watch(gasLayerEnabledProvider);
    if (!enabled) return const SizedBox.shrink();

    final List<GasStation> stations =
        ref.watch(nearbyGasStationsProvider).valueOrNull ?? <GasStation>[];
    if (stations.isEmpty) return const SizedBox.shrink();

    final GasStation? selected = ref.watch(selectedGasStationProvider);

    return MarkerLayer(
      markers: stations.map((GasStation station) {
        final bool isSelected = selected?.id == station.id;
        return Marker(
          point: LatLng(station.latitude, station.longitude),
          width: isSelected ? 88 : 72,
          height: isSelected ? 48 : 40,
          child: GasStationMarker(
            station: station,
            isSelected: isSelected,
            onTap: () {
              ref.read(selectedGasStationProvider.notifier).state =
                  isSelected ? null : station;
              if (!isSelected) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ReportGasPriceSheet(station: station),
                );
              }
            },
          ),
        );
      }).toList(),
    );
  }

  /// POI layer — hidden below [_poiMinZoom] so parking/restaurants don't
  /// flood the screen at city or region zoom levels.
  Widget _buildPoiLayer(WidgetRef ref) {
    final double zoom = ref.watch(currentZoomProvider);
    if (zoom < _poiMinZoom) return const SizedBox.shrink();

    final Set<PoiCategory> active = ref.watch(activePoisProvider);
    if (active.isEmpty) return const SizedBox.shrink();

    final List<PointOfInterest> pois =
        ref.watch(nearbyPoisProvider).valueOrNull ?? <PointOfInterest>[];
    if (pois.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: pois.map((PointOfInterest poi) {
        return Marker(
          point: LatLng(poi.latitude, poi.longitude),
          width: 44,
          height: 52,
          child: PoiMarker(
            icon: poi.category.icon,
            color: poi.category.color,
            label: poi.displayName,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text(
                  poi.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Icon(poi.category.icon,
                          color: poi.category.color, size: 16),
                      const SizedBox(width: 6),
                      Text(poi.category.label,
                          style: const TextStyle(color: Colors.white70)),
                    ]),
                    if (poi.address != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(poi.address!,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                    if (poi.openingHours != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text('Hours: ${poi.openingHours}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHazardLayer(WidgetRef ref) {
    if (!ref.watch(hazardLayerEnabledProvider)) return const SizedBox.shrink();
    final List<Hazard> hazards =
        ref.watch(nearbyHazardsProvider).valueOrNull ?? <Hazard>[];
    if (hazards.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: hazards.map((Hazard h) {
        return Marker(
          point: h.position,
          width: hazardIconSize,
          height: hazardIconSize,
          child: HazardIcon(type: h.type, isOwn: !h.isCommunityConfirmed),
        );
      }).toList(),
    );
  }

  Widget _buildUserMarkerLayer(Position position) {
    final double zoom = ref.watch(currentZoomProvider);
    final double sz = _markerSizeForZoom(zoom);
    return MarkerLayer(
      markers: <Marker>[
        Marker(
          point: LatLng(position.latitude, position.longitude),
          width: sz,
          height: sz,
          rotate: true,
          child: const UserLocationMarker(),
        ),
      ],
    );
  }

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

  // --- SEARCH BAR ---

  /// Search pill + inline results in a single Positioned so the dropdown
  /// always renders directly below the pill — never overlapping it.
  Widget _buildSearchBar(BuildContext context, double statusBarH) {
    return Positioned(
      top: statusBarH + 8,
      left: 12,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(28),
            color: Colors.white,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 16),
                const Icon(Icons.search_rounded, color: migoInk, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: const InputDecoration(
                      hintText: 'Where to?',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    style: const TextStyle(fontSize: 15, color: migoInk),
                    onChanged: _onSearchChanged,
                    onSubmitted: _onSearchSubmitted,
                    textInputAction: TextInputAction.search,
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: migoInk.withValues(alpha: 0.5),
                    onPressed: _clearSearch,
                  ),
                // Mic button — speech-to-text destination search.
                if (_speechAvailable)
                  GestureDetector(
                    onTap: _isListening ? _stopListening : _startListening,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _isListening
                              ? migoCoral
                              : migoInk.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          size: 18,
                          color: _isListening ? Colors.white : migoInk,
                        ),
                      ),
                    ),
                  ),
                // Route options tune icon — only when a route is active.
                if (ref.watch(activeRouteProvider).valueOrNull != null)
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    color: migoCoral,
                    tooltip: 'Route options',
                    onPressed: () => RouteOptionsScreen.showSheet(context),
                  ),
              ],
            ),
          ),
          // Saved-location chips — always shown when the bar is focused
          // and the user hasn't typed anything yet.
          if (_searchFocus.hasFocus &&
              _searchController.text.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _buildSavedLocationChips(),
          ],
          if (_showSearchResults) ...<Widget>[
            const SizedBox(height: 4),
            _buildSearchResultsList(),
          ],
        ],
      ),
    );
  }

  /// Saved-location chips (or a hint card if nothing is saved yet).
  Widget _buildSavedLocationChips() {
    final List<SavedLocation> saved = ref.watch(savedLocationsProvider);

    // Empty state — show a hint so new users know the feature exists.
    if (saved.isEmpty) {
      return Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.bookmark_add_rounded,
                  size: 18, color: migoCoral.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Search for a place, then tap the bookmark to save Home, Work, or Favorites here.',
                  style: TextStyle(fontSize: 12, color: migoInk),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Saved chips row.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: saved.map((SavedLocation loc) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(loc.type.icon, size: 16, color: loc.type.color),
              label: Text(
                loc.label,
                style: const TextStyle(fontSize: 13, color: migoInk),
              ),
              backgroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              onPressed: () => _selectSavedLocation(loc),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    final AsyncValue<List<GeocodingResult>> results =
        ref.watch(geocodeResultsProvider);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: results.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: migoCoral,
              ),
            ),
          ),
        ),
        error: (_, __) => const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Search unavailable — check connection'),
        ),
        data: (List<GeocodingResult> items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No results found'),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (BuildContext ctx, int i) {
              final GeocodingResult r = items[i];
              return ListTile(
                leading:
                    const Icon(Icons.place_rounded, color: migoCoral),
                title: Text(
                  r.shortName,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: migoInk),
                ),
                subtitle: Text(
                  r.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: migoInk.withValues(alpha: 0.5)),
                ),
                trailing: GestureDetector(
                  onTap: () => _showSaveLocationSheet(context, r),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.bookmark_add_rounded,
                            size: 18, color: migoCoral),
                        Text(
                          'Save',
                          style: TextStyle(
                              fontSize: 9,
                              color: migoCoral,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                onTap: () => _selectDestination(r),
              );
            },
          );
        },
      ),
    );
  }

  // --- LAYER TOGGLES ---

  /// Compact icon-button column for toggling map layers on/off.
  /// Gas stations, hazards (community + ALPR).
  Widget _buildLayerToggles(BuildContext context) {
    final bool gasOn = ref.watch(gasLayerEnabledProvider);
    final bool hazardsOn = ref.watch(hazardLayerEnabledProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LayerToggleButton(
          icon: Icons.local_gas_station_rounded,
          active: gasOn,
          tooltip: gasOn ? 'Hide gas stations' : 'Show gas stations',
          onTap: () => ref.read(gasLayerEnabledProvider.notifier).state = !gasOn,
        ),
        const SizedBox(height: 6),
        _LayerToggleButton(
          icon: Icons.warning_amber_rounded,
          active: hazardsOn,
          tooltip: hazardsOn ? 'Hide hazards' : 'Show hazards',
          onTap: () =>
              ref.read(hazardLayerEnabledProvider.notifier).state = !hazardsOn,
        ),
      ],
    );
  }

  // --- ROUTE INFO BAR ---

  /// Persistent bottom bar when a route is active.
  /// Shows remaining distance + ETA on the left; Steps and Exit buttons on the right.
  Widget _buildRouteInfoBar(
      BuildContext context, BravoRoute route, NavigationState? navState) {
    final double distM =
        navState?.distanceRemainingMeters ?? route.distanceMeters;
    final double secs =
        navState?.timeRemainingSeconds ?? route.estimatedSeconds;
    final int mins = (secs / 60).round();

    final String distLabel = distM < 1000
        ? '${distM.round()} m'
        : '${(distM / 1000).toStringAsFixed(1)} km';
    final String timeLabel = mins < 60
        ? '$mins min'
        : '${mins ~/ 60} h ${mins % 60} min';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 12,
        color: migoInk,
        child: SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Time + distance.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        distLabel,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Steps / directions button.
                _RouteActionButton(
                  icon: Icons.list_rounded,
                  label: 'Steps',
                  color: migoAmber,
                  onTap: () =>
                      _showDirectionsSheet(context, route, navState),
                ),
                const SizedBox(width: 4),
                // Cancel route.
                _RouteActionButton(
                  icon: Icons.close_rounded,
                  label: 'Exit',
                  color: migoCoral,
                  onTap: _clearSearch,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- ATTRIBUTION ---

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

// ============================================================
// ROUTE ACTION BUTTON
// ============================================================

class _RouteActionButton extends StatelessWidget {
  const _RouteActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DIRECTIONS SHEET
// ============================================================

/// Full scrollable step list as a draggable bottom sheet.
/// Current step is highlighted in coral; completed steps are dimmed.
class _DirectionsSheet extends StatelessWidget {
  const _DirectionsSheet({
    required this.route,
    required this.currentStepIndex,
  });

  final BravoRoute route;
  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, ScrollController scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: <Widget>[
              // Drag handle.
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.directions_rounded,
                        color: migoAmber, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Directions',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${route.steps.length} steps',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Step list.
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: route.steps.length,
                  separatorBuilder: (_, __) => const Divider(
                      color: Colors.white12, height: 1, indent: 64),
                  itemBuilder: (BuildContext ctx, int i) {
                    return _StepTile(
                      step: route.steps[i],
                      isCurrent: i == currentStepIndex,
                      isDone: i < currentStepIndex,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.isCurrent,
    required this.isDone,
  });

  final ManeuverStep step;
  final bool isCurrent;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final double distMi = step.distanceMiles;
    final String distLabel = distMi < 0.1
        ? '${(distMi * 5280).round()} ft'
        : '${distMi.toStringAsFixed(1)} mi';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrent
              ? migoAmber.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: isDone ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          _iconFor(step.type),
          color: isCurrent
              ? migoAmber          // yellow — pops against the dark sheet
              : isDone
                  ? Colors.white24
                  : Colors.white60,
          size: 22,
        ),
      ),
      title: Text(
        step.instruction,
        style: TextStyle(
          color: isDone ? Colors.white38 : Colors.white,
          fontSize: 14,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: step.streetNames.isNotEmpty
          ? Text(
              step.streetNames.first,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Text(
        distLabel,
        style: TextStyle(
          color: isCurrent ? migoAmber : Colors.white38,
          fontSize: 13,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  IconData _iconFor(ManeuverType type) {
    return switch (type) {
      ManeuverType.right => Icons.turn_right_rounded,
      ManeuverType.sharpRight => Icons.turn_sharp_right_rounded,
      ManeuverType.slightRight => Icons.turn_slight_right_rounded,
      ManeuverType.rampRight => Icons.turn_right_rounded,
      ManeuverType.left => Icons.turn_left_rounded,
      ManeuverType.sharpLeft => Icons.turn_sharp_left_rounded,
      ManeuverType.slightLeft => Icons.turn_slight_left_rounded,
      ManeuverType.rampLeft => Icons.turn_left_rounded,
      ManeuverType.uTurn => Icons.u_turn_left_rounded,
      ManeuverType.merge => Icons.merge_rounded,
      ManeuverType.roundaboutEnter ||
      ManeuverType.roundaboutExit =>
        Icons.roundabout_left_rounded,
      ManeuverType.destination => Icons.flag_rounded,
      ManeuverType.start => Icons.my_location_rounded,
      _ => Icons.straight_rounded,
    };
  }
}

// ============================================================
// MANEUVER BANNER
// ============================================================

class _ManeuverBanner extends StatelessWidget {
  const _ManeuverBanner({required this.navState});
  final NavigationState navState;

  @override
  Widget build(BuildContext context) {
    final ManeuverStep step = navState.currentStep;
    final double distM = navState.distanceToNextManeuverMeters;

    final String distLabel = distM < 50
        ? 'Now'
        : distM < 1000
            ? '${distM.round()} m'
            : '${(distM / 1000).toStringAsFixed(1)} km';

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: migoInk,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            _ManeuverIcon(type: step.type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    step.instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (navState.isLastStep)
                    const Text(
                      'You have arrived',
                      style: TextStyle(color: migoAmber, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              distLabel,
              style: const TextStyle(
                color: migoAmber,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManeuverIcon extends StatelessWidget {
  const _ManeuverIcon({required this.type});
  final ManeuverType type;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (type) {
      ManeuverType.right => Icons.turn_right_rounded,
      ManeuverType.sharpRight => Icons.turn_sharp_right_rounded,
      ManeuverType.slightRight => Icons.turn_slight_right_rounded,
      ManeuverType.rampRight => Icons.turn_right_rounded,
      ManeuverType.left => Icons.turn_left_rounded,
      ManeuverType.sharpLeft => Icons.turn_sharp_left_rounded,
      ManeuverType.slightLeft => Icons.turn_slight_left_rounded,
      ManeuverType.rampLeft => Icons.turn_left_rounded,
      ManeuverType.uTurn => Icons.u_turn_left_rounded,
      ManeuverType.merge => Icons.merge_rounded,
      ManeuverType.roundaboutEnter ||
      ManeuverType.roundaboutExit =>
        Icons.roundabout_left_rounded,
      ManeuverType.destination => Icons.flag_rounded,
      ManeuverType.start => Icons.my_location_rounded,
      _ => Icons.straight_rounded,
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: migoCoral.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: migoCoral, size: 22),
    );
  }
}

// ============================================================
// OFF-ROUTE BADGE
// ============================================================

class _OffRouteBadge extends StatelessWidget {
  const _OffRouteBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        color: migoAmber,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Recalculating…',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DESTINATION MARKER
// ============================================================

class _DestinationMarker extends StatelessWidget {
  const _DestinationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: migoCoral,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child:
          const Icon(Icons.flag_rounded, color: Colors.white, size: 16),
    );
  }
}

// ============================================================
// SAVE LOCATION SHEET
// ============================================================

/// Bottom sheet: lets the user save a geocoding result as Home, Work,
/// or a Favorite with a custom label.
class _SaveLocationSheet extends ConsumerStatefulWidget {
  const _SaveLocationSheet({required this.result});
  final GeocodingResult result;

  @override
  ConsumerState<_SaveLocationSheet> createState() => _SaveLocationSheetState();
}

class _SaveLocationSheetState extends ConsumerState<_SaveLocationSheet> {
  SavedLocationType _type = SavedLocationType.favorite;
  late final TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.result.shortName);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'Save Location',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // Type selector
          Row(
            children: SavedLocationType.values.map((SavedLocationType t) {
              final bool selected = _type == t;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _type = t;
                        if (_labelCtrl.text == _type.defaultLabel ||
                            SavedLocationType.values.any((SavedLocationType x) =>
                                x.defaultLabel == _labelCtrl.text)) {
                          _labelCtrl.text = t.defaultLabel;
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? t.color.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? t.color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: <Widget>[
                          Icon(t.icon,
                              color: selected ? t.color : Colors.white54,
                              size: 22),
                          const SizedBox(height: 4),
                          Text(
                            t.defaultLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? t.color : Colors.white54,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Label field
          TextField(
            controller: _labelCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Label',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _type.color,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(_type.icon, size: 18),
              label: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              onPressed: () async {
                await ref.read(savedLocationsProvider.notifier).saveFromResult(
                      type: _type,
                      result: widget.result,
                      customLabel: _labelCtrl.text.trim().isNotEmpty
                          ? _labelCtrl.text.trim()
                          : null,
                    );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LAYER TOGGLE BUTTON
// ============================================================

/// Small circular icon button for toggling a map layer on/off.
/// Active state uses the layer color; inactive is a semi-transparent dark pill.
class _LayerToggleButton extends StatelessWidget {
  const _LayerToggleButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active
                ? migoAmber.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            boxShadow: const <BoxShadow>[
              BoxShadow(blurRadius: 4, color: Colors.black26),
            ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? migoInk : Colors.white70,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REPORT HAZARD BUTTON
// ============================================================

class _ReportHazardButton extends StatelessWidget {
  const _ReportHazardButton({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'reportHazard',
      backgroundColor: migoCoral,
      foregroundColor: Colors.white,
      elevation: 4,
      tooltip: 'Report hazard',
      onPressed: () => ReportHazardSheet.show(context),
      child: const Icon(Icons.warning_amber_rounded),
    );
  }
}

// ============================================================
// SETTINGS BUTTON
// ============================================================

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () =>
            Navigator.of(context).pushNamed(SettingsScreen.routeName),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.settings_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
