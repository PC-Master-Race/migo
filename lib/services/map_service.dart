// map_service.dart — OSM tile sourcing, zoom-mode logic, and offline cache.
// Decides which tile imagery the map shows at each zoom level, serves tiles
// offline-first from disk, and prefetches the 100-mile home region on WiFi.
// All tile behavior lives in one file so the full picture stays auditable.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../utils/map_utils.dart';
import '../utils/speed_utils.dart';

// --- LOCAL STORAGE DECISION ---
// Evaluated (per PRODUCT_BRIEF): Hive vs Isar for on-device caching.
//   • Isar maintenance has stalled (long-unresolved build issues on recent
//     toolchains), a real risk for a from-scratch app.
//   • Hive CE (community edition): actively maintained, pure Dart (works
//     identically on Android and iOS — no platform stubs needed), simple
//     key-value model fits tile-timestamp + settings needs perfectly.
//   • Tile IMAGE BYTES go to plain files on disk (path_provider), not into
//     any database — image blobs in a KV store bloat it for no benefit.
// CHOICE: Hive CE for metadata + filesystem for tile bytes.

// --- LOCAL CONSTANTS ---

/// Subdirectory under app documents where tile PNGs are stored.
const String tileCacheDirectoryName = 'tile_cache';

/// Pause between prefetch tile downloads (~7 tiles/sec).
/// The public OSM tile server is a donated resource; polite pacing is required.
const Duration prefetchPolitenessDelay = Duration(milliseconds: 150);

/// Hive metadata key storing when the last full home-region sync finished.
const String metadataKeyLastFullSync = 'last_full_sync_iso8601';

// --- ZOOM MODES ---

/// The three visual modes from PRODUCT_BRIEF's map behavior spec.
enum MapZoomMode {
  /// Full cartoon style — neighborhood names, simplified roads, avatars visible.
  cartoon,

  /// Hybrid — road details appear, avatars still visible, cartoon palette kept.
  hybrid,

  /// Street level — satellite imagery, avatars hidden, POI icons appear.
  street,
}

// --- MAP SERVICE ---

/// Maps zoom levels to visual modes and tile sources.
/// Also provides the Overpass-based speed limit lookup used by the HUD.
class MapService {
  /// Returns the [MapZoomMode] for [zoomLevel] using thresholds in constants.dart.
  ///
  /// SATELLITE/STREET MODE IS CURRENTLY DISABLED: the cartoon aesthetic is the
  /// whole point of the app, and the satellite↔cartoon tile swap broke
  /// immersion. We cap at hybrid so the map always renders the warm OSM cartoon
  /// look (cartoon far out, hybrid up close) and avatars stay visible at every
  /// zoom. All the satellite machinery below is intentionally left intact so a
  /// real street-level mode can be re-enabled later — just restore the
  /// `> hybridModeMaxZoom → MapZoomMode.street` line here.
  static MapZoomMode zoomModeForLevel(double zoomLevel) {
    if (zoomLevel <= cartoonModeMaxZoom) return MapZoomMode.cartoon;
    return MapZoomMode.hybrid;
  }

  /// Returns the tile URL template for [mode].
  /// Cartoon/hybrid use OSM raster tiles with a warm tint overlay applied in
  /// map_screen; street mode uses Esri satellite imagery.
  /// TODO: [custom cartoon tile style via styled vector/raster source]
  /// [deferred: needs a tile-styling pipeline; tint overlay approximates the
  /// warm cartoon palette until then]
  static String tileUrlTemplateForMode(MapZoomMode mode) {
    return mode == MapZoomMode.street
        ? satelliteTileUrlTemplate
        : osmTileUrlTemplate;
  }

  /// Returns the starting zoom level that best represents [mode].
  /// Used by map_screen to honour the user's "default zoom mode" preference
  /// from settings — the map opens at this zoom so the chosen style is visible
  /// immediately, and auto-switches as the user zooms in/out from there.
  static double startingZoomForMode(MapZoomMode mode) {
    return switch (mode) {
      MapZoomMode.cartoon => 12.0,  // neighbourhood overview
      MapZoomMode.hybrid  => 15.0,  // block-level (current default)
      MapZoomMode.street  => 17.0,  // building-level, satellite imagery
    };
  }

  /// Whether avatar cars should be visible in [mode].
  /// Street level hides them per PRODUCT_BRIEF (POI icons take over).
  static bool avatarsVisibleInMode(MapZoomMode mode) =>
      mode != MapZoomMode.street;

