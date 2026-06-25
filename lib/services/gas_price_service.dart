// gas_price_service.dart — Gas station locations + community price reports.
//
// Station locations come from Overpass (OSM, no API key, no tracking).
// Prices come from Supabase — reported by users, awarded with Bravos.
// No commercial fuel price feed is used. No data sold. No third parties.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/gas_model.dart';
import '../models/bravo_model.dart';
import 'bravo_service.dart';
import 'supabase_service.dart';

class GasPriceService {
  GasPriceService._();
  static final GasPriceService instance = GasPriceService._();

  // Simple in-memory cache keyed by rounded lat/lon (0.05° resolution ≈ 3mi).
  final Map<String, List<GasStation>> _stationCache =
      <String, List<GasStation>>{};

  // =========================================================================
  // Station fetch — Overpass
  // =========================================================================

  /// Fetches gas stations within [radiusMiles] of [center].
  /// Results are merged with latest community prices from Supabase.
  Future<List<GasStation>> fetchNearbyStations(
    LatLng center, {
    double radiusMiles = 10.0,
  }) async {
    final String cacheKey = _cacheKey(center);
    if (_stationCache.containsKey(cacheKey)) {
      return _stationCache[cacheKey]!;
    }

    final double radiusMeters = radiusMiles * 1609.34;
    final String query =
        '[out:json][timeout:10];'
        'node["amenity"="fuel"]'
        '(around:${radiusMeters.round()},${center.latitude},${center.longitude});'
        'out body;';

    List<GasStation> stations = <GasStation>[];
    try {
      final http.Response resp = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: query,
            headers: <String, String>{'User-Agent': osmUserAgent},
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(resp.body) as Map<String, dynamic>;
        final List<dynamic> elements =
            data['elements'] as List<dynamic>? ?? <dynamic>[];
        stations = elements
            .whereType<Map<String, dynamic>>()
            .where((Map<String, dynamic> e) => e['type'] == 'node')
            .map(GasStation.fromOverpass)
            .toList();
      }
    } catch (_) {
      // Overpass failure — return empty list, no crash.
    }

    // Merge with Supabase prices.
    if (stations.isNotEmpty) {
      stations = await _mergePrices(stations);
    }

    _stationCache[cacheKey] = stations;
    return stations;
  }

  // =========================================================================
  // Price fetch — Supabase
  // =========================================================================

  /// Loads the most recent price per grade for each station in [stationIds].
  Future<List<GasStation>> _mergePrices(List<GasStation> stations) async {
    final List<String> ids = stations.map((GasStation s) => s.id).toList();
    try {
      final List<Map<String, dynamic>> rows = await SupabaseService.client
          .from('gas_prices')
          .select()
          .inFilter('station_osm_id', ids)
          .order('reported_at', ascending: false);

      // Group latest price per (station, grade).
      final Map<String, Map<FuelGrade, GasPrice>> priceMap =
          <String, Map<FuelGrade, GasPrice>>{};
      for (final Map<String, dynamic> row in rows) {
        final GasPrice price = GasPrice.fromJson(row);
        priceMap.putIfAbsent(
            price.stationOsmId, () => <FuelGrade, GasPrice>{});
        // Only keep the most recent per grade (rows are ordered desc).
        priceMap[price.stationOsmId]!
            .putIfAbsent(price.grade, () => price);
      }

      return stations
          .map((GasStation s) => s.copyWith(
                latestPrices: priceMap[s.id] ?? <FuelGrade, GasPrice>{},
              ))
          .toList();
    } catch (_) {
      return stations; // Return without prices if Supabase fails.
    }
  }

  // =========================================================================
  // Price report — community contribution
  // =========================================================================

  /// Reports a fuel price seen at [stationOsmId]. Awards Bravos to reporter.
  Future<void> reportPrice({
    required String stationOsmId,
    required FuelGrade grade,
    required double pricePerGallon,
  }) async {
    final String? userId =
        SupabaseService.client.auth.currentSession?.user.id;
    if (userId == null) throw Exception('Not authenticated.');

    if (pricePerGallon < 0.5 || pricePerGallon > 15.0) {
      throw Exception('Price out of reasonable range.');
    }

    final GasPrice report = GasPrice(
      id: '',
      stationOsmId: stationOsmId,
      grade: grade,
      pricePerGallon: pricePerGallon,
      reportedAt: DateTime.now(),
      reporterId: userId,
    );

    await SupabaseService.client.from('gas_prices').insert(report.toJson());

    // Clear cache so next fetch picks up the new price.
    _stationCache.clear();

    // Award Bravos for contributing price data.
    await BravoService.instance.awardDrivingAchievement(
      userId,
      AchievementId.firstReport, // reuses firstReport as a proxy for now
      // Phase 7: add dedicated gasPriceReporter achievement
    );
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  String _cacheKey(LatLng p) {
    // Round to 0.05° ≈ 3.5 miles — same area reuses cached results.
    final double lat = (p.latitude / 0.05).roundToDouble() * 0.05;
    final double lon = (p.longitude / 0.05).roundToDouble() * 0.05;
    return '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
  }

  /// Straight-line distance between two LatLngs in miles.
  static double distanceMiles(LatLng a, LatLng b) {
    const double R = 3958.8;
    final double lat1 = a.latitude * math.pi / 180;
    final double lat2 = b.latitude * math.pi / 180;
    final double dLat = (b.latitude - a.latitude) * math.pi / 180;
    final double dLon = (b.longitude - a.longitude) * math.pi / 180;
    final double x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }
}
