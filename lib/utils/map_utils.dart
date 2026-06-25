// map_utils.dart — Pure tile/geo math: lat-lng ↔ slippy-map tile coordinates
// and radius → tile-range expansion for the offline prefetcher.
// Pure functions only: no state, no I/O, fully unit-testable.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../constants.dart';

// --- DISTANCE FORMATTING (US units) ---

/// Formats [meters] as a US-style distance string for the turn banner and
/// voice. Under ~0.1 mi it shows feet (rounded to the nearest 10 ft); under
/// 10 mi it shows one decimal of miles; above that, whole miles.
/// When [spoken] is true it uses full words ("feet"/"miles") so the TTS engine
/// reads them naturally instead of saying "ft"/"mi".
String formatUsDistance(double meters, {bool spoken = false}) {
  final double miles = meters / metersPerMile;
  if (miles < 0.1) {
    final int feet = ((meters * 3.28084) / 10).round() * 10; // nearest 10 ft
    return spoken ? '$feet feet' : '$feet ft';
  }
  if (miles < 10) {
    final String n = miles.toStringAsFixed(1);
    return spoken ? '$n miles' : '$n mi';
  }
  final int whole = miles.round();
  return spoken ? '$whole miles' : '$whole mi';
}

// --- TILE COORDINATE ---

/// A single slippy-map tile address (z/x/y), the unit of OSM tile fetching.
class TileCoordinate {
  /// Creates a tile address.
  const TileCoordinate(this.zoom, this.x, this.y);

  /// Zoom level (z in the URL template).
  final int zoom;

  /// Horizontal tile index (x).
  final int x;

  /// Vertical tile index (y).
  final int y;

  /// Stable cache key, e.g. "13/1309/3166" — doubles as the on-disk path.
  String get cacheKey => '$zoom/$x/$y';

  @override
  bool operator ==(Object other) =>
      other is TileCoordinate &&
      other.zoom == zoom &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(zoom, x, y);
}

// --- TILE MATH ---

/// Converts a geographic [position] to the tile containing it at [zoom].
/// Standard slippy-map formula (Web Mercator).
TileCoordinate latLngToTile(LatLng position, int zoom) {
  final int tilesPerAxis = 1 << zoom; // 2^zoom tiles per axis at this zoom
  final double latitudeRadians = position.latitude * math.pi / 180.0;

  final int tileX =
      ((position.longitude + 180.0) / 360.0 * tilesPerAxis).floor();
  final int tileY = ((1.0 -
              math.log(math.tan(latitudeRadians) +
                      1.0 / math.cos(latitudeRadians)) /
                  math.pi) /
          2.0 *
          tilesPerAxis)
      .floor();

  // Clamp to valid range — latitudes near the poles overflow the formula.
  final int clampedX = tileX.clamp(0, tilesPerAxis - 1);
  final int clampedY = tileY.clamp(0, tilesPerAxis - 1);
  return TileCoordinate(zoom, clampedX, clampedY);
}

/// Lists every tile within [radiusMiles] of [center] for each zoom level
/// from [minZoom] to [maxZoom] inclusive. This is the offline prefetcher's
/// shopping list for the 100-mile cache.
List<TileCoordinate> tilesWithinRadius({
  required LatLng center,
  required double radiusMiles,
  required int minZoom,
  required int maxZoom,
}) {
  final List<TileCoordinate> tiles = <TileCoordinate>[];
  final double radiusMeters = radiusMiles * metersPerMile;

  for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
    tiles.addAll(_tilesAtZoomWithinRadius(center, radiusMeters, zoom));
  }
  return tiles;
}

/// Lists tiles at a single [zoom] whose bounding square intersects the circle
/// of [radiusMeters] around [center]. Helper kept separate to honor the
/// 2-level nesting limit.
List<TileCoordinate> _tilesAtZoomWithinRadius(
  LatLng center,
  double radiusMeters,
  int zoom,
) {
  const Distance geodesicDistance = Distance();

  // Corners of the bounding box around the radius circle.
  final LatLng northEdge =
      geodesicDistance.offset(center, radiusMeters, 0); // due north
  final LatLng eastEdge =
      geodesicDistance.offset(center, radiusMeters, 90); // due east
  final LatLng southEdge =
      geodesicDistance.offset(center, radiusMeters, 180); // due south
  final LatLng westEdge =
      geodesicDistance.offset(center, radiusMeters, 270); // due west

  final TileCoordinate topLeft =
      latLngToTile(LatLng(northEdge.latitude, westEdge.longitude), zoom);
  final TileCoordinate bottomRight =
      latLngToTile(LatLng(southEdge.latitude, eastEdge.longitude), zoom);

  final List<TileCoordinate> tilesAtThisZoom = <TileCoordinate>[];
  for (int x = topLeft.x; x <= bottomRight.x; x++) {
    for (int y = topLeft.y; y <= bottomRight.y; y++) {
      tilesAtThisZoom.add(TileCoordinate(zoom, x, y));
    }
  }
  return tilesAtThisZoom;
}
