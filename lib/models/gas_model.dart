// gas_model.dart — Gas station and community-reported fuel price models.
//
// DATA SOURCES:
//   Station locations: Overpass API (OSM amenity=fuel). No API key required.
//   Fuel prices:       Community-reported by Bravo Maps users (same model
//                      as Waze fuel prices). Stored in Supabase gas_prices.
//                      No third-party price feed — all data stays in-house.
//
// PRIVACY: The reporter's user ID is stored so we can award Bravos, but
// is never exposed to other users — only the price and timestamp are shown.

// ---------------------------------------------------------------------------
// Fuel grade enum
// ---------------------------------------------------------------------------

enum FuelGrade {
  regular,   // 87 octane (most common)
  midgrade,  // 89 octane
  premium,   // 91–93 octane
  diesel,
}

extension FuelGradeLabel on FuelGrade {
  String get label => switch (this) {
        FuelGrade.regular  => 'Regular',
        FuelGrade.midgrade => 'Mid',
        FuelGrade.premium  => 'Premium',
        FuelGrade.diesel   => 'Diesel',
      };
  String get shortLabel => switch (this) {
        FuelGrade.regular  => 'REG',
        FuelGrade.midgrade => 'MID',
        FuelGrade.premium  => 'PRE',
        FuelGrade.diesel   => 'DSL',
      };
}

// ---------------------------------------------------------------------------
// GasStation — from Overpass API
// ---------------------------------------------------------------------------

/// A gas station fetched from OpenStreetMap via Overpass.
class GasStation {
  const GasStation({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.name,
    this.brand,
    this.latestPrices = const <FuelGrade, GasPrice>{},
  });

  /// OSM node ID (as string).
  final String id;
  final double latitude;
  final double longitude;

  /// Station name from OSM tags (e.g. "Shell", "BP", "Chevron").
  final String? name;

  /// Brand tag from OSM (may differ from name).
  final String? brand;

  /// Most recent community-reported price per grade.
  /// Empty until gas_prices are loaded from Supabase.
  final Map<FuelGrade, GasPrice> latestPrices;

  /// Display name: brand → name → "Gas Station".
  String get displayName => brand ?? name ?? 'Gas Station';

  /// Cheapest reported regular price, or null if none reported.
  double? get regularPrice => latestPrices[FuelGrade.regular]?.pricePerGallon;

  factory GasStation.fromOverpass(Map<String, dynamic> element) {
    final Map<String, dynamic> tags =
        element['tags'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return GasStation(
      id: element['id'].toString(),
      latitude: (element['lat'] as num).toDouble(),
      longitude: (element['lon'] as num).toDouble(),
      name: tags['name'] as String?,
      brand: tags['brand'] as String?,
    );
  }

  GasStation copyWith({Map<FuelGrade, GasPrice>? latestPrices}) => GasStation(
        id: id,
        latitude: latitude,
        longitude: longitude,
        name: name,
        brand: brand,
        latestPrices: latestPrices ?? this.latestPrices,
      );
}

// ---------------------------------------------------------------------------
// GasPrice — community-reported price row
// ---------------------------------------------------------------------------

/// A single user-reported fuel price at a specific station.
class GasPrice {
  const GasPrice({
    required this.id,
    required this.stationOsmId,
    required this.grade,
    required this.pricePerGallon,
    required this.reportedAt,
    this.reporterId,
  });

  final String id;
  final String stationOsmId;
  final FuelGrade grade;

  /// Price in USD per gallon (e.g. 3.459).
  final double pricePerGallon;
  final DateTime reportedAt;

  /// Reporter's user ID — used only for Bravos award, never shown to others.
  final String? reporterId;

  /// How stale this price is.
  Duration get age => DateTime.now().difference(reportedAt);
  bool get isFresh => age.inHours < 12;
  bool get isStale => age.inHours >= 24;

  factory GasPrice.fromJson(Map<String, dynamic> json) => GasPrice(
        id: json['id'] as String,
        stationOsmId: json['station_osm_id'] as String,
        grade: FuelGrade.values.byName(json['grade'] as String),
        pricePerGallon: (json['price_per_gallon'] as num).toDouble(),
        reportedAt: DateTime.parse(json['reported_at'] as String),
        reporterId: json['reporter_id'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'station_osm_id': stationOsmId,
        'grade': grade.name,
        'price_per_gallon': pricePerGallon,
        'reporter_id': reporterId,
      };
}
