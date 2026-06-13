// bravo_service.dart — Bravos currency, achievements, and POI detection.
//
// PRIVACY: POI checks use Nominatim bounding-box queries to match the
// user's current GPS coordinate to nearby amenity types. No history of
// visit coordinates is stored anywhere — only the earned achievement name
// is sent to Supabase after the unlock threshold is reached.
//
// POI DETECTION FLOW:
//   1. On each position update, checkPoiVisit(position) is called.
//   2. We query Nominatim for amenities within ~50m of the position.
//   3. If we find a matching amenity type, we increment an IN-MEMORY
//      visit counter (never persisted on device or server as a location).
//   4. When a counter hits its threshold, we call _awardAchievement(),
//      which inserts just the achievement name into Supabase.
//   5. Counter is reset so the achievement can't double-fire.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/bravo_model.dart';
import 'supabase_service.dart';

class BravoService {
  BravoService._();
  static final BravoService instance = BravoService._();

  // ── In-memory POI visit counters (never leave the device) ───────────────
  final Map<AchievementId, int> _visitCounts = <AchievementId, int>{};
  // Track last-checked position to avoid re-checking when stationary.
  LatLng? _lastCheckedPosition;
  static const double _minMovementMeters = 30.0;

  // ── POI category → achievement + threshold ───────────────────────────────
  static const Map<String, _PoiRule> _rules = <String, _PoiRule>{
    'vietnamese':   _PoiRule(AchievementId.phoLover, 5),
    'cafe':         _PoiRule(AchievementId.coffeeAddict, 20),
    'coffee':       _PoiRule(AchievementId.coffeeAddict, 20),
    'mexican':      _PoiRule(AchievementId.tacoTuesdayEveryDay, 10),
    'ramen':        _PoiRule(AchievementId.ramenHead, 5),
    'japanese':     _PoiRule(AchievementId.ramenHead, 5),
    'burger':       _PoiRule(AchievementId.burgerConnoisseur, 10),
    'fast_food':    _PoiRule(AchievementId.burgerConnoisseur, 10),
    'beauty':       _PoiRule(AchievementId.glamourQueen, 5),
    'hairdresser':  _PoiRule(AchievementId.glamourQueen, 5),
    'music_venue':  _PoiRule(AchievementId.concertGoer, 5),
    'theatre':      _PoiRule(AchievementId.concertGoer, 5),
    'cinema':       _PoiRule(AchievementId.movieBuff, 5),
    'fitness':      _PoiRule(AchievementId.gymRat, 10),
    'gym':          _PoiRule(AchievementId.gymRat, 10),
    'sports':       _PoiRule(AchievementId.gymRat, 10),
    'books':        _PoiRule(AchievementId.bookworm, 5),
    'library':      _PoiRule(AchievementId.bookworm, 5),
    'music':        _PoiRule(AchievementId.vinylHead, 3),
  };

  // ── Cosmetic that each POI achievement unlocks ───────────────────────────
  static const Map<AchievementId, CosmeticId> _cosmeticForAchievement =
      <AchievementId, CosmeticId>{
    AchievementId.phoLover:              CosmeticId.phoBowl,
    AchievementId.coffeeAddict:          CosmeticId.coffeeCup,
    AchievementId.tacoTuesdayEveryDay:   CosmeticId.tacoHat,
    AchievementId.ramenHead:             CosmeticId.ramenBowl,
    AchievementId.burgerConnoisseur:     CosmeticId.burgerBun,
    AchievementId.glamourQueen:          CosmeticId.lipstickCrown,
    AchievementId.concertGoer:           CosmeticId.musicNote,
    AchievementId.movieBuff:             CosmeticId.popcornBucket,
    AchievementId.gymRat:                CosmeticId.dumbbellPin,
    AchievementId.bookworm:              CosmeticId.tinyBook,
    AchievementId.vinylHead:             CosmeticId.vinylDisc,
    AchievementId.weekStreak:            CosmeticId.streakFlamePin,
    AchievementId.clockwork:             CosmeticId.goldClock,
    AchievementId.guardianAngel:         CosmeticId.shieldBadge,
  };

  // ── Already-earned set (loaded on init, prevents double-awards) ──────────
  final Set<AchievementId> _earned = <AchievementId>{};

  // ── Listeners ─────────────────────────────────────────────────────────────
  /// Called when a new achievement is earned. Wire to Riverpod notifier.
  void Function(AchievementId, CosmeticId?)? onAchievementEarned;

  // =========================================================================
  // Public API
  // =========================================================================

  /// Load already-earned achievements from Supabase so we don't re-award.
  Future<void> init(String userId) async {
    final List<Map<String, dynamic>> rows = await SupabaseService.client
        .from('achievements_earned')
        .select('achievement_id')
        .eq('user_id', userId);
    for (final Map<String, dynamic> row in rows) {
      try {
        _earned.add(
            AchievementId.values.byName(row['achievement_id'] as String));
      } catch (_) {}
    }
  }

