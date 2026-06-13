// settings_provider.dart — Riverpod providers for user settings backed by
// the Hive settings box. One file per domain, per the repo structure.
//
// PRIVACY RULE (immutable): Every privacy-sensitive default is OFF.
// The user opts in; we never opt them in silently.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import '../providers/map_provider.dart'; // MapZoomMode

// ---------------------------------------------------------------------------
// Settings keys
// ---------------------------------------------------------------------------

const String settingsKeyWifiOnlyTileSync    = 'wifi_only_tile_sync';
const String settingsKeyLocationSharing     = 'location_sharing_enabled';
const String settingsKeyAlprAvoidance       = 'alpr_avoidance_enabled';
const String settingsKeyTtsEnabled          = 'tts_enabled';
const String settingsKeyHazardAlerts        = 'hazard_alerts_enabled';
const String settingsKeyDefaultZoomMode     = 'default_zoom_mode';
const String settingsKeyRoutePreference     = 'route_preference';
const String settingsKeyDisplayName         = 'display_name';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Box<dynamic> get _box => Hive.box<dynamic>(hiveBoxSettings);

// ---------------------------------------------------------------------------
// WiFi-only tile sync
// ---------------------------------------------------------------------------

/// Whether tile prefetch is restricted to WiFi. Defaults true.
final StateNotifierProvider<WifiOnlyNotifier, bool> wifiOnlyTileSyncProvider =
    StateNotifierProvider<WifiOnlyNotifier, bool>(
  (_) => WifiOnlyNotifier(),
);

class WifiOnlyNotifier extends StateNotifier<bool> {
  WifiOnlyNotifier()
      : super(_box.get(settingsKeyWifiOnlyTileSync, defaultValue: true) as bool);

  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyWifiOnlyTileSync, state);
  }
}

// ---------------------------------------------------------------------------
// Phase 5: Location sharing toggle
// ---------------------------------------------------------------------------
