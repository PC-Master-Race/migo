// archetype_service.dart — Driving habit tracking and archetype calculation.
//
// DESIGN:
//   Each session produces a SessionMetrics snapshot. The engine converts
//   those metrics into per-archetype "session scores" (0.0–1.0 per
//   archetype), then blends them into the stored EMA scores with α=0.25.
//   α=0.25 means one session is ~25% of the new score, so it takes ~4
//   consistent sessions to fully shift archetypes — fast enough to feel
//   reactive, slow enough that one crazy drive doesn't permanently brand you.
//
//   After blending, the archetype with the highest score becomes current.
//   No gradual morph — it's a clean snap. Feels like a personality reveal.
//
// SCORING RULES (per archetype):
//   grandpa     — avgSpeedRatio < 0.85, hardBrakeCount == 0, highwayFraction < 0.1
//   rocket      — avgSpeedRatio > 1.15, hardBrakeCount > 3, hardAccelCount > 3
//   ghost       — nightDrivingFraction > 0.7, alprAvoidanceCount > 0
//   scout       — hazardReportsCount >= 2, backRoadFraction > 0.2
//   phantom     — alprAvoidanceCount >= 3, nightDrivingFraction > 0.4
//   zenMaster   — avgSpeedRatio in [0.9, 1.05], hardBrakeCount == 0, hardAccelCount == 0
//   chaosAgent  — rerouteCount >= 4, stdDevSpeed high proxy (hard brakes + accels > 6 total)
//   nightOwl    — nightDrivingFraction > 0.5 (less strict than ghost)
//   streetRat   — backRoadFraction > 0.5, highwayFraction < 0.05

import 'dart:math' as math;

import '../models/archetype_model.dart';
import 'supabase_service.dart';

// ---------------------------------------------------------------------------
// EMA alpha — blend factor per session.
// ---------------------------------------------------------------------------
const double _kAlpha = 0.25;

class ArchetypeService {
  ArchetypeService._();
  static final ArchetypeService instance = ArchetypeService._();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Loads the stored archetype profile for [userId], or creates a default
  /// one if none exists yet.
  Future<ArchetypeProfile> loadProfile(String userId) async {
    final List<Map<String, dynamic>> rows = await SupabaseService.client
        .from('archetype_profiles')
        .select()
        .eq('user_id', userId)
        .limit(1);

    if (rows.isEmpty) {
      final ArchetypeProfile fresh = ArchetypeProfile(
        userId: userId,
        currentArchetype: DrivingArchetype.zenMaster,
        scores: zeroScores(),
      );
      await _persist(fresh);
      return fresh;
    }
    return ArchetypeProfile.fromJson(rows.first);
  }

  /// Recalculates archetype scores from a completed session and persists the
  /// updated profile. Returns the new profile.
  Future<ArchetypeProfile> recalculateAfterSession(
    SessionMetrics metrics,
    ArchetypeProfile current,
  ) async {
    // 1. Score this session against every archetype.
    final ArchetypeScores sessionScores = _scoreSession(metrics);

    // 2. Blend into the stored EMA scores.
    final ArchetypeScores updated = _blendScores(current.scores, sessionScores);

    // 3. Determine the new dominant archetype (highest score wins).
    final DrivingArchetype dominant = _dominant(updated);

    // 4. Check rare archetype unlocks.
    final RareArchetype? rare = _checkRareUnlocks(
      metrics: metrics,
      profile: current,
      updatedScores: updated,
    );

    // 5. Check badge awards.
    final List<AvatarBadge> badges = _checkBadges(
      profile: current,
      metrics: metrics,
    );

    final ArchetypeProfile newProfile = current.copyWith(
      currentArchetype: dominant,
      scores: updated,
      rareArchetype: rare ?? current.rareArchetype,
      badges: badges,
      sessionCount: current.sessionCount + 1,
      consecutiveDays: _updateStreak(current),
      updatedAt: DateTime.now(),
    );

    await _persist(newProfile);
    return newProfile;
  }

