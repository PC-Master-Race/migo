// bravo_model.dart — Bravos currency and achievement/cosmetic models.
//
// PRIVACY NOTE: POI visits are checked entirely on-device using GPS bounding
// boxes against local Nominatim data. No visit history is ever sent to any
// external service. The only thing Supabase receives is the achievement name
// after it's already been earned — never the raw location trail.
//
// ECONOMY NOTE: Bravos are merit-only during the initial growth phase.
// No purchase path exists yet. The schema is designed so a purchase path
// can be added later without breaking anything, but it will never be
// required — all content stays earnable for free.

// ---------------------------------------------------------------------------
// Achievement definitions
// ---------------------------------------------------------------------------

/// Every earnable achievement.
/// IDs must be stable — they're stored as strings in Supabase.
enum AchievementId {
  // ── Driving behavior ──────────────────────────────────────────────────────
  /// Completed first navigation session.
  firstDrive,

  /// Drove at or below the speed limit for an entire session.
  speedLawAbider,

  /// 7-day driving streak.
  weekStreak,

  /// 30-day driving streak.
  monthStreak,

  /// Completed 10 long trips (>30 miles).
  roadTripper,

  /// Zero hard brakes in a session.
  silkBrakes,

  /// Arrived within 1 minute of ETA, 5 times.
  clockwork,

  // ── Community contributions ───────────────────────────────────────────────
  /// Reported first hazard.
  firstReport,

  /// 10 confirmed hazard reports.
  hazardHunter,

  /// 50 confirmed hazard reports.
  guardianAngel,

  /// Added first ALPR camera location.
  eyeSpotter,

  // ── POI visits — food ─────────────────────────────────────────────────────
  /// Visited a pho restaurant 5+ times.
  phoLover,

  /// Visited a coffee shop 20+ times.
  coffeeAddict,

  /// Visited a taco spot 10+ times.
  tacoTuesdayEveryDay,

  /// Visited a ramen shop 5+ times.
  ramenHead,

  /// Visited a burger joint 10+ times.
  burgerConnoisseur,

  // ── POI visits — lifestyle ────────────────────────────────────────────────
  /// Visited a beauty supply / salon 5+ times.
  glamourQueen,

  /// Visited a music venue / concert hall 5+ times.
  concertGoer,

  /// Visited a cinema 5+ times.
  movieBuff,

  /// Visited a gym / fitness center 10+ times.
  gymRat,

  /// Visited a bookstore 5+ times.
  bookworm,

  /// Visited a record store 3+ times.
  vinylHead,

  // ── Secret / rare ─────────────────────────────────────────────────────────
  /// Drove on every day of a calendar month.
  creatureOfHabit,

  /// Drove after midnight 10 times.
  nightShift,

  /// Drove in rain (detected via weather conditions at location — Phase 6).
  rainDriver,
}

/// How many Bravos each achievement awards.
const Map<AchievementId, int> kAchievementBravos = <AchievementId, int>{
  AchievementId.firstDrive: 50,
  AchievementId.speedLawAbider: 30,
  AchievementId.weekStreak: 75,
  AchievementId.monthStreak: 250,
  AchievementId.roadTripper: 100,
  AchievementId.silkBrakes: 40,
  AchievementId.clockwork: 60,
  AchievementId.firstReport: 25,
  AchievementId.hazardHunter: 100,
  AchievementId.guardianAngel: 300,
  AchievementId.eyeSpotter: 50,
  AchievementId.phoLover: 80,
  AchievementId.coffeeAddict: 60,
  AchievementId.tacoTuesdayEveryDay: 70,
  AchievementId.ramenHead: 80,
  AchievementId.burgerConnoisseur: 60,
  AchievementId.glamourQueen: 80,
  AchievementId.concertGoer: 100,
  AchievementId.movieBuff: 80,
  AchievementId.gymRat: 70,
  AchievementId.bookworm: 80,
  AchievementId.vinylHead: 120,
  AchievementId.creatureOfHabit: 200,
  AchievementId.nightShift: 90,
  AchievementId.rainDriver: 150,
};

// ---------------------------------------------------------------------------
// Cosmetic items (accessories, car skins, etc.)
// ---------------------------------------------------------------------------

/// Every unlockable cosmetic.
enum CosmeticId {
  // ── POI-earned accessories ────────────────────────────────────────────────
  phoBowl,         // phoLover achievement
  coffeeCup,       // coffeeAddict achievement
  tacoHat,         // tacoTuesdayEveryDay achievement
  ramenBowl,       // ramenHead achievement
  burgerBun,       // burgerConnoisseur achievement
  lipstickCrown,   // glamourQueen achievement
  musicNote,       // concertGoer achievement
  popcornBucket,   // movieBuff achievement
  dumbbellPin,     // gymRat achievement
  tinyBook,        // bookworm achievement
  vinylDisc,       // vinylHead achievement

