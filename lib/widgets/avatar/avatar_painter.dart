// avatar_painter.dart — Chibi avatar CustomPainter for Bravo Maps.
//
// Each user's map marker is a tiny car with a big round chibi head poking
// out through the sunroof — think Waze driver meets turntable.fm bot.
//
// LAYER ORDER (bottom → top):
//   1. Car body       — colored rectangle with rounded corners + wheels
//   2. Car details    — windows, headlights, grill
//   3. Head           — large circle, skin tone
//   4. Eyes           — expressive pair, archetype-specific shape
//   5. Mouth          — small, archetype-specific expression
//   6. Accessory A    — primary archetype item (hat, glasses, etc.)
//   7. Accessory B    — secondary item (optional)
//   8. Earned overlay — POI/achievement cosmetic (pho bowl, popcorn, etc.)
//
// The painter is designed for a 64×80 logical-pixel canvas (portrait).
// The car occupies the bottom ~40 px; the head the top ~48 px.
// Scale up with a Transform or SizedBox for the profile screen.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/archetype_model.dart';
import '../../models/bravo_model.dart';
import '../../theme/bravo_theme.dart';

// ---------------------------------------------------------------------------
// Archetype visual config
// ---------------------------------------------------------------------------

class _ArchetypeConfig {
  const _ArchetypeConfig({
    required this.carColor,
    required this.headColor,
    required this.eyeStyle,
    required this.mouthStyle,
    required this.accessoryA,
    required this.accessoryB,
    this.auraColor,
    this.vehicle = _VehicleType.car,
  });

  final Color carColor;
  final Color headColor;
  final _EyeStyle eyeStyle;
  final _MouthStyle mouthStyle;
  final _AccessoryType accessoryA;
  final _AccessoryType accessoryB;
  final Color? auraColor;

  /// What the chibi rides. Default is the classic car; signature archetypes
  /// get signature rides (Zen floats on a cloud, Rocket rides a rocket, ...).
  final _VehicleType vehicle;
}

/// Per-archetype rides. Same canvas slot as the car (head pokes out the top)
/// so every vehicle drops into the existing layout without layout changes.
enum _VehicleType {
  car,
  cloud,
  rocketShip,
  ufo,
  spectralFloat,
  vintageSedan,
  crescentMoon,
  shoppingCart,
  skateboard,
  jeep,
}

enum _EyeStyle { normal, sleepy, wide, squint, closed, hollow, happy }
enum _MouthStyle { smile, smirk, grin, frown, neutral, ooo }
enum _AccessoryType {
  none,
  readingGlasses,
  racingGoggles,
  explorerHat,
  fedora,
  nightCap,
  hoodie,
  coffeeX3,
  zenHalo,
  spoiler, // car accessory — drawn on car layer
  crownSmall,
  // Rare-archetype accessories (see _kRareConfigs).
  creatureHorns,
  goldHalo,
  silkSparkle,
}

const Map<DrivingArchetype, _ArchetypeConfig> _kConfigs =
    <DrivingArchetype, _ArchetypeConfig>{
  DrivingArchetype.grandpa: _ArchetypeConfig(
    carColor: Color(0xFF9FB4BE), // gentle powder blue-grey
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.neutral,
    accessoryA: _AccessoryType.readingGlasses,
    accessoryB: _AccessoryType.none,
    vehicle: _VehicleType.vintageSedan, // whitewalls + eternal blinker
  ),
  DrivingArchetype.rocket: _ArchetypeConfig(
    carColor: Color(0xFFE53935), // racing red
    headColor: Color(0xFFFFB74D),
    eyeStyle: _EyeStyle.wide,
    mouthStyle: _MouthStyle.grin,
    accessoryA: _AccessoryType.racingGoggles,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33FF5722),
    vehicle: _VehicleType.rocketShip, // rides an actual rocket — speed IS the brand
  ),
  DrivingArchetype.ghost: _ArchetypeConfig(
    carColor: Color(0xFFD9CDEA), // pale spectral lavender
    headColor: Color(0xFFE1E1E1), // pale/ghostly
    eyeStyle: _EyeStyle.hollow,
    mouthStyle: _MouthStyle.ooo,
    accessoryA: _AccessoryType.none,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x44AB47BC),
    vehicle: _VehicleType.spectralFloat, // no car — ghosts don't need one
  ),
  DrivingArchetype.scout: _ArchetypeConfig(
    carColor: Color(0xFF43A047), // forest green
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.happy,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.explorerHat,
    accessoryB: _AccessoryType.none,
    vehicle: _VehicleType.jeep, // open-top, spare tire, expedition flag
  ),
  DrivingArchetype.phantom: _ArchetypeConfig(
    carColor: Color(0xFF37474F), // gunmetal saucer
    headColor: Color(0xFFBDBDBD),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.smirk,
    accessoryA: _AccessoryType.fedora,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33546E7A),
    // The camera-dodger flies a UFO — you can't read the plates on a saucer.
    vehicle: _VehicleType.ufo,
  ),
  DrivingArchetype.zenMaster: _ArchetypeConfig(
    carColor: Color(0xFFECEFF1), // cloud white with the softest grey
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.closed,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.zenHalo,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x2200BCD4),
    vehicle: _VehicleType.cloud, // floats — perfectly smooth driving, literally
  ),
  DrivingArchetype.chaosAgent: _ArchetypeConfig(
    carColor: Color(0xFFB0BEC5), // chrome cart
    headColor: Color(0xFFFFB74D),
    eyeStyle: _EyeStyle.wide,
    mouthStyle: _MouthStyle.ooo,
    accessoryA: _AccessoryType.coffeeX3,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33FF6F00),
    vehicle: _VehicleType.shoppingCart, // 45 mph of pure entropy
  ),
  DrivingArchetype.nightOwl: _ArchetypeConfig(
    carColor: Color(0xFFFFE082), // moonlight gold
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.sleepy,
    mouthStyle: _MouthStyle.neutral,
    accessoryA: _AccessoryType.nightCap,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x221A237E),
    vehicle: _VehicleType.crescentMoon, // hammocked in the moon, stars out
  ),
  DrivingArchetype.streetRat: _ArchetypeConfig(
    carColor: Color(0xFF8D6E63), // scuffed deck brown
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.smirk,
    accessoryA: _AccessoryType.hoodie,
    accessoryB: _AccessoryType.none,
    vehicle: _VehicleType.skateboard, // back streets, fat wheels
  ),
};

// ---------------------------------------------------------------------------
// Rare archetype visual configs (secret unlocks — see RareArchetype).
// When a profile has a rareArchetype set, it overrides the core look so the
// reward feels special and unmistakable.
// ---------------------------------------------------------------------------

const Map<RareArchetype, _ArchetypeConfig> _kRareConfigs =
    <RareArchetype, _ArchetypeConfig>{
  // Creature of Habit — drove every day for 30 days. A friendly little
  // green monster with horns, fangs (grin) and a green glow.
  RareArchetype.creature: _ArchetypeConfig(
    carColor: Color(0xFF2E7D32), // mossy green
    headColor: Color(0xFF8BC34A), // creature green
    eyeStyle: _EyeStyle.wide,
    mouthStyle: _MouthStyle.grin,
    accessoryA: _AccessoryType.creatureHorns,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x4476FF03), // green aura
  ),
  // Guardian — 50+ confirmed hazard reports. A watchful protector with a
  // rich gold halo and a warm golden aura.
  RareArchetype.guardian: _ArchetypeConfig(
    carColor: Color(0xFF1565C0), // guardian blue
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.happy,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.goldHalo,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x44FFD700), // gold aura
  ),
  // Silk Hands — zero hard brakes for 7 sessions. Effortlessly smooth:
  // a sleek silver car, serene closed eyes, and a scatter of sparkles.
  RareArchetype.silkHands: _ArchetypeConfig(
    carColor: Color(0xFFCFD8DC), // silver
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.closed,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.silkSparkle,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33B0BEC5), // soft silver aura
  ),
};

// ---------------------------------------------------------------------------
// AvatarPainter
// ---------------------------------------------------------------------------

/// Paints a chibi avatar on a 64×80 canvas.
/// [archetype] drives the visual config.
/// [carColorOverride] lets the user's real car color replace the default.
/// [rareArchetype] overrides the look entirely when a rare type is unlocked.
/// [equippedCosmetic] is the unlockable the user chose to display (visible to
/// anyone who sees this avatar — that's the point of the reward system).
class AvatarPainter extends CustomPainter {
  const AvatarPainter({
    required this.archetype,
    this.rareArchetype,
    this.carColorOverride,
    this.equippedCosmetic,
    this.bob = 0.0,
    this.showAura = true,
    this.tux = false,
  });

  /// CREATOR EASTER EGG: Tux the Linux penguin, fedora on, in a go-kart.
  /// Overrides everything else. See [creatorMode] in constants.dart.
  final bool tux;

  final DrivingArchetype archetype;

  /// When set, overrides [archetype] with a special rare look.
  final RareArchetype? rareArchetype;
  final Color? carColorOverride;