  // -------------------------------------------------------------------------
  // Scoring engine
  // -------------------------------------------------------------------------

  /// Returns a score in [0.0, 1.0] for each archetype based on this session.
  ArchetypeScores _scoreSession(SessionMetrics m) {
    final double totalBrakeAccel =
        (m.hardBrakeCount + m.hardAccelCount).toDouble();

    return <DrivingArchetype, double>{
      DrivingArchetype.grandpa: _clamp(
        _scoreGrandpa(m),
      ),
      DrivingArchetype.rocket: _clamp(
        _scoreRocket(m),
      ),
      DrivingArchetype.ghost: _clamp(
        _scoreGhost(m),
      ),
      DrivingArchetype.scout: _clamp(
        _scoreScout(m),
      ),
      DrivingArchetype.phantom: _clamp(
        _scorePhantom(m),
      ),
      DrivingArchetype.zenMaster: _clamp(
        _scoreZenMaster(m),
      ),
      DrivingArchetype.chaosAgent: _clamp(
        _scoreChaosAgent(m, totalBrakeAccel),
      ),
      DrivingArchetype.nightOwl: _clamp(
        _scoreNightOwl(m),
      ),
      DrivingArchetype.streetRat: _clamp(
        _scoreStreetRat(m),
      ),
    };
  }

  double _scoreGrandpa(SessionMetrics m) {
    double s = 0.0;
    if (m.avgSpeedRatio < 0.85) s += 0.5;
    if (m.hardBrakeCount == 0) s += 0.25;
    if (m.highwayFraction < 0.1) s += 0.25;
    return s;
  }

  double _scoreRocket(SessionMetrics m) {
    double s = 0.0;
    if (m.avgSpeedRatio > 1.15) s += 0.4;
    if (m.avgSpeedRatio > 1.25) s += 0.1; // bonus for really fast
    if (m.hardBrakeCount > 3) s += 0.25;
    if (m.hardAccelCount > 3) s += 0.25;
    return s;
  }

  double _scoreGhost(SessionMetrics m) {
    double s = 0.0;
    if (m.nightDrivingFraction > 0.7) s += 0.5;
    if (m.alprAvoidanceCount > 0) s += 0.3;
    if (m.nightDrivingFraction > 0.9) s += 0.2; // pure night bonus
    return s;
  }

  double _scoreScout(SessionMetrics m) {
    double s = 0.0;
    if (m.hazardReportsCount >= 1) s += 0.3;
    if (m.hazardReportsCount >= 3) s += 0.2; // bonus for active reporter
    if (m.backRoadFraction > 0.2) s += 0.25;
    if (m.rerouteCount >= 2) s += 0.25; // explorers reroute willingly
    return s;
  }

  double _scorePhantom(SessionMetrics m) {
    double s = 0.0;
    if (m.alprAvoidanceCount >= 3) s += 0.5;
    if (m.nightDrivingFraction > 0.4) s += 0.3;
    if (m.highwayFraction < 0.1) s += 0.2; // avoids surveilled highways
    return s;
  }

  double _scoreZenMaster(SessionMetrics m) {
    double s = 0.0;
    final bool smoothSpeed =
        m.avgSpeedRatio >= 0.9 && m.avgSpeedRatio <= 1.05;
    if (smoothSpeed) s += 0.5;
    if (m.hardBrakeCount == 0) s += 0.25;
    if (m.hardAccelCount == 0) s += 0.25;
    return s;
  }

  double _scoreChaosAgent(SessionMetrics m, double totalBrakeAccel) {
    double s = 0.0;
    if (m.rerouteCount >= 4) s += 0.4;
    if (totalBrakeAccel > 6) s += 0.3;
    if (m.avgSpeedRatio > 1.05 && m.hardBrakeCount > 2) s += 0.3;
    return s;
  }