  /// Attribution text required by the active tile source.
  /// OSM and Esri both mandate visible attribution; this is a legal obligation.
  static String attributionForMode(MapZoomMode mode) {
    return mode == MapZoomMode.street
        ? 'Imagery © Esri'
        : '© OpenStreetMap contributors';
  }

  // --- SPEED LIMIT LOOKUP ---

  /// Fetches the speed limit of the road nearest [position] via Overpass API.
  /// Returns a display label ("45") or [speedLimitUnknownLabel] on any failure.
  /// Privacy note: only a ~30 m circle is sent, with no user identifiers.
  /// TODO: [proxy Overpass through Migo server so IPs never reach third party]
  /// [deferred: needs server infrastructure]
  static Future<String> fetchSpeedLimitLabelNear(LatLng position) async {
    final String query = '[out:json][timeout:5];'
        'way(around:$speedLimitSearchRadiusMeters,'
        '${position.latitude},${position.longitude})[maxspeed];'
        'out tags 1;';
    try {
      final http.Response response = await http.post(
        Uri.parse(overpassApiUrl),
        headers: <String, String>{'User-Agent': osmUserAgent},
        body: <String, String>{'data': query},
      );
      if (response.statusCode != 200) return speedLimitUnknownLabel;
      return _extractMaxspeedLabel(response.body);
    } catch (_) {
      return speedLimitUnknownLabel;
    }
  }

  /// Parses the first maxspeed tag from an Overpass JSON body.
  /// Kept separate to respect the 2-level nesting limit.
  static String _extractMaxspeedLabel(String body) {
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final List<dynamic> elements =
        decoded['elements'] as List<dynamic>? ?? <dynamic>[];
    if (elements.isEmpty) return speedLimitUnknownLabel;
    final Map<String, dynamic> tags =
        (elements.first as Map<String, dynamic>)['tags']
            as Map<String, dynamic>? ??
        <String, dynamic>{};
    return parseOsmMaxspeedTag(tags['maxspeed'] as String?);
  }
}

// --- TILE STORE ---

/// Disk-backed tile storage: PNG bytes as files, fetch timestamps in Hive.
class TileStore {
  static Directory? _cacheRootDirectory;

  /// Returns (and lazily creates) the tile cache root directory.
  static Future<Directory> _cacheRoot() async {
    if (_cacheRootDirectory != null) return _cacheRootDirectory!;
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir =
        Directory('${docs.path}/$tileCacheDirectoryName');
    await dir.create(recursive: true);
    _cacheRootDirectory = dir;
    return dir;
  }

  /// Returns the on-disk [File] for [tile] (may not exist yet).
  static Future<File> fileForTile(TileCoordinate tile) async {
    final Directory root = await _cacheRoot();
    return File('${root.path}/${tile.cacheKey}.png');
  }

