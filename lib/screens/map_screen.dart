// map_screen.dart — The main navigation screen.
// Phase 1: live map, follow-user camera, three zoom modes, speed HUD.
// Phase 2: destination search bar, route polyline, maneuver banner,
//          off-route recalculation, route options bottom sheet.


import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';
import '../providers/location_provider.dart';
import '../providers/map_provider.dart';
import '../providers/routing_provider.dart';
import '../providers/settings_provider.dart';
import '../services/map_service.dart';
import '../services/supabase_service.dart';
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

/// Time to wait after a keystroke before issuing a Nominatim search.
/// Enforces Nominatim's 1 req/s policy guideline.
const Duration _searchDebounce = Duration(milliseconds: 500);

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

  bool _isFollowingUser = true;
  bool _prefetchStarted = false;
  bool _showSearchResults = false;
  bool _hasHadFirstFix = false;

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

  // --- SEARCH ---

  void _onSearchChanged(String query) {
    ref.read(geocodeQueryProvider.notifier).state = query;
    setState(() => _showSearchResults = query.isNotEmpty);
  }

  void _onSearchSubmitted(String query) {
    // Trigger search immediately on submit regardless of debounce.
    ref.read(geocodeQueryProvider.notifier).state = query;
    setState(() => _showSearchResults = query.isNotEmpty);
  }

  void _selectDestination(GeocodingResult result) {
    // Dismiss keyboard + search results.
    _searchFocus.unfocus();
    _searchController.text = result.shortName;
    setState(() => _showSearchResults = false);

    // Set destination and calculate route.
    ref.read(destinationProvider.notifier).state = result.position;

    final Position? pos = ref.read(positionStreamProvider).valueOrNull;
    if (pos != null) {
      ref.read(activeRouteProvider.notifier).calculate(
            destination: result.position,
          );
    }

    // Pan map to show destination.
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
    });
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final MapZoomMode zoomMode = ref.watch(zoomModeProvider);
    final Position? position = ref.watch(positionStreamProvider).valueOrNull;
    final BravoRoute? route = ref.watch(activeRouteProvider).valueOrNull;
    final NavigationState? navState = ref.watch(navigationStateProvider);

    // Activate side-effect providers every build so they stay alive.
    ref.watch(prefAutoRecalcProvider);
    ref.watch(ttsAnnouncerProvider);
    ref.watch(hazardAlertWatcherProvider);

    if (position != null) {
      _startPrefetchOnce(position);
      _handleFirstFix(position);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _followPositionIfEnabled(position),
      );
    }

    // Off-route: trigger recalculation once per off-route detection.
    final bool isOffRoute = ref.watch(offRouteProvider);
    if (isOffRoute && route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeRouteProvider.notifier).recalculate();
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          // Base map — wrapped in a perspective tilt when actively navigating.
          _buildMapWithTilt(zoomMode, position, route, navState),

          // Attribution (bottom right).
          _buildAttributionBadge(zoomMode),

          // Search bar + results overlay (top).
          _buildSearchOverlay(context),

          // Maneuver banner (below search bar, only when navigating).
          if (navState != null)
            Positioned(
              top: 80,
              left: 12,
              right: 12,
              child: _ManeuverBanner(navState: navState),
            ),

          // Off-route recalculating indicator.
          if (isOffRoute && route != null)
            Positioned(
              top: navState != null ? 154 : 80,
              left: 0,
              right: 0,
              child: const _OffRouteBadge(),
            ),

          // Speed HUD — bottom-left so it never overlaps the status bar
          // or the search/maneuver banners at the top.
          const Positioned(
            bottom: 32,
            left: 16,
            child: SpeedHud(),
          ),

          // Report hazard FAB — always visible (bottom-left stack).
          Positioned(
            bottom: 100,
            left: 16,
            child: _ReportHazardButton(context: context),
          ),

          // Route options button (above the report button when navigating).
          if (route != null)
            Positioned(
              bottom: 160,
              left: 16,
              child: _RouteOptionsButton(context: context),
            ),

          // Bravos balance chip — bottom-right above recenter button.
          const Positioned(
            bottom: 88,
            right: 16,
            child: BravosHudChip(),
          ),

          // Recenter button (bottom-right, when not following).
          if (!_isFollowingUser)
            Positioned(
              bottom: 32,
              right: 16,
              child: RecenterButton(onPressed: _recenterOnUser),
            ),

          // Settings gear — top-right, tucked below the status bar.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: _SettingsButton(context: context),
          ),

          // Search results dropdown.
          if (_showSearchResults) _buildSearchResultsOverlay(),

          // Phase 3: hazard alert banner (above map, below search bar).
          Positioned(
            top: navState != null ? 160 : 86,
            left: 0,
            right: 0,
            child: const HazardAlertStack(),
          ),

        ],
      ),
    );
  }

  // --- MAP LAYERS ---

  /// Wraps [_buildMap] in a perspective Transform when [navState] is active,
  /// giving a Waze-like driving-perspective tilt (45-60 degrees). Returns the
  /// flat map when not navigating so the top-down view is fully interactive.
  Widget _buildMapWithTilt(
    MapZoomMode zoomMode,
    Position? position,
    BravoRoute? route,
    NavigationState? navState,
  ) {
    final Widget map = _buildMap(zoomMode, position, route);
    if (navState == null) return map;
    return Transform(
      // Anchor the tilt at the bottom centre so the user's position
      // stays in place while the horizon recedes toward the top.
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, mapTiltPerspective)   // perspective depth
        ..rotateX(-mapTiltRadians),            // tilt top away from viewer
      child: map,
    );
  }

  Widget _buildMap(
    MapZoomMode zoomMode,
    Position? position,
    BravoRoute? route,
  ) {
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
          tileProvider: zoomMode == MapZoomMode.street
              ? NetworkTileProvider()
              : OfflineFirstTileProvider(),
        ),
        _buildCartoonTintOverlay(zoomMode),

        // Route polyline — drawn below the user marker so the dot stays on top.
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

        // Phase 3: hazard pins layer.
        _buildHazardLayer(ref),

        // Phase 5: family member live-location layer.
        _buildFamilyLayer(ref),

        // Phase 6: gas station price pins.
        _buildGasLayer(ref),

        // Phase 6: POI pins (restaurants, parking, etc.).
        _buildPoiLayer(ref),

        // User position marker.
        if (position != null) _buildUserMarkerLayer(position),
      ],
    );
  }


  /// Builds the family member MarkerLayer from Supabase Realtime stream.
  /// Only shows members who are actively sharing and have a non-expired ping.
  Widget _buildFamilyLayer(WidgetRef ref) {
    // Activate the publisher side-effect (no-op if sharing is off).
    ref.watch(locationPublisherProvider);

    final List<FamilyLocation> locations =
        ref.watch(familyLocationsProvider).valueOrNull ?? <FamilyLocation>[];
    final Map<String, FamilyMember> memberMap =
        ref.watch(familyMemberMapProvider);

    if (locations.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: locations.map((FamilyLocation loc) {
        final FamilyMember? member = memberMap[loc.userId];
        if (member == null) return null;
        return Marker(
          point: LatLng(loc.latitude, loc.longitude),
          width: 64,
          height: 80,
          child: FamilyMemberMarker(member: member, location: loc),
        );
      }).whereType<Marker>().toList(),
    );
  }

  /// Builds gas station price-bubble markers.
  /// Hidden when the gas layer toggle is off or no stations are nearby.
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

  /// Builds POI pin markers for all active categories.
  /// Hidden when no categories are toggled on.
  Widget _buildPoiLayer(WidgetRef ref) {
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

  /// Builds the hazard pin MarkerLayer from [nearbyHazardsProvider].
  /// Confirmed hazards are full-opacity; own pending pins are dimmed.
  Widget _buildHazardLayer(WidgetRef ref) {
    final List<Hazard> hazards =
        ref.watch(nearbyHazardsProvider).valueOrNull ?? <Hazard>[];
    if (hazards.isEmpty) return const SizedBox.shrink();

    final String? myId = SupabaseService.isConnected
        ? null // reporter_id not available client-side without extra query
        : null;

    return MarkerLayer(
      markers: hazards.map((Hazard h) {
        final bool isOwn = myId != null;
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

  // --- SEARCH OVERLAY ---

  Widget _buildSearchOverlay(BuildContext context) {
    return Positioned(
      top: 44,
      left: 12,
      right: 12,
      child: SafeArea(
        child: Material(
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
              // Route options (gear icon) when navigating.
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
      ),
    );
  }

  Widget _buildSearchResultsOverlay() {
    final AsyncValue<List<GeocodingResult>> results =
        ref.watch(geocodeResultsProvider);

    return Positioned(
      top: 104,
      left: 12,
      right: 12,
      child: Material(
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
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (BuildContext ctx, int i) {
                final GeocodingResult r = items[i];
                return ListTile(
                  leading: const Icon(Icons.place_rounded, color: migoCoral),
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
                    style:
                        TextStyle(fontSize: 12, color: migoInk.withValues(alpha: 0.5)),
                  ),
                  onTap: () => _selectDestination(r),
                );
              },
            );
          },
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

// --- MANEUVER BANNER ---

/// Top-of-screen card showing the next turn instruction and distance.
class _ManeuverBanner extends StatelessWidget {
  const _ManeuverBanner({required this.navState});
  final NavigationState navState;

  @override
  Widget build(BuildContext context) {
    final ManeuverStep step = navState.currentStep;
    final double distM = navState.distanceToNextManeuverMeters;

    // Format distance: metres under 500, then feet are US convention, but for
    // Phase 2 we use metres. TODO: [unit preference toggle] [Phase 7 polish]
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

/// Icon representing the maneuver direction.
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

// --- OFF-ROUTE BADGE ---

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

// --- DESTINATION MARKER ---

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
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.flag_rounded, color: Colors.white, size: 16),
    );
  }
}

// --- ROUTE OPTIONS BUTTON ---

class _RouteOptionsButton extends StatelessWidget {
  const _RouteOptionsButton({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'routeOptions',
      backgroundColor: Colors.white,
      foregroundColor: migoCoral,
      elevation: 4,
      tooltip: 'Route options',
      onPressed: () => RouteOptionsScreen.showSheet(context),
      child: const Icon(Icons.tune_rounded),
    );
  }
}

// --- REPORT HAZARD BUTTON ---

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

// --- SETTINGS BUTTON ---

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
        onTap: () => Navigator.of(context).pushNamed(SettingsScreen.routeName),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.settings_rounded,
              color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
