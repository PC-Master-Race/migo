// hazard_model.dart — A user-reported map hazard (crash, ALPR, debris, etc.).
// Mirrors the `hazards` table. Voting/confirmation logic lives in
// hazard_service.dart (Phase 3); this file is the pure data shape.

import 'package:latlong2/latlong.dart';

// --- HAZARD TYPES ---

/// Every hazard category Migo supports. Each maps to a cartoon icon asset and
/// a distinct alert sound (Phase 3). Order is stable — stored by name, not
/// index, so reordering here never corrupts database rows.
enum HazardType {
  /// Crashed car — urgent alert tone.
  crash,

  /// ALPR camera — ominous/subtle alert tone, plum-colored UI.
  alprCamera,

  /// Debris or trash on the road.
  debris,

  /// Ice or other road-surface hazard.
  ice,

  /// Construction zone.
  construction,

  /// Speed trap (cartoon cop with clipboard) — distinct alert tone.
  speedTrap,

  /// Anything else worth a heads-up.
  generalDisturbance,
}

// --- MODEL ---

/// A single reported hazard pin on the map.
class Hazard {
  /// Creates a hazard report.
  const Hazard({
    required this.id,
    required this.type,
    required this.position,
    required this.reportedAt,
    this.confirmedVotes = 0,
    this.dismissedVotes = 0,
    this.isCommunityConfirmed = false,
  });

  /// Row UUID in the `hazards` table.
  final String id;

  /// What kind of hazard this is — selects icon and alert sound.
  final HazardType type;

  /// Where the hazard is on the map.
  final LatLng position;

  /// When it was first reported. Drives the expiry re-check prompt (Phase 3).
  final DateTime reportedAt;

  /// "Still there" votes from the community.
  final int confirmedVotes;

  /// "Gone now" votes from the community.
  final int dismissedVotes;

  /// True once enough votes confirm it — only then is it shown to all users
  /// (PRODUCT_BRIEF: hazards require community confirmation).
  final bool isCommunityConfirmed;

  /// Builds a hazard from a Supabase `hazards` row.
  factory Hazard.fromJson(Map<String, dynamic> json) {
    return Hazard(
      id: json['id'] as String,
      type: HazardType.values.byName(json['hazard_type'] as String),
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      reportedAt: DateTime.parse(json['reported_at'] as String),
      confirmedVotes: json['confirmed_votes'] as int? ?? 0,
      dismissedVotes: json['dismissed_votes'] as int? ?? 0,
      isCommunityConfirmed: json['is_community_confirmed'] as bool? ?? false,
    );
  }

  /// Serializes this hazard for a Supabase insert.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'hazard_type': type.name,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'reported_at': reportedAt.toIso8601String(),
    };
  }
}
