// vehicle_model.dart — The user's car. Drives avatar color and body shape.
// Mirrors the `vehicles` table. Make/model/year/color are entered during
// onboarding; vehicle class maps to the avatar's base body shape (Phase 4).

// --- VEHICLE CLASS ---

/// Broad vehicle categories that determine the cartoon avatar's body shape.
enum VehicleClass {
  /// Standard car silhouette — the default avatar body.
  sedan,

  /// Taller, boxier avatar body.
  suv,

  /// Pickup-style avatar body.
  truck,

  /// Low, sleek avatar body (pairs naturally with Speed Demon archetype).
  sportsCar,

  /// Van/minivan avatar body.
  van,

  /// Motorcycle avatar body.
  motorcycle,
}

// --- MODEL ---

/// A user's vehicle profile.
class Vehicle {
  /// Creates a vehicle. [colorHex] feeds the avatar's paint color directly.
  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.make,
    required this.model,
    required this.year,
    required this.colorHex,
    required this.vehicleClass,
  });

  /// Row UUID in the `vehicles` table.
  final String id;

  /// The owning user's auth UUID.
  final String ownerId;

  /// Manufacturer, e.g. "Toyota". Free text from onboarding.
  final String make;

  /// Model name, e.g. "Corolla". Free text from onboarding.
  final String model;

  /// Model year, e.g. 2019.
  final int year;

  /// Real car color as a hex string (e.g. "#FF6B5E"). The cartoon avatar is
  /// painted this color so family members recognize the actual car.
  final String colorHex;

  /// Body class — selects the avatar's base shape (see [VehicleClass]).
  final VehicleClass vehicleClass;

  /// Builds a vehicle from a Supabase `vehicles` row.
  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      year: json['year'] as int,
      colorHex: json['color_hex'] as String,
      vehicleClass: VehicleClass.values.byName(json['vehicle_class'] as String),
    );
  }

  /// Serializes this vehicle for a Supabase upsert.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'owner_id': ownerId,
      'make': make,
      'model': model,
      'year': year,
      'color_hex': colorHex,
      'vehicle_class': vehicleClass.name,
    };
  }
}
