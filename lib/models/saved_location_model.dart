// saved_location_model.dart — A user-saved place (Home, Work, or Favorite).
// Persisted to Hive as a JSON string so no TypeAdapter codegen is needed.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// --- ENUM ---

enum SavedLocationType { home, work, favorite }

extension SavedLocationTypeX on SavedLocationType {
  IconData get icon => switch (this) {
        SavedLocationType.home => Icons.home_rounded,
        SavedLocationType.work => Icons.work_rounded,
        SavedLocationType.favorite => Icons.star_rounded,
      };

  Color get color => switch (this) {
        SavedLocationType.home => const Color(0xFF4ECDC4),   // migoTeal
        SavedLocationType.work => const Color(0xFFFFB347),   // migoAmber
        SavedLocationType.favorite => const Color(0xFFFF6B6B), // migoCoral
      };

  String get defaultLabel => switch (this) {
        SavedLocationType.home => 'Home',
        SavedLocationType.work => 'Work',
        SavedLocationType.favorite => 'Favorite',
      };
}

// --- MODEL ---

class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.type,
    required this.label,
    required this.position,
    required this.address,
  });

  final String id;
  final SavedLocationType type;
  final String label;
  final LatLng position;
  final String address;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.index,
        'label': label,
        'lat': position.latitude,
        'lon': position.longitude,
        'address': address,
      };

  factory SavedLocation.fromJson(Map<String, dynamic> j) => SavedLocation(
        id: j['id'] as String,
        type: SavedLocationType.values[j['type'] as int],
        label: j['label'] as String,
        position: LatLng(j['lat'] as double, j['lon'] as double),
        address: j['address'] as String,
      );
}