  double _scoreNightOwl(SessionMetrics m) {
    double s = 0.0;
    if (m.nightDrivingFraction > 0.5) s += 0.6;
    if (m.nightDrivingFraction > 0.8) s += 0.4;
    return s;
  }

  double _scoreStreetRat(SessionMetrics m) {
    double s = 0.0;
    if (m.backRoadFraction > 0.5) s += 0.5;
    if (m.highwayFraction < 0.05) s += 0.3;
    if (m.alprAvoidanceCount > 0) s += 0.2; // rats dodge cameras too
    return s;
  }

  // -------------------------------------------------------------------------
  // EMA blend
  // -------------------------------------------------------------------------

  ArchetypeScores _blendScores(
    ArchetypeScores stored,
    ArchetypeScores session,
  ) {
    return <DrivingArchetype, double>{
      for (final DrivingArchetype a in DrivingArchetype.values)
        a: _kAlpha * (session[a] ?? 0.0) + (1.0 - _kAlpha) * (stored[a] ?? 0.0),
    };
  }

  DrivingArchetype _dominant(ArchetypeScores scores) {
    return scores.entries
        .reduce((MapEntry<DrivingArchetype, double> a,
                MapEntry<DrivingArchetype, double> b) =>
            a.value >= b.value ? a : b)
        .key;
  }

  // -------------------------------------------------------------------------
  // Rare archetype unlocks
  // -------------------------------------------------------------------------

  RareArchetype? _checkRareUnlocks({
    required SessionMetrics metrics,
    required ArchetypeProfile profile,
    required ArchetypeScores updatedScores,
  }) {
    // creature: 30 consecutive days
    if (profile.consecutiveDays >= 29) {
      return RareArchetype.creature;
    }
    // guardian: cumulative hazard reports — check via session count proxy
    // (full implementation reads total reports from Supabase in production)
    if (profile.sessionCount >= 25 &&
        metrics.hazardReportsCount >= 2 &&
        (updatedScores[DrivingArchetype.scout] ?? 0.0) > 0.6) {
      return RareArchetype.guardian;
    }
    // silkHands: zero hard brakes for 7 consecutive sessions
    // Tracked in session_count — stubbed here; full check is cumulative.
    if (profile.sessionCount >= 7 &&
        metrics.hardBrakeCount == 0 &&
        (updatedScores[DrivingArchetype.zenMaster] ?? 0.0) > 0.7) {
      return RareArchetype.silkHands;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Badge awards
  // -------------------------------------------------------------------------

  List<AvatarBadge> _checkBadges({
    required ArchetypeProfile profile,
    required SessionMetrics metrics,
  }) {
    final Set<AvatarBadge> badges = Set<AvatarBadge>.from(profile.badges);

    // Streak flame: 7+ consecutive days
    if (profile.consecutiveDays >= 7) {
      badges.add(AvatarBadge.streakFlame);
    } else {
      badges.remove(AvatarBadge.streakFlame);
    }

    return badges.toList();
  }

  // -------------------------------------------------------------------------
  // Streak helper
  // -------------------------------------------------------------------------

  int _updateStreak(ArchetypeProfile profile) {
    if (profile.updatedAt == null) return 1;
    final DateTime lastDate = profile.updatedAt!.toLocal();
    final DateTime today = DateTime.now().toLocal();
    final int daysDiff = today
        .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
        .inDays;
    if (daysDiff == 0) return profile.consecutiveDays; // same day, no change
    if (daysDiff == 1) return profile.consecutiveDays + 1; // perfect streak
    return 1; // streak broken
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> _persist(ArchetypeProfile profile) async {
    // Offline / dev mode (placeholder Supabase credentials): skip the write so
    // recalculateAfterSession still succeeds and the in-memory avatar updates.
    // The profile simply isn't saved between launches until a backend exists.
    if (!SupabaseService.isConnected) return;
    await SupabaseService.client
        .from('archetype_profiles')
        .upsert(profile.toJson());
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  double _clamp(double v) => math.max(0.0, math.min(1.0, v));
}