  /// The unlockable the user has chosen to display (null = none). Only ever
  /// passed when the user equipped it — unlocking alone never shows it.
  final CosmeticId? equippedCosmetic;

  /// Head-bob phase 0.0–1.0 (one full bounce cycle). Driven by AvatarWidget's
  /// looping controller; 0.0 = no bob (static).
  final double bob;
  final bool showAura;

  @override
  void paint(Canvas canvas, Size size) {
    // Creator easter egg takes over everything: fedora'd Tux in a kart.
    if (tux) {
      _paintTuxKart(canvas, size);
      return;
    }

    // A rare archetype, when unlocked, takes over the whole look.
    final _ArchetypeConfig cfg = rareArchetype != null
        ? (_kRareConfigs[rareArchetype] ??
            _kConfigs[archetype] ??
            _kConfigs[DrivingArchetype.zenMaster]!)
        : (_kConfigs[archetype] ?? _kConfigs[DrivingArchetype.zenMaster]!);

    final double w = size.width;  // 64
    final double h = size.height; // 80

    // Coordinate helpers — everything is proportional so it scales cleanly.
    final double cx = w / 2;

    // ── 1. Aura (soft glow behind car+head) ──────────────────────────────
    if (showAura && cfg.auraColor != null) {
      _drawAura(canvas, cx, h * 0.55, w * 0.52, cfg.auraColor!);
    }

    // ── 2. Vehicle (car / cloud / rocket — the archetype's signature ride) ─
    final Color carColor = carColorOverride ?? cfg.carColor;
    switch (cfg.vehicle) {
      case _VehicleType.car:
        _drawCar(
            canvas, size, carColor, cfg.accessoryB == _AccessoryType.spoiler);
      case _VehicleType.cloud:
        _drawCloud(canvas, size, carColor);
      case _VehicleType.rocketShip:
        _drawRocketShip(canvas, size, carColor);
      case _VehicleType.ufo:
        _drawUfo(canvas, size, carColor);
      case _VehicleType.spectralFloat:
        _drawSpectralFloat(canvas, size, carColor);
      case _VehicleType.vintageSedan:
        _drawVintageSedan(canvas, size, carColor);
      case _VehicleType.crescentMoon:
        _drawCrescentMoon(canvas, size, carColor);
      case _VehicleType.shoppingCart:
        _drawShoppingCart(canvas, size, carColor);
      case _VehicleType.skateboard:
        _drawSkateboard(canvas, size, carColor);
      case _VehicleType.jeep:
        _drawJeep(canvas, size, carColor);
    }

    // ── 3. Head ───────────────────────────────────────────────────────────
    final double headRadius = w * 0.36; // ~23px on 64px canvas
    // Head-bob: a smooth sine bounce (turntable-style). It shifts the head and
    // everything attached to it (eyes, mouth, accessory, cosmetic); the car and
    // aura stay planted, so it reads as the driver bobbing to a beat.
    final double bobOffset = math.sin(bob * 2 * math.pi) * h * 0.045;
    final Offset headCenter = Offset(cx, h * 0.38 + bobOffset);
    _drawHead(canvas, headCenter, headRadius, cfg.headColor);

    // ── 4. Eyes ───────────────────────────────────────────────────────────
    _drawEyes(canvas, headCenter, headRadius, cfg.eyeStyle);

    // ── 5. Mouth ──────────────────────────────────────────────────────────
    _drawMouth(canvas, headCenter, headRadius, cfg.mouthStyle);

    // ── 6. Accessory A ────────────────────────────────────────────────────
    if (cfg.accessoryA != _AccessoryType.none &&
        cfg.accessoryA != _AccessoryType.spoiler) {
      _drawAccessoryA(canvas, headCenter, headRadius, cfg.accessoryA);
    }

    // ── 7. Equipped cosmetic overlay (unlockable badge near the head) ──────
    // Only drawn when the user equipped it — visible to everyone who sees the
    // avatar, which is the whole point of the reward system.
    if (equippedCosmetic != null) {
      _drawCosmetic(canvas, headCenter, headRadius, equippedCosmetic!);
    }
  }

  // ── Aura ─────────────────────────────────────────────────────────────────

