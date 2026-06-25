// user_model.dart — The Migo user account and preference snapshot.
// Mirrors the `users` table in supabase/schema.sql. Holds identity and
// preference data only; driving behavior lives in archetype/session models.

// --- MODEL ---

/// A Migo user account with privacy and route preferences.
class BravoUser {
  /// Creates a user. All privacy-sensitive flags default to the most private
  /// option — privacy-first means opt IN to sharing, never opt out.
  const BravoUser({
    required this.id,
    required this.displayName,
    this.locationSharingEnabled = false,
    this.alprAvoidanceEnabled = false,
    this.homeRegionCachedAt,
  });

  /// Supabase auth UUID. Primary key linking all of the user's data.
  final String id;

  /// Name shown to family members. Never shown to strangers — non-family
  /// users only ever see anonymous avatars (PRODUCT_BRIEF privacy rule).
  final String displayName;

  /// Whether the user shares live location with their family group.
  /// Defaults OFF: sharing is strictly opt-in.
  final bool locationSharingEnabled;

  /// Whether routing should avoid known ALPR camera locations.
  /// Defaults OFF per PRODUCT_BRIEF Phase 2 spec.
  final bool alprAvoidanceEnabled;

  /// When the offline tile cache around the user's region was last refreshed.
  /// Null until the first WiFi prefetch completes.
  final DateTime? homeRegionCachedAt;

  /// Builds a user from a Supabase `users` row.
  factory BravoUser.fromJson(Map<String, dynamic> json) {
    return BravoUser(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      locationSharingEnabled: json['location_sharing_enabled'] as bool? ?? false,
      alprAvoidanceEnabled: json['alpr_avoidance_enabled'] as bool? ?? false,
      homeRegionCachedAt: json['home_region_cached_at'] == null
          ? null
          : DateTime.parse(json['home_region_cached_at'] as String),
    );
  }

  /// Serializes this user for a Supabase upsert.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'display_name': displayName,
      'location_sharing_enabled': locationSharingEnabled,
      'alpr_avoidance_enabled': alprAvoidanceEnabled,
      'home_region_cached_at': homeRegionCachedAt?.toIso8601String(),
    };
  }
}
