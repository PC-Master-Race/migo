// archetype_model.dart — Driving personality archetypes for Bravo Maps.
//
// Archetypes are derived from real driving behavior at the end of each
// session. The avatar SNAPS to whichever archetype the current scores point
// to — no gradual morph. Scores do accumulate over time (exponential moving
// average) so one wild session won't permanently brand you as The Rocket.
//
// Nine core archetypes, all drawn in chibi style — big round head, tiny body,
// 2-3 signature accessories. Designed to appeal to any gender.

/// Every core driving archetype.
enum DrivingArchetype {
  /// Putters well under the limit, brakes early, avoids highways.
  /// Accessories: reading glasses, little cardigan, slow sedan.
  grandpa,

  /// Consistently over the limit, hard late-braking, aggressive lines.
  /// Accessories: racing goggles, wild hair, spoiler.
  rocket,

  /// Drives almost exclusively at night, avoids all cameras.
  /// Accessories: sheet-ghost body, hollow eyes, dark car.
  ghost,

  /// Reports hazards constantly, tries new routes every session.
  /// Accessories: explorer hat, binoculars, backpack.
  scout,

  /// Routes around every toll and ALPR camera religiously.
  /// Accessories: trenchcoat, fedora, suspicious squint.
  phantom,

  /// Perfectly smooth, never over the limit, zero hard brakes.
  /// Accessories: closed eyes, serene smile, zen aura.
  zenMaster,

  /// Unpredictable speed, lots of rerouting, erratic acceleration.
  /// Accessories: three coffees, wild hair, bags under eyes.
  chaosAgent,

  /// Almost exclusively drives after 10 pm, sleepy face.
  /// Accessories: half-closed eyes, moon on car, tiny pillow.
  nightOwl,

  /// Only back roads and shortcuts, never a main road or highway.
  /// Accessories: hoodie, sneaky grin, tiny rat ears.
  streetRat,
}

/// Rare / secret archetypes unlocked by specific hidden achievements.
/// Not shown in any picker — discovered organically.
enum RareArchetype {
  /// Driven every single day for 30 days straight.
  creature,

  /// Reported 50+ confirmed hazards total.
  guardian,

  /// Zero hard brakes across 7 consecutive sessions.
  silkHands,
}

/// Overlay badges that decorate the avatar without replacing the archetype.
enum AvatarBadge {
  /// App creator. Hardcoded to the product-owner account — never earnable.
  creator,

  /// Pre-release beta tester (founder's edition).
  founder,

  /// Currently on a 7-day consecutive driving streak.
  streakFlame,
}

// ---------------------------------------------------------------------------
// Session metrics — raw inputs the archetype engine reads each session.
// ---------------------------------------------------------------------------

/// Driving metrics collected during a single navigation session.
class SessionMetrics {
  const SessionMetrics({
    required this.sessionId,
    required this.userId,
    required this.startedAt,
    required this.endedAt,
    required this.avgSpeedRatio,
    required this.hardBrakeCount,
    required this.hardAccelCount,
    required this.nightDrivingFraction,
    required this.highwayFraction,
    required this.backRoadFraction,
    required this.hazardReportsCount,
    required this.alprAvoidanceCount,
    required this.rerouteCount,
    required this.onTimeArrival,
  });

  final String sessionId;
  final String userId;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Average speed / posted speed limit. 1.0 = exactly at limit.
  /// Values >1.15 signal consistent speeding → rocket score rises.
  final double avgSpeedRatio;

  /// GPS-derived sudden decelerations (>0.4g-equivalent drop in speed/sec).
  final int hardBrakeCount;

  /// GPS-derived sudden accelerations (>0.35g-equivalent).
  final int hardAccelCount;

  /// Fraction of drive time between 10 pm and 5 am → ghost / nightOwl.
  final double nightDrivingFraction;

  /// Fraction of distance on roads tagged highway/motorway.
  final double highwayFraction;

  /// Fraction of distance on residential/unclassified/track roads → streetRat.
  final double backRoadFraction;

