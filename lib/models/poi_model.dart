// poi_model.dart — Points of Interest from OpenStreetMap via Overpass.
// No API key required. No tracking. Pure OSM data.

import 'package:flutter/material.dart';

enum PoiCategory {
  restaurant,
  cafe,
  parking,
  park,
  pharmacy,
  atm,
  grocery,
  hospital,
  gasStation,
  hotel,
}

extension PoiCategoryDisplay on PoiCategory {
  String get label => switch (this) {
        PoiCategory.restaurant => 'Restaurant',
        PoiCategory.cafe       => 'Café',
        PoiCategory.parking    => 'Parking',
        PoiCategory.park       => 'Park',
        PoiCategory.pharmacy   => 'Pharmacy',
        PoiCategory.atm        => 'ATM',
        PoiCategory.grocery    => 'Grocery',
        PoiCategory.hospital   => 'Hospital',
        PoiCategory.gasStation => 'Gas Station',
        PoiCategory.hotel      => 'Hotel',
      };

  IconData get icon => switch (this) {
        PoiCategory.restaurant => Icons.restaurant,
        PoiCategory.cafe       => Icons.local_cafe,
        PoiCategory.parking    => Icons.local_parking,
        PoiCategory.park       => Icons.park,
        PoiCategory.pharmacy   => Icons.local_pharmacy,
        PoiCategory.atm        => Icons.atm,
        PoiCategory.grocery    => Icons.shopping_basket,
        PoiCategory.hospital   => Icons.local_hospital,
        PoiCategory.gasStation => Icons.local_gas_station,
        PoiCategory.hotel      => Icons.hotel,
      };

  Color get color => switch (this) {
        PoiCategory.restaurant => const Color(0xFFEF5350),
        PoiCategory.cafe       => const Color(0xFF8D6E63),
        PoiCategory.parking    => const Color(0xFF1565C0),
        PoiCategory.park       => const Color(0xFF43A047),
        PoiCategory.pharmacy   => const Color(0xFF00897B),
        PoiCategory.atm        => const Color(0xFFFFB300),
        PoiCategory.grocery    => const Color(0xFF7B1FA2),
        PoiCategory.hospital   => const Color(0xFFE53935),
        PoiCategory.gasStation => const Color(0xFF0288D1),
        PoiCategory.hotel      => const Color(0xFF6D4C41),
      };
}

class PointOfInterest {
  const PointOfInterest({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.name,
    this.address,
    this.openingHours,
    this.phone,
    this.website,
  });

  final String id;
  final double latitude;
  final double longitude;
  final PoiCategory category;
  final String? name;
  final String? address;
  final String? openingHours;
  final String? phone;
  final String? website;

  String get displayName => name ?? category.label;

  factory PointOfInterest.fromOverpass(
      Map<String, dynamic> element, PoiCategory category,) {
    final Map<String, dynamic> tags =
        element['tags'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String? houseNumber = tags['addr:housenumber'] as String?;
    final String? street = tags['addr:street'] as String?;
    final String? address =
        (houseNumber != null && street != null) ? '$houseNumber $street' : null;

    // Nodes have lat/lon directly; ways/relations use center.
    final dynamic center = element['center'];
    final Map<String, dynamic>? centerMap =
        center is Map ? center.cast<String, dynamic>() : null;

    return PointOfInterest(
      id: '${element['type']}_${element['id']}',
      latitude: (element['lat'] as num?)?.toDouble() ??
          (centerMap?['lat'] as num?)?.toDouble() ?? 0,
      longitude: (element['lon'] as num?)?.toDouble() ??
          (centerMap?['lon'] as num?)?.toDouble() ?? 0,
      category: category,
      name: tags['name'] as String?,
      address: address,
      openingHours: tags['opening_hours'] as String?,
      phone: tags['phone'] as String?,
      website: tags['website'] as String?,
    );
  }
}