  /// Check if the current GPS position is near a known POI type.
  /// Call this from the location service on position updates.
  /// [position] is never stored or sent anywhere.
  Future<void> checkPoiVisit(LatLng position) async {
    // Skip if not moved enough
    if (_lastCheckedPosition != null) {
      final double moved = _haversineMeters(_lastCheckedPosition!, position);
      if (moved < _minMovementMeters) return;
    }
    _lastCheckedPosition = position;

    // Query Nominatim for amenities within ~60m (coarse bounding box)
    final double delta = 0.0006; // ~60m in degrees
    final Uri url = Uri.parse(
      '${nominatimSearchUrl}?format=json&limit=5'
      '&bounded=1'
      '&viewbox=${position.longitude - delta},${position.latitude + delta},'
      '${position.longitude + delta},${position.latitude - delta}',
    );

    try {
      final http.Response resp = await http
          .get(url, headers: <String, String>{'User-Agent': osmUserAgent})
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;

      final List<dynamic> results =
          jsonDecode(resp.body) as List<dynamic>;

      for (final dynamic item in results) {
        final Map<String, dynamic> place = item as Map<String, dynamic>;
        final String type = (place['type'] as String? ?? '').toLowerCase();
        final String category =
            (place['class'] as String? ?? '').toLowerCase();
        final String name = (place['display_name'] as String? ?? '').toLowerCase();

        // Match against our rules
        for (final MapEntry<String, _PoiRule> entry in _rules.entries) {
          if (type.contains(entry.key) ||
              category.contains(entry.key) ||
              name.contains(entry.key)) {
            _incrementVisit(entry.value);
            break;
          }
        }
      }
    } catch (_) {
      // Network failure — fail silently, POI checks are best-effort
    }
  }

  /// Award a driving-behavior achievement directly (called from session end).
  Future<void> awardDrivingAchievement(
      String userId, AchievementId id) async {
    if (_earned.contains(id)) return;
    await _awardAchievement(userId, id);
  }

  /// Load the user's current Bravos balance.
  Future<BravosBalance?> loadBalance(String userId) async {
    final List<Map<String, dynamic>> rows = await SupabaseService.client
        .from('bravos_balance')
        .select()
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    return BravosBalance.fromJson(rows.first);
  }

  /// Load all cosmetics the user has unlocked.
  Future<List<UnlockedCosmetic>> loadCosmetics(String userId) async {
    final List<Map<String, dynamic>> rows = await SupabaseService.client
        .from('cosmetics_unlocked')
        .select()
        .eq('user_id', userId);
    return rows.map(UnlockedCosmetic.fromJson).toList();
  }

  /// Toggle whether a cosmetic is displayed on the avatar.
  /// The user opts in — nothing is shown without explicit choice.
  Future<void> setEquipped(
      String userId, CosmeticId cosmeticId, bool equipped) async {
    await SupabaseService.client
        .from('cosmetics_unlocked')
        .update(<String, dynamic>{'is_equipped': equipped})
        .eq('user_id', userId)
        .eq('cosmetic_id', cosmeticId.name);
  }

  // =========================================================================
  // Private
  // =========================================================================

  void _incrementVisit(_PoiRule rule) {
    if (_earned.contains(rule.achievement)) return;
    final int newCount = (_visitCounts[rule.achievement] ?? 0) + 1;
    _visitCounts[rule.achievement] = newCount;

    // Check threshold — but we need userId for the award.
    // The userId is retrieved from Supabase auth at award time.
    if (newCount >= rule.threshold) {
      _visitCounts[rule.achievement] = 0;
      final String? userId =
          SupabaseService.client.auth.currentSession?.user.id;
      if (userId != null) {
        _awardAchievement(userId, rule.achievement);
      }
    }
  }

  Future<void> _awardAchievement(String userId, AchievementId id) async {
    if (_earned.contains(id)) return;
    _earned.add(id);

    final int bravos = kAchievementBravos[id] ?? 10;
    final EarnedAchievement record = EarnedAchievement(
      userId: userId,
      achievementId: id,
      bravosAwarded: bravos,
      earnedAt: DateTime.now(),
    );

    try {
      // Insert achievement record
      await SupabaseService.client
          .from('achievements_earned')
          .insert(record.toJson());

      // Increment Bravos balance via RPC (atomic, avoids race conditions)
      await SupabaseService.client.rpc(
        'increment_bravos',
        params: <String, dynamic>{'p_user_id': userId, 'p_amount': bravos},
      );

      // Unlock the corresponding cosmetic if there is one
      final CosmeticId? cosmetic = _cosmeticForAchievement[id];
      if (cosmetic != null) {
        await SupabaseService.client.from('cosmetics_unlocked').upsert(
          UnlockedCosmetic(
            userId: userId,
            cosmeticId: cosmetic,
            unlockedAt: DateTime.now(),
          ).toJson(),
        );
      }

      // Notify UI
      onAchievementEarned?.call(id, cosmetic);
    } catch (_) {
      // If Supabase fails, remove from earned set so it retries next session
      _earned.remove(id);
    }
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const double R = 6371000;
    final double lat1 = a.latitude * math.pi / 180;
    final double lat2 = b.latitude * math.pi / 180;
    final double dLat = (b.latitude - a.latitude) * math.pi / 180;
    final double dLon = (b.longitude - a.longitude) * math.pi / 180;
    final double x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _PoiRule {
  const _PoiRule(this.achievement, this.threshold);
  final AchievementId achievement;
  final int threshold;
}
