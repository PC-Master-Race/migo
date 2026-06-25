// map_provider.dart — Riverpod state for the map: current zoom level and the
// derived visual mode. One file per domain, per the repo structure.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../services/map_service.dart';

// --- PROVIDERS ---

/// The map's current zoom level, updated by map_screen on camera changes.
final StateProvider<double> currentZoomProvider =
    StateProvider<double>((Ref ref) => mapDefaultZoom);

/// The visual mode derived from the current zoom — cartoon, hybrid, or
/// street. Widgets watch this to switch tile sources and avatar visibility.
final Provider<MapZoomMode> zoomModeProvider = Provider<MapZoomMode>((Ref ref) {
  final double zoomLevel = ref.watch(currentZoomProvider);
  return MapService.zoomModeForLevel(zoomLevel);
});