  void _drawAura(
      Canvas canvas, double cx, double cy, double radius, Color color) {
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  // ── Car body ──────────────────────────────────────────────────────────────

  void _drawCar(Canvas canvas, Size size, Color color, bool hasSpoiler) {
    final double w = size.width;
    final double h = size.height;
    final double carTop = h * 0.56;
    final double carBottom = h * 0.88;
    final double carLeft = w * 0.08;
    final double carRight = w * 0.92;

    final Paint bodyPaint = Paint()..color = color;
    final Paint shadowPaint = Paint()..color = Colors.black26;
    final Paint windowPaint = Paint()..color = const Color(0xFFB3E5FC);
    final Paint wheelPaint = Paint()..color = const Color(0xFF212121);
    final Paint hubPaint = Paint()..color = const Color(0xFFBDBDBD);

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(carLeft + 2, carTop + 2, carRight + 2, carBottom + 2),
        const Radius.circular(10),
      ),
      shadowPaint,
    );

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(carLeft, carTop, carRight, carBottom),
        const Radius.circular(10),
      ),
      bodyPaint,
    );

    // Windshield (the opening the head pokes through)
    final double sunroofLeft = w * 0.30;
    final double sunroofRight = w * 0.70;
    final double sunroofTop = carTop - 2;
    final double sunroofBot = carTop + h * 0.10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(sunroofLeft, sunroofTop, sunroofRight, sunroofBot),
        const Radius.circular(4),
      ),
      windowPaint,
    );

    // Side windows
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(carLeft + 4, carTop + 4, sunroofLeft - 2,
            carTop + h * 0.14),
        const Radius.circular(3),
      ),
      windowPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(sunroofRight + 2, carTop + 4, carRight - 4,
            carTop + h * 0.14),
        const Radius.circular(3),
      ),
      windowPaint,
    );

    // Headlights
    canvas.drawCircle(
        Offset(carLeft + 8, carBottom - 6), 4, Paint()..color = const Color(0xFFFFF9C4));
    canvas.drawCircle(
        Offset(carRight - 8, carBottom - 6), 4, Paint()..color = const Color(0xFFFFF9C4));

    // Wheels (4 small circles)
    for (final Offset pos in <Offset>[
      Offset(carLeft + 8, carBottom),
      Offset(carLeft + 8, carBottom),
      Offset(carRight - 8, carBottom),
    ]) {
      canvas.drawCircle(pos, 7, wheelPaint);
      canvas.drawCircle(pos, 3, hubPaint);
    }
    // Rear wheels slightly visible
    canvas.drawCircle(Offset(carLeft + 10, carBottom - 1), 7, wheelPaint);
    canvas.drawCircle(Offset(carLeft + 10, carBottom - 1), 3, hubPaint);
    canvas.drawCircle(Offset(carRight - 10, carBottom - 1), 7, wheelPaint);
    canvas.drawCircle(Offset(carRight - 10, carBottom - 1), 3, hubPaint);

    // Spoiler (rocket accessory on car)
    if (hasSpoiler) {
      final Paint spoilerPaint = Paint()
        ..color = color.withAlpha(220)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(carLeft + 4, carTop - 4),
        Offset(carRight - 4, carTop - 4),
        spoilerPaint..style = PaintingStyle.fill
            ..color = const Color(0xFFE53935),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(carLeft + 4, carTop - 8, carRight - 4, carTop - 4),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFB71C1C),
      );
    }
  }

  // ── Cloud (Zen Master's ride) ────────────────────────────────────────────
  // Perfectly smooth driving = floating on a cloud. Fluffy cumulus puffs in
  // the car's canvas slot, a soft under-mist instead of wheels, and two tiny
  // sparkles for serenity.

  void _drawCloud(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.58;
    final double bottom = h * 0.86;
    final double midY = (top + bottom) / 2;

    // Under-mist (takes the place of a ground shadow — clouds don't clunk).
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.92), width: w * 0.6, height: h * 0.05),
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final Paint puff = Paint()..color = color;
    final Paint puffShade = Paint()
      ..color = Color.lerp(color, const Color(0xFF90A4AE), 0.35)!;

    // Flat-ish base with a soft shaded underside.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.10, midY, w * 0.90, bottom),
        Radius.circular(h * 0.07),
      ),
      puffShade,
    );

    // Fluffy top puffs (the head rises out from between them).
    canvas.drawCircle(Offset(w * 0.22, midY), w * 0.15, puff);
    canvas.drawCircle(Offset(w * 0.42, top + h * 0.02), w * 0.19, puff);
    canvas.drawCircle(Offset(w * 0.66, midY - h * 0.02), w * 0.16, puff);
    canvas.drawCircle(Offset(w * 0.84, midY + h * 0.02), w * 0.12, puff);
    // Fill the seams.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.12, midY - h * 0.015, w * 0.88, bottom - h * 0.02),
        Radius.circular(h * 0.06),
      ),
      puff,
    );

    // Serenity sparkles.
    final Paint sparkle = Paint()..color = const Color(0xFFFFF9C4);
    canvas.drawCircle(Offset(w * 0.13, top - h * 0.015), 1.6, sparkle);
    canvas.drawCircle(Offset(w * 0.88, top + h * 0.01), 1.2, sparkle);
  }

  // ── Rocket ship (The Rocket's ride) ──────────────────────────────────────
  // Speed IS the brand: a sideways rocket with a nose cone, tail fins, a
  // porthole, exhaust flame, and speed lines trailing behind.

  void _drawRocketShip(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.58;
    final double bottom = h * 0.86;
    final double midY = (top + bottom) / 2;
    final double bodyLeft = w * 0.14;
    final double bodyRight = w * 0.78;

    // Exhaust flame (behind/left — the rocket "flies" right).
    final Path flame = Path()
      ..moveTo(bodyLeft, midY - h * 0.055)
      ..lineTo(w * 0.02, midY)
      ..lineTo(bodyLeft, midY + h * 0.055)
      ..close();
    canvas.drawPath(flame, Paint()..color = const Color(0xFFFFA000));
    final Path flameInner = Path()
      ..moveTo(bodyLeft, midY - h * 0.03)
      ..lineTo(w * 0.07, midY)
      ..lineTo(bodyLeft, midY + h * 0.03)
      ..close();
    canvas.drawPath(flameInner, Paint()..color = const Color(0xFFFFF176));

    // Speed lines.
    final Paint lines = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.02, top + h * 0.01), Offset(w * 0.13, top + h * 0.01), lines);
    canvas.drawLine(
        Offset(w * 0.00, bottom - h * 0.015), Offset(w * 0.10, bottom - h * 0.015), lines);

    // Tail fins (top + bottom, at the back).
    final Paint fin = Paint()
      ..color = Color.lerp(color, const Color(0xFF7F0000), 0.35)!;
    final Path topFin = Path()
      ..moveTo(bodyLeft + w * 0.02, midY - h * 0.05)
      ..lineTo(bodyLeft - w * 0.015, top - h * 0.025)
      ..lineTo(bodyLeft + w * 0.13, midY - h * 0.045)
      ..close();
    canvas.drawPath(topFin, fin);
    final Path bottomFin = Path()
      ..moveTo(bodyLeft + w * 0.02, midY + h * 0.05)
      ..lineTo(bodyLeft - w * 0.015, bottom + h * 0.025)
      ..lineTo(bodyLeft + w * 0.13, midY + h * 0.045)
      ..close();
    canvas.drawPath(bottomFin, fin);

    // Body — horizontal capsule.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(bodyLeft, midY - h * 0.075, bodyRight, midY + h * 0.075),
        Radius.circular(h * 0.075),
      ),
      Paint()..color = color,
    );

    // Nose cone (front/right).
    final Path nose = Path()
      ..moveTo(bodyRight - w * 0.01, midY - h * 0.075)
      ..quadraticBezierTo(w * 0.98, midY, bodyRight - w * 0.01, midY + h * 0.075)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFFB71C1C));

    // Cockpit opening under the head (so the chibi rides IN it) + porthole.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.34, midY - h * 0.085, w * 0.62, midY),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFB3E5FC),
    );
    canvas.drawCircle(Offset(w * 0.70, midY), w * 0.045,
        Paint()..color = const Color(0xFFB3E5FC));
    canvas.drawCircle(
      Offset(w * 0.70, midY),
      w * 0.045,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF90A4AE),
    );
  }

  // ── UFO (The Phantom's ride) ─────────────────────────────────────────────
  // The ALPR-dodger flies the one vehicle no camera can identify. Classic
  // saucer: translucent dome (the fedora'd head sits inside it), gunmetal
  // disc, rim lights, and a soft abduction beam instead of wheels.

  void _drawUfo(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double midY = h * 0.68;

    // Abduction beam — a soft glowing cone where wheels would be.
    final Path beam = Path()
      ..moveTo(w * 0.36, midY)
      ..lineTo(w * 0.22, h * 0.95)
      ..lineTo(w * 0.78, h * 0.95)
      ..lineTo(w * 0.64, midY)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..color = const Color(0x3376FF03) // faint alien green
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Glass dome — translucent, drawn before the head so the chibi (and the
    // fedora) reads as sitting INSIDE it. Wider than the (huge chibi) head so
    // its glass edges stay visible around the face.
    final Rect domeRect = Rect.fromCenter(
        center: Offset(w * 0.5, midY - h * 0.06),
        width: w * 0.84,
        height: h * 0.34);
    canvas.drawArc(domeRect, math.pi, math.pi, true,
        Paint()..color = const Color(0x55B3E5FC));
    canvas.drawArc(
      domeRect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xAAB3E5FC),
    );

    // Saucer disc.
    final Rect disc = Rect.fromCenter(
        center: Offset(w * 0.5, midY),
        width: w * 0.88,
        height: h * 0.16);
    canvas.drawOval(
        disc.shift(const Offset(2, 2)), Paint()..color = Colors.black26);
    canvas.drawOval(disc, Paint()..color = color);
    // Underside — darker half-ellipse.
    canvas.drawArc(
        disc.inflate(0), 0, math.pi, true,
        Paint()..color = Color.lerp(color, Colors.black, 0.35)!);

    // Rim lights — the classic blinky trio.
    const List<Color> rim = <Color>[
      Color(0xFFFFEB3B),
      Color(0xFF76FF03),
      Color(0xFFFF6B6B),
    ];
    for (int i = 0; i < 3; i++) {
      final double lx = w * (0.30 + 0.20 * i);
      canvas.drawCircle(Offset(lx, midY + h * 0.035), 2.4,
          Paint()..color = rim[i]);
    }

    // Tiny antenna with a glowing ball, off-center for charm.
    canvas.drawLine(
      Offset(w * 0.5, midY - h * 0.20),
      Offset(w * 0.5, midY - h * 0.245),
      Paint()
        ..color = const Color(0xFF90A4AE)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(w * 0.5, midY - h * 0.255), 2.2,
        Paint()..color = const Color(0xFF76FF03));
  }

  // ── Spectral float (The Ghost) ───────────────────────────────────────────
  // Ghosts don't drive. A sheet-body that tapers into wisps where wheels
  // would be, plus a faint trail drifting off to one side.

  void _drawSpectralFloat(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.56;
    final double bottom = h * 0.90;

    // Drifting trail (behind, to the left).
    final Paint trail = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(w * 0.10, h * 0.72), w * 0.05, trail);
    canvas.drawCircle(Offset(w * 0.04, h * 0.66), w * 0.033, trail);

    // Sheet body: wide at the shoulders, wavy hem at the bottom.
    final Path sheet = Path()
      ..moveTo(w * 0.18, top + h * 0.02)
      ..quadraticBezierTo(w * 0.5, top - h * 0.05, w * 0.82, top + h * 0.02)
      ..lineTo(w * 0.84, bottom - h * 0.05);
    // Wavy hem — four scallops.
    const int scallops = 4;
    for (int i = 0; i < scallops; i++) {
      final double x1 = w * (0.84 - 0.165 * i) - w * 0.0825;
      final double x2 = w * (0.84 - 0.165 * (i + 1));
      sheet.quadraticBezierTo(
          x1, bottom + h * 0.035, x2, bottom - h * 0.05);
    }
    sheet.close();
    canvas.drawPath(sheet, Paint()..color = color.withValues(alpha: 0.92));
    // Inner shade for a hint of depth.
    canvas.drawPath(
      sheet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF9575CD).withValues(alpha: 0.5),
    );
  }

  // ── Vintage sedan (The Grandpa) ──────────────────────────────────────────
  // Rounded fenders, whitewall tires, and the LEFT BLINKER ETERNALLY ON.

  void _drawVintageSedan(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.58;
    final double bottom = h * 0.88;

    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.08 + 2, top + 2, w * 0.92 + 2, bottom + 2),
        Radius.circular(h * 0.10),
      ),
      Paint()..color = Colors.black26,
    );

    // Rounded vintage body — bigger corner radius than the modern car.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.08, top, w * 0.92, bottom),
        Radius.circular(h * 0.10),
      ),
      Paint()..color = color,
    );
    // Sweeping fender line.
    canvas.drawArc(
      Rect.fromLTRB(w * 0.10, top + h * 0.10, w * 0.90, bottom + h * 0.06),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Split windshield (the vintage tell) where the head pokes through.
    final Paint window = Paint()..color = const Color(0xFFB3E5FC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.30, top - 2, w * 0.485, top + h * 0.10),
        const Radius.circular(3),
      ),
      window,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.515, top - 2, w * 0.70, top + h * 0.10),
        const Radius.circular(3),
      ),
      window,
    );

    // Whitewall tires — the pride of the fleet.
    final Paint tire = Paint()..color = const Color(0xFF212121);
    final Paint whitewall = Paint()..color = const Color(0xFFF5F5F5);
    final Paint hub = Paint()..color = const Color(0xFFBDBDBD);
    for (final double x in <double>[w * 0.24, w * 0.76]) {
      canvas.drawCircle(Offset(x, bottom - 1), 8, tire);
      canvas.drawCircle(Offset(x, bottom - 1), 5, whitewall);
      canvas.drawCircle(Offset(x, bottom - 1), 2.5, hub);
    }

    // The eternal left blinker (amber, gently "on").
    canvas.drawCircle(
      Offset(w * 0.105, bottom - h * 0.075),
      3.2,
      Paint()
        ..color = const Color(0xFFFFB300)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // Right headlight, plain.
    canvas.drawCircle(Offset(w * 0.895, bottom - h * 0.075), 3,
        Paint()..color = const Color(0xFFFFF9C4));
  }

  // ── Crescent moon (The Night Owl) ────────────────────────────────────────
  // Hammocked inside a golden crescent, stars around, one drifting Z.

  void _drawCrescentMoon(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final Offset center = Offset(w * 0.5, h * 0.66);
    final double rOuter = w * 0.42;

    // Stars.
    final Paint star = Paint()..color = const Color(0xFFFFF59D);
    canvas.drawCircle(Offset(w * 0.10, h * 0.58), 1.8, star);
    canvas.drawCircle(Offset(w * 0.90, h * 0.62), 1.4, star);
    canvas.drawCircle(Offset(w * 0.16, h * 0.85), 1.4, star);
    canvas.drawCircle(Offset(w * 0.86, h * 0.86), 1.8, star);

    // Crescent: full disc minus an offset "bite" (clipped difference).
    final Path disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: rOuter));
    final Path bite = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(center.dx, center.dy - h * 0.085),
          radius: rOuter * 0.86));
    final Path crescent =
        Path.combine(PathOperation.difference, disc, bite);
    // Soft moon glow.
    canvas.drawPath(
      crescent,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(crescent, Paint()..color = color);
    // A couple of craters on the visible rim.
    final Paint crater = Paint()
        ..color = Color.lerp(color, const Color(0xFF8D6E63), 0.35)!;
    canvas.drawCircle(Offset(w * 0.28, h * 0.80), 2.4, crater);
    canvas.drawCircle(Offset(w * 0.66, h * 0.845), 1.8, crater);

    // One drifting Z (the nightcap head above completes the picture).
    final TextPainter z = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: h * 0.09,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    z.paint(canvas, Offset(w * 0.80, h * 0.50));
  }

  // ── Shopping cart (The Chaos Agent) ──────────────────────────────────────
  // Unpredictable speed, constant rerouting: a chrome shopping cart at full
  // tilt, one wheel wobbling, of course.

  void _drawShoppingCart(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.58;
    final double bottom = h * 0.84;

    final Paint frame = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Basket — a trapezoid of chrome lattice.
    final Path basket = Path()
      ..moveTo(w * 0.16, top)
      ..lineTo(w * 0.24, bottom - h * 0.045)
      ..lineTo(w * 0.78, bottom - h * 0.045)
      ..lineTo(w * 0.84, top)
      ..close();
    canvas.drawPath(
        basket, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawPath(basket, frame);
    // Lattice bars — horizontal wires that follow the basket's taper.
    for (int i = 1; i <= 3; i++) {
      final double t = i / 4;
      final double y = top + (bottom - h * 0.045 - top) * t;
      canvas.drawLine(
        Offset(w * (0.16 + 0.08 * t), y),
        Offset(w * (0.84 - 0.06 * t), y),
        frame..strokeWidth = 1.2,
      );
    }
    frame.strokeWidth = 2.2;

    // Handle bar (back-left, where a chaotic pilot grips).
    canvas.drawLine(
        Offset(w * 0.16, top), Offset(w * 0.06, top - h * 0.05), frame);
    canvas.drawLine(Offset(w * 0.06, top - h * 0.05),
        Offset(w * 0.06, top - h * 0.015), frame);

    // Wheels: tiny casters — and the front one is WOBBLING.
    final Paint tire = Paint()..color = const Color(0xFF212121);
    final Paint hub = Paint()..color = const Color(0xFFBDBDBD);
    canvas.drawCircle(Offset(w * 0.28, bottom + h * 0.02), 5, tire);
    canvas.drawCircle(Offset(w * 0.28, bottom + h * 0.02), 2, hub);
    // Wobble: front caster drawn tilted off its mount.
    canvas.save();
    canvas.translate(w * 0.72, bottom + h * 0.02);
    canvas.rotate(0.5);
    canvas.drawCircle(Offset.zero, 5, tire);
    canvas.drawCircle(Offset.zero, 2, hub);
    canvas.restore();

    // Chaos lines (it is moving FAST).
    final Paint lines = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.0, top + h * 0.05),
        Offset(w * 0.10, top + h * 0.055), lines);
    canvas.drawLine(Offset(w * 0.02, bottom - h * 0.02),
        Offset(w * 0.11, bottom - h * 0.025), lines);
  }

  // ── Skateboard (The Street Rat) ──────────────────────────────────────────
  // A chunky longboard with fat wheels — back roads only, obviously.

  void _drawSkateboard(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double deckY = h * 0.80;

    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.93), width: w * 0.7, height: h * 0.05),
      Paint()..color = Colors.black26,
    );

    // Deck — slight kick at both ends via a bent path.
    final Path deck = Path()
      ..moveTo(w * 0.06, deckY - h * 0.035)
      ..quadraticBezierTo(w * 0.10, deckY, w * 0.20, deckY)
      ..lineTo(w * 0.80, deckY)
      ..quadraticBezierTo(w * 0.90, deckY, w * 0.94, deckY - h * 0.035)
      ..lineTo(w * 0.94, deckY + h * 0.005)
      ..quadraticBezierTo(w * 0.90, deckY + h * 0.038, w * 0.80, deckY + h * 0.038)
      ..lineTo(w * 0.20, deckY + h * 0.038)
      ..quadraticBezierTo(w * 0.10, deckY + h * 0.038, w * 0.06, deckY + h * 0.005)
      ..close();
    canvas.drawPath(deck, Paint()..color = color);
    // Grip-tape stripe.
    canvas.drawLine(
      Offset(w * 0.20, deckY + h * 0.012),
      Offset(w * 0.80, deckY + h * 0.012),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    // Fat wheels (urethane orange — skater canon).
    final Paint wheel = Paint()..color = const Color(0xFFFF9800);
    final Paint hub = Paint()..color = const Color(0xFFFFE0B2);
    for (final double x in <double>[w * 0.26, w * 0.74]) {
      canvas.drawCircle(Offset(x, deckY + h * 0.075), 6.5, wheel);
      canvas.drawCircle(Offset(x, deckY + h * 0.075), 2.6, hub);
    }
  }

  // ── Jeep (The Scout) ─────────────────────────────────────────────────────
  // Open-top expedition rig: spare tire on the back, antenna flag up front.

  void _drawJeep(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double top = h * 0.60;
    final double bottom = h * 0.88;

    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.10 + 2, top + 2, w * 0.90 + 2, bottom + 2),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.black26,
    );

    // Boxy open-top body (no roof — the head IS the driver, visibly).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.10, top, w * 0.90, bottom),
        const Radius.circular(5),
      ),
      Paint()..color = color,
    );
    // Flat fold-down windshield in front of the head.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.62, top - h * 0.055, w * 0.68, top + h * 0.02),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFB3E5FC),
    );
    // Horizontal grille slats at the front.
    final Paint slat = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 1.4;
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(w * 0.84, top + h * 0.05 + i * h * 0.035),
        Offset(w * 0.895, top + h * 0.05 + i * h * 0.035),
        slat,
      );
    }

    // Spare tire mounted on the back.
    final Paint tire = Paint()..color = const Color(0xFF212121);
    canvas.drawCircle(Offset(w * 0.085, (top + bottom) / 2), 7.5, tire);
    canvas.drawCircle(Offset(w * 0.085, (top + bottom) / 2), 3,
        Paint()..color = color);

    // Knobby off-road wheels.
    final Paint hub = Paint()..color = const Color(0xFFBDBDBD);
    for (final double x in <double>[w * 0.28, w * 0.72]) {
      canvas.drawCircle(Offset(x, bottom), 8.5, tire);
      canvas.drawCircle(Offset(x, bottom), 3.2, hub);
    }

    // Antenna flag.
    canvas.drawLine(
      Offset(w * 0.14, top),
      Offset(w * 0.14, top - h * 0.09),
      Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = 1.5,
    );
    final Path flag = Path()
      ..moveTo(w * 0.14, top - h * 0.09)
      ..lineTo(w * 0.24, top - h * 0.0725)
      ..lineTo(w * 0.14, top - h * 0.055)
      ..close();
    canvas.drawPath(flag, Paint()..color = const Color(0xFFFF6B6B));
  }

  // ── TUX KART (creator easter egg) ────────────────────────────────────────
  // Tux the Linux penguin — fedora, go-kart, zero license plates on file.

  void _paintTuxKart(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;

    // Subtle terminal-green aura, because of course.
    _drawAura(canvas, cx, h * 0.55, w * 0.50, const Color(0x2226A269));

    // Kart first (behind the body).
    _drawKart(canvas, size, const Color(0xFFE53935));

    // Tux head (with the same bob as everyone else).
    final double headRadius = w * 0.36;
    final double bobOffset = math.sin(bob * 2 * math.pi) * h * 0.045;
    final Offset head = Offset(cx, h * 0.38 + bobOffset);
    _drawTuxHead(canvas, head, headRadius);

    // The fedora — reused from The Phantom's wardrobe.
    _drawFedora(canvas, head, headRadius);
  }

  void _drawTuxHead(Canvas canvas, Offset c, double r) {
    // Black penguin head.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1B1B1D));
    // White face patch — two joined ovals, the classic Tux mask.
    final Paint face = Paint()..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx - r * 0.30, c.dy + r * 0.18),
          width: r * 0.72,
          height: r * 0.95),
      face,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx + r * 0.30, c.dy + r * 0.18),
          width: r * 0.72,
          height: r * 0.95),
      face,
    );

    // Eyes — white sclera up in the black zone, dark pupils, tiny shine.
    for (final double sx in <double>[-1, 1]) {
      final Offset eye = Offset(c.dx + sx * r * 0.30, c.dy - r * 0.28);
      canvas.drawOval(
        Rect.fromCenter(
            center: eye, width: r * 0.34, height: r * 0.42),
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(Offset(eye.dx + sx * r * 0.04, eye.dy + r * 0.05),
          r * 0.09, Paint()..color = const Color(0xFF1B1B1D));
      canvas.drawCircle(Offset(eye.dx + sx * r * 0.01, eye.dy - r * 0.01),
          r * 0.03, Paint()..color = Colors.white);
    }

    // Beak — orange, slightly open (upper wedge over lower wedge).
    final Paint beak = Paint()..color = const Color(0xFFF57C00);
    final Path upperBeak = Path()
      ..moveTo(c.dx - r * 0.22, c.dy + r * 0.02)
      ..quadraticBezierTo(
          c.dx, c.dy + r * 0.30, c.dx + r * 0.22, c.dy + r * 0.02)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.14, c.dx - r * 0.22, c.dy + r * 0.02)
      ..close();
    canvas.drawPath(upperBeak, beak);
    canvas.drawPath(
      upperBeak,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFBF5B00),
    );
  }

  /// A Mario-style go-kart: low red body, nose cone, seat back, steering
  /// wheel, chunky rear tire + smaller front tire, and a puff of exhaust.
  void _drawKart(Canvas canvas, Size size, Color color) {
    final double w = size.width;
    final double h = size.height;
    final double bodyTop = h * 0.68;
    final double bodyBottom = h * 0.82;

    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.92), width: w * 0.8, height: h * 0.05),
      Paint()..color = Colors.black26,
    );

    // Exhaust puff (rear-left).
    final Paint puff = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(w * 0.045, bodyBottom - h * 0.01), w * 0.045, puff);
    canvas.drawCircle(Offset(w * 0.10, bodyBottom - h * 0.035), w * 0.03, puff);

    // Seat back — rises behind the head.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.16, bodyTop - h * 0.09, w * 0.30, bodyTop + h * 0.02),
        const Radius.circular(4),
      ),
      Paint()..color = Color.lerp(color, Colors.black, 0.25)!,
    );

    // Low kart body with a tapered nose (front = right).
    final Path body = Path()
      ..moveTo(w * 0.12, bodyTop)
      ..lineTo(w * 0.74, bodyTop)
      ..quadraticBezierTo(w * 0.95, bodyTop + h * 0.02, w * 0.92, bodyBottom)
      ..lineTo(w * 0.14, bodyBottom)
      ..quadraticBezierTo(w * 0.10, bodyBottom, w * 0.12, bodyTop)
      ..close();
    canvas.drawPath(body, Paint()..color = color);
    // Racing stripe down the nose.
    canvas.drawLine(
      Offset(w * 0.60, bodyTop + h * 0.015),
      Offset(w * 0.88, bodyBottom - h * 0.02),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Steering column + wheel (in front of the driver).
    canvas.drawLine(
      Offset(w * 0.60, bodyTop),
      Offset(w * 0.66, bodyTop - h * 0.055),
      Paint()
        ..color = const Color(0xFF424242)
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      Offset(w * 0.67, bodyTop - h * 0.06),
      w * 0.055,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF424242),
    );

    // Wheels: chunky rear, smaller front — kart proportions.
    final Paint tire = Paint()..color = const Color(0xFF212121);
    final Paint hub = Paint()..color = const Color(0xFFFFD54F); // gold hubs
    canvas.drawCircle(Offset(w * 0.22, bodyBottom + h * 0.015), 9, tire);
    canvas.drawCircle(Offset(w * 0.22, bodyBottom + h * 0.015), 3.6, hub);
    canvas.drawCircle(Offset(w * 0.78, bodyBottom + h * 0.02), 7, tire);
    canvas.drawCircle(Offset(w * 0.78, bodyBottom + h * 0.02), 2.8, hub);
  }

  // ── Head ──────────────────────────────────────────────────────────────────

  void _drawHead(
      Canvas canvas, Offset center, double radius, Color skinColor) {
    // Shadow
    canvas.drawCircle(
      center + const Offset(2, 2),
      radius,
      Paint()..color = Colors.black26,
    );
    // Head circle
    canvas.drawCircle(center, radius, Paint()..color = skinColor);
    // Cheek blush
    final Paint blushPaint = Paint()..color = const Color(0x55FF8A80);
    canvas.drawCircle(
        center + Offset(-radius * 0.55, radius * 0.2), radius * 0.22, blushPaint);
    canvas.drawCircle(
        center + Offset(radius * 0.55, radius * 0.2), radius * 0.22, blushPaint);
  }

  // ── Eyes ──────────────────────────────────────────────────────────────────

  void _drawEyes(
      Canvas canvas, Offset head, double r, _EyeStyle style) {
    final double ex = r * 0.38;
    final double ey = -r * 0.05;
    final Offset left = head + Offset(-ex, ey);
    final Offset right = head + Offset(ex, ey);

    switch (style) {
      case _EyeStyle.normal:
        _solidEye(canvas, left, r * 0.13);
        _solidEye(canvas, right, r * 0.13);
      case _EyeStyle.happy:
        _happyEye(canvas, left, r);
        _happyEye(canvas, right, r);
      case _EyeStyle.wide:
        _solidEye(canvas, left, r * 0.17);
        _solidEye(canvas, right, r * 0.17);
        // white highlight
        canvas.drawCircle(left + Offset(r * 0.04, -r * 0.04),
            r * 0.05, Paint()..color = Colors.white);
        canvas.drawCircle(right + Offset(r * 0.04, -r * 0.04),
            r * 0.05, Paint()..color = Colors.white);
      case _EyeStyle.sleepy:
        _sleepyEye(canvas, left, r);
        _sleepyEye(canvas, right, r);
      case _EyeStyle.squint:
        _squintEye(canvas, left, r);
        _squintEye(canvas, right, r);
      case _EyeStyle.closed:
        _closedEye(canvas, left, r);
        _closedEye(canvas, right, r);
      case _EyeStyle.hollow:
        _hollowEye(canvas, left, r);
        _hollowEye(canvas, right, r);
    }
  }

  void _solidEye(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF212121));
  }

  void _happyEye(Canvas canvas, Offset c, double r) {
    // ^ shape — happy arc
    final Path p = Path()
      ..moveTo(c.dx - r * 0.15, c.dy)
      ..quadraticBezierTo(c.dx, c.dy - r * 0.2, c.dx + r * 0.15, c.dy);
    canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF212121)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  void _sleepyEye(Canvas canvas, Offset c, double r) {
    // half-closed: filled semicircle bottom
    final Path p = Path()
      ..moveTo(c.dx - r * 0.15, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.18, c.dx + r * 0.15, c.dy);
    canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF212121)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    // eyelid line
    canvas.drawLine(
        c + Offset(-r * 0.15, 0),
        c + Offset(r * 0.15, 0),
        Paint()
          ..color = const Color(0xFF212121)
          ..strokeWidth = 1.5);
  }

  void _squintEye(Canvas canvas, Offset c, double r) {
    canvas.drawLine(
        c + Offset(-r * 0.14, -r * 0.02),
        c + Offset(r * 0.14, r * 0.02),
        Paint()
          ..color = const Color(0xFF212121)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
  }

  void _closedEye(Canvas canvas, Offset c, double r) {
    canvas.drawArc(
      Rect.fromCenter(center: c, width: r * 0.32, height: r * 0.18),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF212121)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );
  }

  void _hollowEye(Canvas canvas, Offset c, double r) {
    // Ghost eyes: oval outlines with no pupil
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 0.28, height: r * 0.36),
      Paint()..color = const Color(0xFF212121),
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 0.16, height: r * 0.22),
      Paint()..color = Colors.white,
    );
  }

  // ── Mouth ─────────────────────────────────────────────────────────────────

  void _drawMouth(Canvas canvas, Offset head, double r, _MouthStyle style) {
    final Offset m = head + Offset(0, r * 0.38);

    switch (style) {
      case _MouthStyle.smile:
        canvas.drawArc(
          Rect.fromCenter(center: m, width: r * 0.5, height: r * 0.24),
          0,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFF212121)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      case _MouthStyle.smirk:
        final Path p = Path()
          ..moveTo(m.dx - r * 0.14, m.dy + r * 0.04)
          ..quadraticBezierTo(m.dx, m.dy - r * 0.04, m.dx + r * 0.14, m.dy);
        canvas.drawPath(
            p,
            Paint()
              ..color = const Color(0xFF212121)
              ..strokeWidth = 2.0
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round);
      case _MouthStyle.grin:
        canvas.drawArc(
          Rect.fromCenter(center: m, width: r * 0.58, height: r * 0.30),
          0,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFF212121)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
        // teeth
        canvas.drawRect(
          Rect.fromCenter(center: m + Offset(0, r * 0.04),
              width: r * 0.28, height: r * 0.10),
          Paint()..color = Colors.white,
        );
      case _MouthStyle.frown:
        canvas.drawArc(
          Rect.fromCenter(center: m + Offset(0, r * 0.1),
              width: r * 0.5, height: r * 0.24),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFF212121)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      case _MouthStyle.neutral:
        canvas.drawLine(
          m + Offset(-r * 0.14, 0),
          m + Offset(r * 0.14, 0),
          Paint()
            ..color = const Color(0xFF212121)
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round,
        );
      case _MouthStyle.ooo:
        canvas.drawOval(
          Rect.fromCenter(center: m, width: r * 0.20, height: r * 0.26),
          Paint()..color = const Color(0xFF212121),
        );
    }
  }

  // ── Accessories ───────────────────────────────────────────────────────────

  void _drawAccessoryA(
      Canvas canvas, Offset head, double r, _AccessoryType type) {
    switch (type) {
      case _AccessoryType.readingGlasses:
        _drawGlasses(canvas, head, r,
            frameColor: const Color(0xFF795548), lensColor: const Color(0x2200BCD4));
      case _AccessoryType.racingGoggles:
        _drawGlasses(canvas, head, r,
            frameColor: const Color(0xFFE53935),
            lensColor: const Color(0x44FF6F00),
            thick: true);
      case _AccessoryType.explorerHat:
        _drawBrimHat(canvas, head, r,
            crownColor: const Color(0xFF8D6E63),
            brimColor: const Color(0xFF6D4C41));
      case _AccessoryType.fedora:
        _drawFedora(canvas, head, r);
      case _AccessoryType.nightCap:
        _drawNightCap(canvas, head, r);
      case _AccessoryType.hoodie:
        _drawHoodie(canvas, head, r);
      case _AccessoryType.coffeeX3:
        _drawCoffees(canvas, head, r);
      case _AccessoryType.zenHalo:
        _drawHalo(canvas, head, r);
      case _AccessoryType.crownSmall:
        _drawCrown(canvas, head, r);
      case _AccessoryType.creatureHorns:
        _drawCreatureHorns(canvas, head, r);
      case _AccessoryType.goldHalo:
        _drawGoldHalo(canvas, head, r);
      case _AccessoryType.silkSparkle:
        _drawSilkSparkle(canvas, head, r);
      default:
        break;
    }
  }

  void _drawGlasses(Canvas canvas, Offset head, double r,
      {required Color frameColor,
      required Color lensColor,
      bool thick = false}) {
    final double ey = head.dy - r * 0.05;
    final double ex = r * 0.38;
    final double lensR = r * 0.18;
    final double strokeW = thick ? 2.5 : 1.5;

    // Left lens
    canvas.drawCircle(head + Offset(-ex, ey - head.dy),
        lensR, Paint()..color = lensColor);
    canvas.drawCircle(
        head + Offset(-ex, ey - head.dy),
        lensR,
        Paint()
          ..color = frameColor
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke);
    // Right lens
    canvas.drawCircle(head + Offset(ex, ey - head.dy),
        lensR, Paint()..color = lensColor);
    canvas.drawCircle(
        head + Offset(ex, ey - head.dy),
        lensR,
        Paint()
          ..color = frameColor
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke);
    // Bridge
    canvas.drawLine(
        head + Offset(-ex + lensR, ey - head.dy),
        head + Offset(ex - lensR, ey - head.dy),
        Paint()
          ..color = frameColor
          ..strokeWidth = strokeW);
  }

  void _drawBrimHat(Canvas canvas, Offset head, double r,
      {required Color crownColor, required Color brimColor}) {
    final double hatY = head.dy - r * 0.82;
    // Crown
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(head.dx, hatY), width: r * 1.1, height: r * 0.55),
        const Radius.circular(4),
      ),
      Paint()..color = crownColor,
    );
    // Brim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(head.dx, hatY + r * 0.28),
            width: r * 1.6,
            height: r * 0.18),
        const Radius.circular(3),
      ),
      Paint()..color = brimColor,
    );
    // Band
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(head.dx, hatY + r * 0.05),
          width: r * 1.1,
          height: r * 0.10),
      Paint()..color = const Color(0xFF5D4037),
    );
  }

  void _drawFedora(Canvas canvas, Offset head, double r) {
    final double hatY = head.dy - r * 0.80;
    // Crown with center dent
    final Path crownPath = Path()
      ..moveTo(head.dx - r * 0.55, hatY + r * 0.22)
      ..lineTo(head.dx - r * 0.50, hatY)
      ..quadraticBezierTo(head.dx, hatY - r * 0.12, head.dx + r * 0.50, hatY)
      ..lineTo(head.dx + r * 0.55, hatY + r * 0.22)
      ..close();
    canvas.drawPath(crownPath, Paint()..color = const Color(0xFF37474F));
    // Brim
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(head.dx, hatY + r * 0.22),
          width: r * 1.5,
          height: r * 0.22),
      Paint()..color = const Color(0xFF263238),
    );
    // Hat band
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(head.dx, hatY + r * 0.10),
          width: r * 1.10,
          height: r * 0.09),
      Paint()..color = const Color(0xFF546E7A),
    );
  }

  void _drawNightCap(Canvas canvas, Offset head, double r) {
    final Path cap = Path()
      ..moveTo(head.dx - r * 0.70, head.dy - r * 0.55)
      ..lineTo(head.dx + r * 0.70, head.dy - r * 0.55)
      ..lineTo(head.dx + r * 0.20, head.dy - r * 1.40)
      ..quadraticBezierTo(
          head.dx, head.dy - r * 1.60, head.dx - r * 0.10, head.dy - r * 1.50)
      ..close();
    canvas.drawPath(cap, Paint()..color = const Color(0xFF1A237E));
    // Pompom
    canvas.drawCircle(head + Offset(-r * 0.08, -r * 1.55),
        r * 0.14, Paint()..color = Colors.white);
    // Band
    canvas.drawRect(
      Rect.fromLTRB(head.dx - r * 0.70, head.dy - r * 0.65,
          head.dx + r * 0.70, head.dy - r * 0.55),
      Paint()..color = Colors.white,
    );
    // Moon decoration
    canvas.drawCircle(head + Offset(r * 0.10, -r * 1.10),
        r * 0.10, Paint()..color = const Color(0xFFFFEB3B));
  }

  void _drawHoodie(Canvas canvas, Offset head, double r) {
    // The hood is a larger circle around the head. Since accessories paint
    // AFTER the face, we redraw the head fill (so it sits inside the hood) and
    // then re-draw the eyes + mouth on top — otherwise the hood erases the face.
    final _ArchetypeConfig cfg = _kConfigs[archetype]!;
    final Paint hoodPaint = Paint()..color = const Color(0xFF616161);
    canvas.drawCircle(head, r * 1.10, hoodPaint);
    canvas.drawCircle(head, r, Paint()..color = cfg.headColor);
    _drawEyes(canvas, head, r, cfg.eyeStyle);
    _drawMouth(canvas, head, r, cfg.mouthStyle);
    // Hood strings
    canvas.drawLine(
        head + Offset(-r * 0.14, r * 0.65),
        head + Offset(-r * 0.10, r * 0.90),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5);
    canvas.drawLine(
        head + Offset(r * 0.14, r * 0.65),
        head + Offset(r * 0.10, r * 0.90),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5);
    // Rat ears (tiny triangle ears)
    _drawRatEar(canvas, head + Offset(-r * 0.78, -r * 0.72), r, left: true);
    _drawRatEar(canvas, head + Offset(r * 0.78, -r * 0.72), r, left: false);
  }

  void _drawRatEar(Canvas canvas, Offset pos, double r, {required bool left}) {
    final double d = left ? -1 : 1;
    final Path ear = Path()
      ..moveTo(pos.dx, pos.dy + r * 0.12)
      ..lineTo(pos.dx + d * r * 0.12, pos.dy - r * 0.12)
      ..lineTo(pos.dx + d * r * 0.22, pos.dy + r * 0.06)
      ..close();
    canvas.drawPath(ear, Paint()..color = const Color(0xFF757575));
    // Inner ear
    final Path inner = Path()
      ..moveTo(pos.dx + d * r * 0.02, pos.dy + r * 0.08)
      ..lineTo(pos.dx + d * r * 0.12, pos.dy - r * 0.06)
      ..lineTo(pos.dx + d * r * 0.18, pos.dy + r * 0.04)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFE57373));
  }

  void _drawCoffees(Canvas canvas, Offset head, double r) {
    // Three tiny coffee cups floating near the head
    for (int i = 0; i < 3; i++) {
      final double angle = -0.5 + i * 0.5;
      final Offset pos = head + Offset(
        (r * 0.90) * math.cos(angle - math.pi / 2),
        (r * 0.90) * math.sin(angle - math.pi / 2) - r * 0.3,
      );
      _drawTinyCup(canvas, pos, r * 0.18);
    }
  }

  void _drawTinyCup(Canvas canvas, Offset pos, double size) {
    // Cup body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: size * 1.4, height: size * 1.6),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFF6F00),
    );
    // Steam lines
    canvas.drawLine(
        pos + Offset(-size * 0.2, -size * 0.9),
        pos + Offset(-size * 0.2, -size * 1.4),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 1.0);
    canvas.drawLine(
        pos + Offset(size * 0.2, -size * 0.9),
        pos + Offset(size * 0.2, -size * 1.4),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 1.0);
  }

  void _drawHalo(Canvas canvas, Offset head, double r) {
    canvas.drawArc(
      Rect.fromCenter(
          center: head + Offset(0, -r * 0.92),
          width: r * 0.90,
          height: r * 0.28),
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFFFEB3B)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawCrown(Canvas canvas, Offset head, double r) {
    final double y = head.dy - r * 0.82;
    final Path crown = Path()
      ..moveTo(head.dx - r * 0.45, y + r * 0.28)
      ..lineTo(head.dx - r * 0.45, y)
      ..lineTo(head.dx - r * 0.22, y + r * 0.16)
      ..lineTo(head.dx, y - r * 0.10)
      ..lineTo(head.dx + r * 0.22, y + r * 0.16)
      ..lineTo(head.dx + r * 0.45, y)
      ..lineTo(head.dx + r * 0.45, y + r * 0.28)
      ..close();
    canvas.drawPath(crown, Paint()..color = const Color(0xFFFFD700));
    // Jewels
    for (final Offset jewel in <Offset>[
      Offset(head.dx - r * 0.28, y + r * 0.10),
      Offset(head.dx, y),
      Offset(head.dx + r * 0.28, y + r * 0.10),
    ]) {
      canvas.drawCircle(jewel, r * 0.06, Paint()..color = migoTeal);
    }
  }

  // ── Rare: Creature of Habit — two little monster horns ────────────────────

  void _drawCreatureHorns(Canvas canvas, Offset head, double r) {
    final Paint horn = Paint()..color = const Color(0xFF33691E); // dark green
    final double y = head.dy - r * 0.74;
    final Path left = Path()
      ..moveTo(head.dx - r * 0.42, y + r * 0.30)
      ..lineTo(head.dx - r * 0.30, y - r * 0.14)
      ..lineTo(head.dx - r * 0.16, y + r * 0.30)
      ..close();
    final Path right = Path()
      ..moveTo(head.dx + r * 0.16, y + r * 0.30)
      ..lineTo(head.dx + r * 0.30, y - r * 0.14)
      ..lineTo(head.dx + r * 0.42, y + r * 0.30)
      ..close();
    canvas.drawPath(left, horn);
    canvas.drawPath(right, horn);
  }

  // ── Rare: Guardian — a rich gold halo (thicker than the zen halo) ─────────

  void _drawGoldHalo(Canvas canvas, Offset head, double r) {
    canvas.drawArc(
      Rect.fromCenter(
          center: head + Offset(0, -r * 0.95),
          width: r * 1.00,
          height: r * 0.32),
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke,
    );
  }

  // ── Rare: Silk Hands — a scatter of little sparkle stars ──────────────────

  void _drawSilkSparkle(Canvas canvas, Offset head, double r) {
    final Paint star = Paint()..color = const Color(0xFFFFFFFF);
    for (final Offset c in <Offset>[
      Offset(head.dx - r * 0.70, head.dy - r * 0.55),
      Offset(head.dx + r * 0.72, head.dy - r * 0.30),
      Offset(head.dx + r * 0.55, head.dy + r * 0.55),
    ]) {
      _drawSparkle(canvas, c, r * 0.18, star);
    }
  }

  /// A 4-point sparkle centered at [c] with arm length [s].
  void _drawSparkle(Canvas canvas, Offset c, double s, Paint paint) {
    final Path p = Path()
      ..moveTo(c.dx, c.dy - s)
      ..lineTo(c.dx + s * 0.28, c.dy - s * 0.28)
      ..lineTo(c.dx + s, c.dy)
      ..lineTo(c.dx + s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx, c.dy + s)
      ..lineTo(c.dx - s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx - s, c.dy)
      ..lineTo(c.dx - s * 0.28, c.dy - s * 0.28)
      ..close();
    canvas.drawPath(p, paint);
  }

  // ── Equipped cosmetic (unlockable) ────────────────────────────────────────
  // Drawn as a small emblem at the upper-right of the head — uniform placement
  // so all 15 unlockables read clearly as a worn pin/badge, on a white backing
  // so they stay legible against any car/head color.

  void _drawCosmetic(Canvas canvas, Offset head, double r, CosmeticId id) {
    final Offset c = Offset(head.dx + r * 0.72, head.dy - r * 0.72);
    final double s = r * 0.62; // emblem size

    // White badge backing for contrast.
    canvas.drawCircle(c, s * 0.62, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      s * 0.62,
      Paint()
        ..color = Colors.black26
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    switch (id) {
      case CosmeticId.phoBowl:
        _emblemBowl(canvas, c, s, const Color(0xFF8D6E63)); // brown broth
      case CosmeticId.ramenBowl:
        _emblemBowl(canvas, c, s, const Color(0xFFFFB300)); // golden broth
      case CosmeticId.coffeeCup:
        _emblemCoffee(canvas, c, s);
      case CosmeticId.tacoHat:
        _emblemTaco(canvas, c, s);
      case CosmeticId.burgerBun:
        _emblemBurger(canvas, c, s);
      case CosmeticId.lipstickCrown:
        _emblemCrown(canvas, c, s, const Color(0xFFEC407A));
      case CosmeticId.musicNote:
        _emblemNote(canvas, c, s);
      case CosmeticId.popcornBucket:
        _emblemPopcorn(canvas, c, s);
      case CosmeticId.dumbbellPin:
        _emblemDumbbell(canvas, c, s);
      case CosmeticId.tinyBook:
        _emblemBook(canvas, c, s);
      case CosmeticId.vinylDisc:
        _emblemVinyl(canvas, c, s);
      case CosmeticId.streakFlamePin:
        _emblemFlame(canvas, c, s);
      case CosmeticId.goldClock:
        _emblemClock(canvas, c, s);
      case CosmeticId.shieldBadge:
        _emblemShield(canvas, c, s);
      case CosmeticId.founderStar:
        _emblemStar(canvas, c, s, const Color(0xFFFFD700));
    }
  }

  // Bowl (pho/ramen) — half-disc of broth + rising steam.
  void _emblemBowl(Canvas canvas, Offset c, double s, Color broth) {
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy + s * 0.08),
          width: s * 0.85,
          height: s * 0.55),
      0,
      math.pi,
      true,
      Paint()..color = broth,
    );
    _emblemSteam(canvas, c, s);
  }

  void _emblemSteam(Canvas canvas, Offset c, double s) {
    final Paint p = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(c.dx - s * 0.14, c.dy - s * 0.12),
        Offset(c.dx - s * 0.14, c.dy - s * 0.40), p);
    canvas.drawLine(Offset(c.dx + s * 0.14, c.dy - s * 0.12),
        Offset(c.dx + s * 0.14, c.dy - s * 0.40), p);
  }

  // Coffee cup — body + handle + steam.
  void _emblemCoffee(Canvas canvas, Offset c, double s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: s * 0.5, height: s * 0.55),
          const Radius.circular(2)),
      Paint()..color = const Color(0xFF6D4C41),
    );
    canvas.drawCircle(
      Offset(c.dx + s * 0.34, c.dy),
      s * 0.12,
      Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    _emblemSteam(canvas, c, s);
  }

  // Taco — folded golden shell with a green filling line.
  void _emblemTaco(Canvas canvas, Offset c, double s) {
    canvas.drawArc(
      Rect.fromCenter(center: c, width: s * 0.85, height: s * 0.85),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFFFFC107),
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy - s * 0.02),
          width: s * 0.7,
          height: s * 0.5),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF66BB6A)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  // Burger — top bun, patty, bottom bun.
  void _emblemBurger(Canvas canvas, Offset c, double s) {
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy - s * 0.16),
          width: s * 0.8,
          height: s * 0.5),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFFE0A35A),
    );
    canvas.drawRect(
      Rect.fromCenter(center: c, width: s * 0.8, height: s * 0.16),
      Paint()..color = const Color(0xFF6D4C41),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(c.dx, c.dy + s * 0.2),
              width: s * 0.8,
              height: s * 0.22),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFFE0A35A),
    );
  }

  // Small 3-point crown in [color].
  void _emblemCrown(Canvas canvas, Offset c, double s, Color color) {
    final double y = c.dy + s * 0.22;
    final Path p = Path()
      ..moveTo(c.dx - s * 0.4, y)
      ..lineTo(c.dx - s * 0.4, y - s * 0.45)
      ..lineTo(c.dx - s * 0.18, y - s * 0.2)
      ..lineTo(c.dx, y - s * 0.5)
      ..lineTo(c.dx + s * 0.18, y - s * 0.2)
      ..lineTo(c.dx + s * 0.4, y - s * 0.45)
      ..lineTo(c.dx + s * 0.4, y)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  // Music note — head + stem + flag.
  void _emblemNote(Canvas canvas, Offset c, double s) {
    final Paint p = Paint()..color = const Color(0xFF5E35B1);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx - s * 0.12, c.dy + s * 0.22),
          width: s * 0.32,
          height: s * 0.24),
      p,
    );
    canvas.drawRect(Rect.fromLTWH(c.dx + s * 0.02, c.dy - s * 0.35, s * 0.08, s * 0.57), p);
    canvas.drawRect(Rect.fromLTWH(c.dx + s * 0.02, c.dy - s * 0.35, s * 0.22, s * 0.10), p);
  }

  // Popcorn — red tub + popped kernels.
  void _emblemPopcorn(Canvas canvas, Offset c, double s) {
    final Path tub = Path()
      ..moveTo(c.dx - s * 0.3, c.dy - s * 0.1)
      ..lineTo(c.dx - s * 0.4, c.dy + s * 0.4)
      ..lineTo(c.dx + s * 0.4, c.dy + s * 0.4)
      ..lineTo(c.dx + s * 0.3, c.dy - s * 0.1)
      ..close();
    canvas.drawPath(tub, Paint()..color = const Color(0xFFE53935));
    for (final double dx in <double>[-0.18, 0.0, 0.18]) {
      canvas.drawCircle(Offset(c.dx + s * dx, c.dy - s * 0.2), s * 0.12,
          Paint()..color = const Color(0xFFFFF59D));
    }
  }

  // Dumbbell — bar + two weights.
  void _emblemDumbbell(Canvas canvas, Offset c, double s) {
    final Paint p = Paint()..color = const Color(0xFF455A64);
    canvas.drawRect(
        Rect.fromCenter(center: c, width: s * 0.7, height: s * 0.12), p);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx - s * 0.34, c.dy),
                width: s * 0.14,
                height: s * 0.5),
            const Radius.circular(2)),
        p);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx + s * 0.34, c.dy),
                width: s * 0.14,
                height: s * 0.5),
            const Radius.circular(2)),
        p);
  }

  // Book — cover + center page line.
  void _emblemBook(Canvas canvas, Offset c, double s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: s * 0.6, height: s * 0.72),
          const Radius.circular(2)),
      Paint()..color = const Color(0xFF8E24AA),
    );
    canvas.drawLine(Offset(c.dx, c.dy - s * 0.32), Offset(c.dx, c.dy + s * 0.32),
        Paint()..color = Colors.white..strokeWidth = 1.0);
  }

  // Vinyl record — black disc, colored label, center hole.
  void _emblemVinyl(Canvas canvas, Offset c, double s) {
    canvas.drawCircle(c, s * 0.42, Paint()..color = const Color(0xFF212121));
    canvas.drawCircle(c, s * 0.16, Paint()..color = const Color(0xFFEF5350));
    canvas.drawCircle(c, s * 0.04, Paint()..color = Colors.white);
  }

  // Flame — teardrop.
  void _emblemFlame(Canvas canvas, Offset c, double s) {
    final Path f = Path()
      ..moveTo(c.dx, c.dy - s * 0.42)
      ..quadraticBezierTo(c.dx + s * 0.34, c.dy, c.dx + s * 0.16, c.dy + s * 0.3)
      ..quadraticBezierTo(c.dx, c.dy + s * 0.46, c.dx - s * 0.16, c.dy + s * 0.3)
      ..quadraticBezierTo(c.dx - s * 0.34, c.dy, c.dx, c.dy - s * 0.42)
      ..close();
    canvas.drawPath(f, Paint()..color = const Color(0xFFFF7043));
  }

  // Clock — gold face + hands.
  void _emblemClock(Canvas canvas, Offset c, double s) {
    canvas.drawCircle(c, s * 0.4, Paint()..color = const Color(0xFFFFD700));
    canvas.drawCircle(
        c,
        s * 0.4,
        Paint()
          ..color = const Color(0xFF6D4C00)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    final Paint h = Paint()
      ..color = const Color(0xFF3E2723)
      ..strokeWidth = 1.5;
    canvas.drawLine(c, Offset(c.dx, c.dy - s * 0.26), h);
    canvas.drawLine(c, Offset(c.dx + s * 0.18, c.dy), h);
  }

  // Shield — badge silhouette.
  void _emblemShield(Canvas canvas, Offset c, double s) {
    final Path sh = Path()
      ..moveTo(c.dx, c.dy - s * 0.4)
      ..lineTo(c.dx + s * 0.34, c.dy - s * 0.24)
      ..lineTo(c.dx + s * 0.28, c.dy + s * 0.2)
      ..lineTo(c.dx, c.dy + s * 0.44)
      ..lineTo(c.dx - s * 0.28, c.dy + s * 0.2)
      ..lineTo(c.dx - s * 0.34, c.dy - s * 0.24)
      ..close();
    canvas.drawPath(sh, Paint()..color = const Color(0xFF42A5F5));
  }

  // Five-point star in [color].
  void _emblemStar(Canvas canvas, Offset c, double s, Color color) {
    final Path star = Path();
    for (int i = 0; i < 5; i++) {
      final double outer = -math.pi / 2 + i * 2 * math.pi / 5;
      final double inner = outer + math.pi / 5;
      final Offset po =
          Offset(c.dx + math.cos(outer) * s * 0.42, c.dy + math.sin(outer) * s * 0.42);
      final Offset pin =
          Offset(c.dx + math.cos(inner) * s * 0.18, c.dy + math.sin(inner) * s * 0.18);
      if (i == 0) {
        star.moveTo(po.dx, po.dy);
      } else {
        star.lineTo(po.dx, po.dy);
      }
      star.lineTo(pin.dx, pin.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = color);
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.archetype != archetype ||
      old.rareArchetype != rareArchetype ||
      old.carColorOverride != carColorOverride ||
      old.equippedCosmetic != equippedCosmetic ||
      old.bob != bob;
}

// ---------------------------------------------------------------------------
// AvatarWidget — wraps AvatarPainter in a convenient Widget
// ---------------------------------------------------------------------------

/// A chibi avatar Widget.
/// [size] is the long side (height). Width is 80% of height.
class AvatarWidget extends StatefulWidget {
  const AvatarWidget({
    super.key,
    required this.archetype,
    this.rareArchetype,
    this.size = 80.0,
    this.carColorOverride,
    this.equippedCosmetic,
    this.animate = true,
    this.tux = false,
  });

  final DrivingArchetype archetype;

  /// Creator easter egg — overrides everything with fedora'd Tux in a kart.
  final bool tux;

  /// When set, overrides [archetype] with a special rare look.
  final RareArchetype? rareArchetype;
  final double size;
  final Color? carColorOverride;

  /// The unlockable the user chose to display (null = none).
  final CosmeticId? equippedCosmetic;

  /// When true (default) the head gently bobs in a continuous loop.
  final bool animate;

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget>
    with SingleTickerProviderStateMixin {
  // One bob cycle ~1.1 s — a relaxed, musical bounce.
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _bob.repeat();
  }

  @override
  void didUpdateWidget(AvatarWidget old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_bob.isAnimating) {
      _bob.repeat();
    } else if (!widget.animate && _bob.isAnimating) {
      _bob.stop();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 0.80,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: AvatarPainter(
              archetype: widget.archetype,
              rareArchetype: widget.rareArchetype,
              carColorOverride: widget.carColorOverride,
              equippedCosmetic: widget.equippedCosmetic,
              bob: widget.animate ? _bob.value : 0.0,
              tux: widget.tux,
            ),
          );
        },
      ),
    );
  }
}