  // ── Milestone earned ──────────────────────────────────────────────────────
  streakFlamePin,  // weekStreak
  goldClock,       // clockwork
  shieldBadge,     // guardianAngel
  founderStar,     // pre-release beta (granted manually)
}

/// Which achievement unlocks each cosmetic (null = granted manually).
const Map<CosmeticId, AchievementId?> kCosmeticUnlockSource =
    <CosmeticId, AchievementId?>{
  CosmeticId.phoBowl: AchievementId.phoLover,
  CosmeticId.coffeeCup: AchievementId.coffeeAddict,
  CosmeticId.tacoHat: AchievementId.tacoTuesdayEveryDay,
  CosmeticId.ramenBowl: AchievementId.ramenHead,
  CosmeticId.burgerBun: AchievementId.burgerConnoisseur,
  CosmeticId.lipstickCrown: AchievementId.glamourQueen,
  CosmeticId.musicNote: AchievementId.concertGoer,
  CosmeticId.popcornBucket: AchievementId.movieBuff,
  CosmeticId.dumbbellPin: AchievementId.gymRat,
  CosmeticId.tinyBook: AchievementId.bookworm,
  CosmeticId.vinylDisc: AchievementId.vinylHead,
  CosmeticId.streakFlamePin: AchievementId.weekStreak,
  CosmeticId.goldClock: AchievementId.clockwork,
  CosmeticId.shieldBadge: AchievementId.guardianAngel,
  CosmeticId.founderStar: null, // manual grant
};

// ---------------------------------------------------------------------------
// Record models — mirrors Supabase rows.
// ---------------------------------------------------------------------------

/// A single earned achievement row from Supabase `achievements_earned`.
class EarnedAchievement {
  const EarnedAchievement({
    required this.userId,
    required this.achievementId,
    required this.bravosAwarded,
    required this.earnedAt,
  });

  final String userId;
  final AchievementId achievementId;
  final int bravosAwarded;
  final DateTime earnedAt;

  factory EarnedAchievement.fromJson(Map<String, dynamic> json) =>
      EarnedAchievement(
        userId: json['user_id'] as String,
        achievementId:
            AchievementId.values.byName(json['achievement_id'] as String),
        bravosAwarded: json['bravos_awarded'] as int,
        earnedAt: DateTime.parse(json['earned_at'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'achievement_id': achievementId.name,
        'bravos_awarded': bravosAwarded,
        'earned_at': earnedAt.toIso8601String(),
      };
}

/// A cosmetic the user has unlocked and may choose to display.
class UnlockedCosmetic {
  const UnlockedCosmetic({
    required this.userId,
    required this.cosmeticId,
    required this.unlockedAt,
    this.isEquipped = false,
  });

  final String userId;
  final CosmeticId cosmeticId;
  final DateTime unlockedAt;

  /// Whether the user has chosen to display this cosmetic on their avatar.
  /// Default: false — it's a gift, not an announcement.
  final bool isEquipped;

  factory UnlockedCosmetic.fromJson(Map<String, dynamic> json) =>
      UnlockedCosmetic(
        userId: json['user_id'] as String,
        cosmeticId: CosmeticId.values.byName(json['cosmetic_id'] as String),
        unlockedAt: DateTime.parse(json['unlocked_at'] as String),
        isEquipped: json['is_equipped'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': userId,
        'cosmetic_id': cosmeticId.name,
        'unlocked_at': unlockedAt.toIso8601String(),
        'is_equipped': isEquipped,
      };

  UnlockedCosmetic copyWith({bool? isEquipped}) => UnlockedCosmetic(
        userId: userId,
        cosmeticId: cosmeticId,
        unlockedAt: unlockedAt,
        isEquipped: isEquipped ?? this.isEquipped,
      );
}

/// The user's current Bravos balance + lifetime total.
class BravosBalance {
  const BravosBalance({
    required this.userId,
    required this.balance,
    required this.lifetimeEarned,
    required this.updatedAt,
  });

  final String userId;
  final int balance;
  final int lifetimeEarned;
  final DateTime updatedAt;

  factory BravosBalance.fromJson(Map<String, dynamic> json) => BravosBalance(
        userId: json['user_id'] as String,
        balance: json['balance'] as int,
        lifetimeEarned: json['lifetime_earned'] as int,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
