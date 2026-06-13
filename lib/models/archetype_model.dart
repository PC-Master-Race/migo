// archetype_model.dart — Driving personality archetypes and badges.
// Mirrors the `archetypes` table. Calculation logic lives in
// archetype_service.dart (Phase 4); this file defines the data shapes.

// --- CORE ARCHETYPES ---

/// Every core driving archetype. Each has a unique cartoon avatar (Phase 4).
/// Archetypes evolve with habits and are never permanently locked.
enum DrivingArchetype {
  /// Consistently slow, smooth, cautious. Old man with cane + beret.
  grandpaDriver,

  /// Aggressive, fast, hard braking. Teen with headphones, beat-up car.
  angstyTeen,

  /// Consistent, average, reliable. Harried person in a sensible sedan.
  responsibleEmployee,

  /// Consistently high speed, time efficient. Racing helmet, flames.
  speedDemon,

  /// Fuel-efficient routes, smooth driving. Green leaf, hybrid car.
  ecoWarrior,

  /// Long drives, highway miles, steady pace. Happy big rig, CB radio.
  trucker,

  /// High ALPR reporter, privacy-conscious routes. Trench coat, fedora.
  secretAgent,

  /// Arrives at ETA or earlier, consistently. Pocket watch, bow tie.
  timeLord,
}

// TODO: [rare/secret archetype enum extension] [deferred to Phase 4 — needs
// the hidden-unlock infrastructure; at least 3 rare archetypes will be stubbed
// there per PRODUCT_BRIEF]

// --- BADGES ---

/// Overlay badges that decorate an avatar without replacing its archetype.
enum AvatarBadge {
  /// Crowdsourced hotness — 100+ community marks (chiliPepperVoteThreshold).
  chiliPepper,

  /// 100+ bad-driver reports. Escalates visually as reports accumulate.
  menace,

  /// Hardcoded to exactly one account (the product owner). Never earnable.
  creator,
}

// --- MODEL ---

/// A user's current archetype state, recalculated after each driving session.
class ArchetypeProfile {
  /// Creates an archetype profile snapshot.
  const ArchetypeProfile({
    required this.userId,
    required this.currentArchetype,
    required this.scores,
    this.badges = const <AvatarBadge>[],
    this.updatedAt,
  });

  /// The user this profile belongs to.
  final String userId;

  /// The archetype currently displayed on the user's avatar.
  final DrivingArchetype currentArchetype;

  /// Per-archetype affinity scores (0.0–1.0). The highest score wins the
  /// avatar; keeping all scores lets archetypes evolve smoothly over time.
  final Map<DrivingArchetype, double> scores;

  /// Earned overlay badges.
  final List<AvatarBadge> badges;

  /// When the profile was last recalculated.
  final DateTime? updatedAt;

  /// Builds a profile from a Supabase `archetypes` row.
  factory ArchetypeProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawScores =
        json['scores'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ArchetypeProfile(
      userId: json['user_id'] as String,
      currentArchetype:
          DrivingArchetype.values.byName(json['current_archetype'] as String),
      scores: rawScores.map(
        (String key, dynamic value) => MapEntry(
          DrivingArchetype.values.byName(key),
          (value as num).toDouble(),
        ),
      ),
      badges: (json['badges'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic name) => AvatarBadge.values.byName(name as String))
          .toList(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );
  }
}
