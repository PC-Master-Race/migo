// family_model.dart — Family group and live-location models for Bravo Maps.
//
// PRIVACY RULES (from PRODUCT_BRIEF — immutable):
//   • Location data transmitted ONLY to Supabase.
//   • Visible ONLY to authorized family group members (enforced by RLS).
//   • Sharing is strictly opt-in per user — default OFF.
//   • No external service ever receives family member locations.
//   • A user's location is never stored longer than 10 minutes server-side
//     (expires_at column; a Supabase Edge Function or pg_cron prunes stale rows).

// ---------------------------------------------------------------------------
// FamilyGroup
// ---------------------------------------------------------------------------

/// A family group. One group can have up to 10 members.
class FamilyGroup {
  const FamilyGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;

  /// Display name chosen by the group creator (e.g. "The Garcias").
  final String name;

  /// 6-character alphanumeric code shared out-of-band to invite members.
  /// Codes are never sent as push notifications or stored in logs.
  final String inviteCode;

  final String createdBy;
  final DateTime createdAt;

  factory FamilyGroup.fromJson(Map<String, dynamic> json) => FamilyGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// FamilyMember
// ---------------------------------------------------------------------------

/// A member of a family group, as seen by other members.
class FamilyMember {
  const FamilyMember({
    required this.userId,
    required this.displayName,
    required this.groupId,
    required this.joinedAt,
    this.isSharingLocation = false,
    this.archetype,
  });

  final String userId;
  final String displayName;
  final String groupId;
  final DateTime joinedAt;

  /// True if this member currently has location_sharing_enabled = true.
  final bool isSharingLocation;

  /// Their current archetype (shown as their avatar on the family map).
  final String? archetype;

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
        groupId: json['group_id'] as String,
        joinedAt: DateTime.parse(json['joined_at'] as String),
        isSharingLocation: json['is_sharing_location'] as bool? ?? false,
        archetype: json['archetype'] as String?,
      );
}

// ---------------------------------------------------------------------------
// FamilyLocation
// ---------------------------------------------------------------------------

/// A single location ping from one family member.
/// Rows expire after 10 minutes — nothing is stored long-term.
class FamilyLocation {
  const FamilyLocation({
    required this.userId,
    required this.groupId,
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String userId;
  final String groupId;
  final double latitude;
  final double longitude;

  /// Speed in m/s from GPS — used to show "moving / parked" state.
  final double speedMps;

  final DateTime updatedAt;

  /// Server-side expiry. Supabase prunes rows older than this.
  final DateTime expiresAt;

  factory FamilyLocation.fromJson(Map<String, dynamic> json) => FamilyLocation(
        userId: json['user_id'] as String,
        groupId: json['group_id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        speedMps: (json['speed_mps'] as num? ?? 0).toDouble(),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'group_id': groupId,
        'latitude': latitude,
        'longitude': longitude,
        'speed_mps': speedMps,
        'updated_at': updatedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
