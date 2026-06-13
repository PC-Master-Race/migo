// settings_provider.dart — Riverpod providers for user settings backed by
// the Hive settings box. One file per domain, per the repo structure.
//
// PRIVACY RULE (immutable): Every privacy-sensitive default is OFF.
// The user opts in; we never opt them in silently.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import '../services/map_service.dart'; // MapZoomMode

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
// Base class for all boolean toggle notifiers
// ---------------------------------------------------------------------------

/// Common base so [SettingsScreen] can call [toggle()] through a typed
/// [StateNotifierProvider<ToggleNotifier, bool>] without casting.
abstract class ToggleNotifier extends StateNotifier<bool> {
  ToggleNotifier(super.initial);

  Future<void> toggle() async {
    state = !state;
    await persist(!state); // note: state already flipped above
  }

  /// Subclasses persist the new value to Hive.
  Future<void> persist(bool previous);
}

// ---------------------------------------------------------------------------
// WiFi-only tile sync (defaults TRUE — not privacy-sensitive)
// ---------------------------------------------------------------------------

final StateNotifierProvider<WifiOnlyNotifier, bool> wifiOnlyTileSyncProvider =
    StateNotifierProvider<WifiOnlyNotifier, bool>((_) => WifiOnlyNotifier());

class WifiOnlyNotifier extends ToggleNotifier {
  WifiOnlyNotifier()
      : super(_box.get(settingsKeyWifiOnlyTileSync, defaultValue: true) as bool);

  @override
  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyWifiOnlyTileSync, state);
  }

  @override
  Future<void> persist(bool previous) async {}
}

// ---------------------------------------------------------------------------
// Location sharing (family) — defaults OFF
// ---------------------------------------------------------------------------

final StateNotifierProvider<LocationSharingNotifier, bool> locationSharingEnabledProvider =
    StateNotifierProvider<LocationSharingNotifier, bool>((_) => LocationSharingNotifier());

class LocationSharingNotifier extends ToggleNotifier {
  LocationSharingNotifier()
      : super(_box.get(settingsKeyLocationSharing, defaultValue: false) as bool);

  @override
  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyLocationSharing, state);
  }

  @override
  Future<void> persist(bool previous) async {}
}

// ---------------------------------------------------------------------------
// ALPR avoidance — defaults OFF
// ---------------------------------------------------------------------------

final StateNotifierProvider<AlprAvoidanceNotifier, bool> alprAvoidanceEnabledProvider =
    StateNotifierProvider<AlprAvoidanceNotifier, bool>((_) => AlprAvoidanceNotifier());

class AlprAvoidanceNotifier extends ToggleNotifier {
  AlprAvoidanceNotifier()
      : super(_box.get(settingsKeyAlprAvoidance, defaultValue: false) as bool);

  @override
  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyAlprAvoidance, state);
  }

  @override
  Future<void> persist(bool previous) async {}
}

// ---------------------------------------------------------------------------
// TTS (voice guidance) — defaults OFF
// ---------------------------------------------------------------------------

final StateNotifierProvider<TtsEnabledNotifier, bool> ttsEnabledProvider =
    StateNotifierProvider<TtsEnabledNotifier, bool>((_) => TtsEnabledNotifier());

class TtsEnabledNotifier extends ToggleNotifier {
  TtsEnabledNotifier()
      : super(_box.get(settingsKeyTtsEnabled, defaultValue: false) as bool);

  @override
  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyTtsEnabled, state);
  }

  @override
  Future<void> persist(bool previous) async {}
}

// ---------------------------------------------------------------------------
// Hazard alerts — defaults OFF
// ---------------------------------------------------------------------------

final StateNotifierProvider<HazardAlertsNotifier, bool> hazardAlertsEnabledProvider =
    StateNotifierProvider<HazardAlertsNotifier, bool>((_) => HazardAlertsNotifier());

class HazardAlertsNotifier extends ToggleNotifier {
  HazardAlertsNotifier()
      : super(_box.get(settingsKeyHazardAlerts, defaultValue: false) as bool);

  @override
  Future<void> toggle() async {
    state = !state;
    await _box.put(settingsKeyHazardAlerts, state);
  }

  @override
  Future<void> persist(bool previous) async {}
}

// ---------------------------------------------------------------------------
// Default zoom mode
// ---------------------------------------------------------------------------

final StateNotifierProvider<DefaultZoomModeNotifier, MapZoomMode> defaultZoomModeProvider =
    StateNotifierProvider<DefaultZoomModeNotifier, MapZoomMode>((_) => DefaultZoomModeNotifier());

class DefaultZoomModeNotifier extends StateNotifier<MapZoomMode> {
  DefaultZoomModeNotifier()
      : super(_parseZoomMode(_box.get(settingsKeyDefaultZoomMode, defaultValue: 'follow') as String));

  static MapZoomMode _parseZoomMode(String raw) =>
      MapZoomMode.values.firstWhere((MapZoomMode m) => m.name == raw, orElse: () => MapZoomMode.cartoon);

  Future<void> set(MapZoomMode mode) async {
    state = mode;
    await _box.put(settingsKeyDefaultZoomMode, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Route preference
// ---------------------------------------------------------------------------

enum RoutePreference { fastest, shortest, eco }

extension RoutePreferenceLabel on RoutePreference {
  String get label => switch (this) {
    RoutePreference.fastest  => 'Fastest',
    RoutePreference.shortest => 'Shortest',
    RoutePreference.eco      => 'Eco',
  };
}

final StateNotifierProvider<RoutePreferenceNotifier, RoutePreference> routePreferenceProvider =
    StateNotifierProvider<RoutePreferenceNotifier, RoutePreference>((_) => RoutePreferenceNotifier());

class RoutePreferenceNotifier extends StateNotifier<RoutePreference> {
  RoutePreferenceNotifier()
      : super(_parse(_box.get(settingsKeyRoutePreference, defaultValue: 'fastest') as String));

  static RoutePreference _parse(String raw) =>
      RoutePreference.values.firstWhere(
          (RoutePreference r) => r.name == raw, orElse: () => RoutePreference.fastest);

  Future<void> set(RoutePreference pref) async {
    state = pref;
    await _box.put(settingsKeyRoutePreference, pref.name);
  }
}

// ---------------------------------------------------------------------------
// Display name
// ---------------------------------------------------------------------------

final StateNotifierProvider<DisplayNameNotifier, String> displayNameProvider =
    StateNotifierProvider<DisplayNameNotifier, String>((_) => DisplayNameNotifier());

class DisplayNameNotifier extends StateNotifier<String> {
  DisplayNameNotifier()
      : super(_box.get(settingsKeyDisplayName, defaultValue: '') as String);

  Future<void> set(String name) async {
    state = name;
    await _box.put(settingsKeyDisplayName, name);
  }
}
