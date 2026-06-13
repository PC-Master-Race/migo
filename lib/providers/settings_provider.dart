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
