// settings_provider.dart — Riverpod providers for user settings backed by
// the Hive settings box. One file per domain, per the repo structure.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';

// --- SETTINGS KEYS ---

/// Settings key: tile prefetch allowed only on WiFi. Defaults true and the
/// PRODUCT_BRIEF forbids cellular auto-downloads without explicit consent.
const String settingsKeyWifiOnlyTileSync = 'wifi_only_tile_sync';

// --- PROVIDERS ---

/// Whether tile prefetch is restricted to WiFi. Read by the offline cache
/// prefetcher before any bulk download.
final Provider<bool> wifiOnlyTileSyncProvider = Provider<bool>((Ref ref) {
  final Box<dynamic> settings = Hive.box<dynamic>(hiveBoxSettings);
  return settings.get(settingsKeyWifiOnlyTileSync, defaultValue: true) as bool;
});

// TODO: [route preference providers] [deferred to Phase 2]
// TODO: [privacy toggle providers (ALPR avoidance, location sharing)]
// [deferred to Phases 2/5 with their features]

// ---------------------------------------------------------------------------
// Phase 5: Location sharing toggle
// ---------------------------------------------------------------------------

/// Hive key for the location-sharing preference.
const String settingsKeyLocationSharing = 'location_sharing_enabled';

/// Whether the user has opted in to sharing their live location with their
/// family group. Defaults FALSE — sharing is strictly opt-in per PRODUCT_BRIEF.
final StateNotifierProvider<LocationSharingNotifier, bool>
    locationSharingEnabledProvider =
    StateNotifierProvider<LocationSharingNotifier, bool>(
  (_) => LocationSharingNotifier(),
);

class LocationSharingNotifier extends StateNotifier<bool> {
  LocationSharingNotifier()
      : super(
          Hive.box<dynamic>(hiveBoxSettings)
              .get(settingsKeyLocationSharing, defaultValue: false) as bool,
        );

  Future<void> toggle() async {
    state = !state;
    await Hive.box<dynamic>(hiveBoxSettings)
        .put(settingsKeyLocationSharing, state);
  }

  Future<void> set(bool value) async {
    state = value;
    await Hive.box<dynamic>(hiveBoxSettings)
        .put(settingsKeyLocationSharing, value);
  }
}