  /// Hazard reports submitted this session → scout score.
  final int hazardReportsCount;

  /// ALPR cameras the route actively avoided → phantom score.
  final int alprAvoidanceCount;

  /// Mid-session reroutes → chaosAgent score.
  final int rerouteCount;

  /// Arrived within 2 minutes of original ETA.
  final bool onTimeArrival;

  Duration get duration => endedAt.difference(startedAt);
}

// ---------------------------------------------------------------------------
// Archetype scores.
// ---------------------------------------------------------------------------

/// Per-archetype affinity map. Highest score wins the current avatar.
typedef ArchetypeScores = Map<DrivingArchetype, double>;

/// Zero-initialised scores for a brand-new user.
ArchetypeScores zeroScores() => {
      for (final DrivingArchetype a in DrivingArchetype.values) a: 0.0,
    };

// ---------------------------------------------------------------------------
// ArchetypeProfile — persisted in Supabase `archetype_profiles`.
// ---------------------------------------------------------------------------

/// A user's current archetype state, recalculated after each driving session.
class ArchetypeProfile {
  const ArchetypeProfile({
    required this.userId,
    required this.currentArchetype,
    required this.scores,
    this.rareArchetype,
    this.badges = const <AvatarBadge>[],
    this.sessionCount = 0,
    this.consecutiveDays = 0,
    this.updatedAt,
  });

  final String userId;

  /// The archetype currently displayed — the highest-scoring one.
  final DrivingArchetype currentArchetype;

  /// Per-archetype EMA scores (0.0–1.0).
  final ArchetypeScores scores;

  /// If a rare archetype is unlocked, it can override the display.
  final RareArchetype? rareArchetype;

  /// Earned overlay badges.
  final List<AvatarBadge> badges;

  /// Total sessions completed (used for rare-unlock checks).
  final int sessionCount;

  /// Consecutive calendar days with at least one session (streak tracking).
  final int consecutiveDays;

  final DateTime? updatedAt;

  factory ArchetypeProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawScores =
        json['scores'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ArchetypeProfile(
      userId: json['user_id'] as String,
      currentArchetype: DrivingArchetype.values.byName(
        json['current_archetype'] as String? ?? 'zenMaster',
      ),
      scores: rawScores.isEmpty
          ? zeroScores()
          : rawScores.map(
              (String key, dynamic value) => MapEntry(
                DrivingArchetype.values.byName(key),
                (value as num).toDouble(),
              ),
            ),
      rareArchetype: json['rare_archetype'] == null
          ? null
          : RareArchetype.values.byName(json['rare_archetype'] as String),
      badges: (json['badges'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic name) => AvatarBadge.values.byName(name as String))
          .toList(),
      sessionCount: json['session_count'] as int? ?? 0,
      consecutiveDays: json['consecutive_days'] as int? ?? 0,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'current_archetype': currentArchetype.name,
        'scores': scores.map((DrivingArchetype k, double v) =>
            MapEntry(k.name, v)),
        if (rareArchetype != null) 'rare_archetype': rareArchetype!.name,
        'badges': badges.map((AvatarBadge b) => b.name).toList(),
        'session_count': sessionCount,
        'consecutive_days': consecutiveDays,
      };

  ArchetypeProfile copyWith({
    DrivingArchetype? currentArchetype,
    ArchetypeScores? scores,
    RareArchetype? rareArchetype,
    List<AvatarBadge>? badges,
    int? sessionCount,
    int? consecutiveDays,
    DateTime? updatedAt,
  }) =>
      ArchetypeProfile(
        userId: userId,
        currentArchetype: currentArchetype ?? this.currentArchetype,
        scores: scores ?? this.scores,
        rareArchetype: rareArchetype ?? this.rareArchetype,
        badges: badges ?? this.badges,
        sessionCount: sessionCount ?? this.sessionCount,
        consecutiveDays: consecutiveDays ?? this.consecutiveDays,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