  /// Reads cached bytes for [tile], or null when not yet cached.
  static Future<Uint8List?> readTileBytes(TileCoordinate tile) async {
    final File f = await fileForTile(tile);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Writes [bytes] to disk for [tile] and records the timestamp in Hive.
  static Future<void> writeTileBytes(TileCoordinate tile, Uint8List bytes) async {
    final File f = await fileForTile(tile);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    Hive.box<dynamic>(hiveBoxTileMetadata)
        .put(tile.cacheKey, DateTime.now().toIso8601String());
  }

  /// True when [tile] is cached and younger than [tileStaleAfterDays] days.
  static bool isTileFresh(TileCoordinate tile) {
    final dynamic stored =
        Hive.box<dynamic>(hiveBoxTileMetadata).get(tile.cacheKey);
    if (stored == null) return false;
    final int ageDays =
        DateTime.now().difference(DateTime.parse(stored as String)).inDays;
    return ageDays < tileStaleAfterDays;
  }

  /// Downloads [tile] from the OSM server and stores it. Returns true on success.
  static Future<bool> downloadAndStoreTile(TileCoordinate tile) async {
    final String url = osmTileUrlTemplate
        .replaceFirst('{z}', '${tile.zoom}')
        .replaceFirst('{x}', '${tile.x}')
        .replaceFirst('{y}', '${tile.y}');
    try {
      final http.Response r = await http.get(
        Uri.parse(url),
        headers: <String, String>{'User-Agent': osmUserAgent},
      );
      if (r.statusCode != 200) return false;
      await writeTileBytes(tile, r.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}

// --- OFFLINE-FIRST TILE PROVIDER ---

/// flutter_map TileProvider: disk first, network fallback, opportunistic cache.
/// Used for OSM cartoon/hybrid layers. Satellite stays network-only.
/// TODO: [satellite tile caching] [deferred: imagery tiles are large; needs
/// a storage budget decision before enabling]
class OfflineFirstTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(TileCoordinates coords, TileLayer options) {
    return _OfflineFirstTileImage(TileCoordinate(coords.z, coords.x, coords.y));
  }
}

/// ImageProvider that resolves tile bytes from disk, then network.
class _OfflineFirstTileImage extends ImageProvider<_OfflineFirstTileImage> {
  const _OfflineFirstTileImage(this.tile);
  final TileCoordinate tile;

  @override
  Future<_OfflineFirstTileImage> obtainKey(ImageConfiguration config) =>
      SynchronousFuture<_OfflineFirstTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _OfflineFirstTileImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadTile(decode));
  }

  /// Loads bytes from disk, falls back to network, then decodes.
  Future<ImageInfo> _loadTile(ImageDecoderCallback decode) async {
    Uint8List? bytes = await TileStore.readTileBytes(tile);
    if (bytes == null) {
      if (await TileStore.downloadAndStoreTile(tile)) {
        bytes = await TileStore.readTileBytes(tile);
      }
    }
    if (bytes == null) {
      throw Exception('Tile unavailable offline: ${tile.cacheKey}');
    }
    final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.Codec codec = await decode(buf);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is _OfflineFirstTileImage && other.tile == tile;

  @override
  int get hashCode => tile.hashCode;
}

// --- HOME REGION PREFETCHER ---

/// Bulk-downloads the 100-mile home region for offline use.
/// Enforces PRODUCT_BRIEF hard rules: WiFi-only default, weekly cadence,
/// polite pacing for the donated OSM tile infrastructure.
class TilePrefetcher {
  static bool _prefetchInProgress = false;

  /// Prefetches tiles within [offlineCacheRadiusMiles] of [homeCenter].
  /// [wifiOnlyAllowed] comes from the user's settings (default: true).
  static Future<void> prefetchHomeRegion(
    LatLng homeCenter, {
    required bool wifiOnlyAllowed,
  }) async {
    if (_prefetchInProgress || _syncedWithinPastWeek()) return;
    if (wifiOnlyAllowed && !await _isOnWifi()) return;

    _prefetchInProgress = true;
    try {
      await _downloadMissingTiles(homeCenter);
      Hive.box<dynamic>(hiveBoxTileMetadata)
          .put(metadataKeyLastFullSync, DateTime.now().toIso8601String());
    } finally {
      _prefetchInProgress = false;
    }
  }

  /// True when the last full sync was within [tileStaleAfterDays] days.
  static bool _syncedWithinPastWeek() {
    final dynamic last =
        Hive.box<dynamic>(hiveBoxTileMetadata).get(metadataKeyLastFullSync);
    if (last == null) return false;
    return DateTime.now().difference(DateTime.parse(last as String)).inDays <
        tileStaleAfterDays;
  }

  /// True when the device is on WiFi or ethernet (an unmetered connection).
  static Future<bool> _isOnWifi() async {
    final List<ConnectivityResult> conns =
        await Connectivity().checkConnectivity();
    return conns.contains(ConnectivityResult.wifi) ||
        conns.contains(ConnectivityResult.ethernet);
  }

  /// Downloads every stale or missing tile in the region, paced politely.
  static Future<void> _downloadMissingTiles(LatLng center) async {
    final List<TileCoordinate> tiles = tilesWithinRadius(
      center: center,
      radiusMiles: offlineCacheRadiusMiles,
      minZoom: offlineCacheMinZoom,
      maxZoom: offlineCacheMaxZoom,
    );
    for (final TileCoordinate tile in tiles) {
      if (TileStore.isTileFresh(tile)) continue;
      await TileStore.downloadAndStoreTile(tile);
      await Future<void>.delayed(prefetchPolitenessDelay);
    }
  }

  // TODO: [delta updates on app launch — only re-fetch changed tiles]
  // [deferred: raster OSM tiles have no diff feed; needs ETag checks per
  // tile or a migration to vector tiles with a proper change log]
}
