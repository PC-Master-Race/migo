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
  });

  final Color carColor;
  final Color headColor;
  final _EyeStyle eyeStyle;
  final _MouthStyle mouthStyle;
  final _AccessoryType accessoryA;
  final _AccessoryType accessoryB;
  final Color? auraColor;
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
    carColor: Color(0xFF90A4AE), // steel blue-grey
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.neutral,
    accessoryA: _AccessoryType.readingGlasses,
    accessoryB: _AccessoryType.none,
  ),
  DrivingArchetype.rocket: _ArchetypeConfig(
    carColor: Color(0xFFE53935), // racing red
    headColor: Color(0xFFFFB74D),
    eyeStyle: _EyeStyle.wide,
    mouthStyle: _MouthStyle.grin,
    accessoryA: _AccessoryType.racingGoggles,
    accessoryB: _AccessoryType.spoiler,
    auraColor: Color(0x33FF5722),
  ),
  DrivingArchetype.ghost: _ArchetypeConfig(
    carColor: Color(0xFF4A148C), // deep purple
    headColor: Color(0xFFE1E1E1), // pale/ghostly
    eyeStyle: _EyeStyle.hollow,
    mouthStyle: _MouthStyle.ooo,
    accessoryA: _AccessoryType.none,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x44AB47BC),
  ),
  DrivingArchetype.scout: _ArchetypeConfig(
    carColor: Color(0xFF43A047), // forest green
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.happy,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.explorerHat,
    accessoryB: _AccessoryType.none,
  ),
  DrivingArchetype.phantom: _ArchetypeConfig(
    carColor: Color(0xFF263238), // near black
    headColor: Color(0xFFBDBDBD),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.smirk,
    accessoryA: _AccessoryType.fedora,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33546E7A),
  ),
  DrivingArchetype.zenMaster: _ArchetypeConfig(
    carColor: Color(0xFF80DEEA), // soft teal
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.closed,
    mouthStyle: _MouthStyle.smile,
    accessoryA: _AccessoryType.zenHalo,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x2200BCD4),
  ),
  DrivingArchetype.chaosAgent: _ArchetypeConfig(
    carColor: Color(0xFFFF6F00), // amber orange
    headColor: Color(0xFFFFB74D),
    eyeStyle: _EyeStyle.wide,
    mouthStyle: _MouthStyle.ooo,
    accessoryA: _AccessoryType.coffeeX3,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x33FF6F00),
  ),
  DrivingArchetype.nightOwl: _ArchetypeConfig(
    carColor: Color(0xFF1A237E), // midnight blue
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.sleepy,
    mouthStyle: _MouthStyle.neutral,
    accessoryA: _AccessoryType.nightCap,
    accessoryB: _AccessoryType.none,
    auraColor: Color(0x221A237E),
  ),
  DrivingArchetype.streetRat: _ArchetypeConfig(
    carColor: Color(0xFF757575), // urban grey
    headColor: Color(0xFFFFCC99),
    eyeStyle: _EyeStyle.squint,
    mouthStyle: _MouthStyle.smirk,
    accessoryA: _AccessoryType.hoodie,
    accessoryB: _AccessoryType.none,
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
/// [earnedAccessory] is an optional POI-earned cosmetic painted on top.
class AvatarPainter extends CustomPainter {
  const AvatarPainter({
    required this.archetype,
    this.rareArchetype,
    this.carColorOverride,
    this.earnedAccessory,
    this.showAura = true,
  });

  final DrivingArchetype archetype;

  /// When set, overrides [archetype] with a special rare look.
  final RareArchetype? rareArchetype;
  final Color? carColorOverride;
  final _AccessoryType? earnedAccessory;
  final bool showAura;

  @override
  void paint(Canvas canvas, Size size) {
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

    // ── 2. Car body ───────────────────────────────────────────────────────
    final Color carColor = carColorOverride ?? cfg.carColor;
    _drawCar(canvas, size, carColor, cfg.accessoryB == _AccessoryType.spoiler);

    // ── 3. Head ───────────────────────────────────────────────────────────
    final double headRadius = w * 0.36; // ~23px on 64px canvas
    final Offset headCenter = Offset(cx, h * 0.38);
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

    // ── 7. Earned POI overlay ─────────────────────────────────────────────
    if (earnedAccessory != null &&
        earnedAccessory != _AccessoryType.none &&
        earnedAccessory != cfg.accessoryA) {
      _drawAccessoryA(canvas, headCenter, headRadius, earnedAccessory!);
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
    // Hood behind head
    final Paint hoodPaint = Paint()..color = const Color(0xFF616161);
    canvas.drawCircle(head, r * 1.10, hoodPaint);
    canvas.drawCircle(head, r, Paint()..color = _kConfigs[archetype]!.headColor);
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

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.archetype != archetype ||
      old.rareArchetype != rareArchetype ||
      old.carColorOverride != carColorOverride ||
      old.earnedAccessory != earnedAccessory;
}

// ---------------------------------------------------------------------------
// AvatarWidget — wraps AvatarPainter in a convenient Widget
// ---------------------------------------------------------------------------

/// A chibi avatar Widget.
/// [size] is the long side (height). Width is 80% of height.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    required this.archetype,
    this.rareArchetype,
    this.size = 80.0,
    this.carColorOverride,
    this.earnedAccessory,
  });

  final DrivingArchetype archetype;

  /// When set, overrides [archetype] with a special rare look.
  final RareArchetype? rareArchetype;
  final double size;
  final Color? carColorOverride;
  final _AccessoryType? earnedAccessory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.80,
      height: size,
      child: CustomPaint(
        painter: AvatarPainter(
          archetype: archetype,
          rareArchetype: rareArchetype,
          carColorOverride: carColorOverride,
          earnedAccessory: earnedAccessory,
        ),
      ),
    );
  }
}
