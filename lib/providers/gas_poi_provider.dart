// gas_poi_provider.dart — Riverpod state for gas stations and POIs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/gas_model.dart';
import '../models/poi_model.dart';
import '../services/gas_price_service.dart';
import '../services/poi_service.dart';
import 'location_provider.dart';
import 'map_provider.dart'; // for currentZoomProvider

// ---------------------------------------------------------------------------
// Gas stations
// ---------------------------------------------------------------------------

/// Whether the gas layer is enabled. User toggles via map control.
final StateProvider<bool> gasLayerEnabledProvider =
    StateProvider<bool>((_) => false);

final AutoDisposeFutureProvider<List<GasStation>> nearbyGasStationsProvider =
    AutoDisposeFutureProvider<List<GasStation>>(
        (Ref ref) async {
  final bool enabled = ref.watch(gasLayerEnabledProvider);
  if (!enabled) return <GasStation>[];

  final dynamic pos = ref.watch(positionStreamProvider).valueOrNull;
  if (pos == null) return <GasStation>[];

  final LatLng center = LatLng(
    pos.latitude as double,
    pos.longitude as double,
  );
  return GasPriceService.instance.fetchNearbyStations(center);
});

// ---------------------------------------------------------------------------
// POIs
// ---------------------------------------------------------------------------

/// Which POI categories are currently shown on the map.
final StateProvider<Set<PoiCategory>> activePoisProvider =
    StateProvider<Set<PoiCategory>>(
  // parking excluded from default — it floods the map at street zoom.
  // Users can re-enable it in Settings → Map → POI categories.
  (_) => const <PoiCategory>{
    PoiCategory.restaurant,
    PoiCategory.cafe,
    PoiCategory.park,
    PoiCategory.pharmacy,
  },
);

final AutoDisposeFutureProvider<List<PointOfInterest>> nearbyPoisProvider =
    AutoDisposeFutureProvider<List<PointOfInterest>>(
        (Ref ref) async {
  final Set<PoiCategory> cats = ref.watch(activePoisProvider);
  if (cats.isEmpty) return <PointOfInterest>[];

  final double zoom = ref.watch(currentZoomProvider);
  final dynamic pos = ref.watch(positionStreamProvider).valueOrNull;
  if (pos == null) return <PointOfInterest>[];

  final LatLng center = LatLng(
    pos.latitude as double,
    pos.longitude as double,
  );

  return PoiService.instance.fetchNearby(
    center,
    zoom: zoom,
    categories: cats,
  );
});

// ---------------------------------------------------------------------------
// Selected station — for the report-price sheet and route-to action
// ---------------------------------------------------------------------------

final StateProvider<GasStation?> selectedGasStationProvider =
    StateProvider<GasStation?>((_) => null);
