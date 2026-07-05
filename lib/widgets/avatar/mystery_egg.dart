// mystery_egg.dart — The pre-reveal starter avatar: an egg with racing
// stripes, gently rocking, with curious eyes peeking through a crack.
//
// New users' avatars are NOT assigned — they hatch. Until the user completes
// [archetypeRevealSessionCount] driving sessions, this egg is what shows on
// the map, making the onboarding promise ("Drive to discover your avatar")
// literally true, and keeping prestige archetypes like Zen Master earned-only.
//
// Code-drawn like every other avatar (CustomPainter, no image assets).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/bravo_theme.dart';

/// The mystery egg avatar. [size] is the height; width is 80% of height
/// (matches AvatarWidget's aspect so it drops into the same Marker box).
class MysteryEggWidget extends StatefulWidget {
  const MysteryEggWidget({super.key, this.size = 80.0, this.animate = true});

  final double size;

  /// When true (default) the egg rocks side to side in a continuous loop.
  final bool animate;

  @override
  State<MysteryEggWidget> createState() => _MysteryEggWidgetState();
}

class _MysteryEggWidgetState extends State<MysteryEggWidget>
    with SingleTickerProviderStateMixin {
  // One rock cycle ~1.4 s — slightly slower than the avatar bob; eggs are shy.
  late final AnimationController _rock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _rock.repeat();
  }

  @override
  void dispose() {
    _rock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 0.80,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _rock,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: MysteryEggPainter(
              rock: widget.animate ? _rock.value : 0.0,
            ),
          );
        },
      ),
    );
  }
}

/// Public so the MapLibre view can render the egg to a symbol image too.
class MysteryEggPainter extends CustomPainter {
  const MysteryEggPainter({required this.rock});

  /// Animation phase 0..1 — drives the rocking tilt.
  final double rock;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Ground shadow (does not rock — the egg rocks above it).
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.93),
          width: w * 0.62,
          height: h * 0.08),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    // Rock the whole egg around its base contact point.
    final double tilt = math.sin(rock * 2 * math.pi) * 0.07; // ±4°
    canvas.save();
    canvas.translate(w * 0.5, h * 0.90);
    canvas.rotate(tilt);
    canvas.translate(-w * 0.5, -h * 0.90);

    // --- Egg shell ---
    final Rect eggRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.50),
        width: w * 0.74,
        height: h * 0.82);
    final Path egg = Path()..addOval(eggRect);
    canvas.drawPath(egg, Paint()..color = const Color(0xFFF6EFE3));
    // Soft bottom shading so it reads as 3D.
    canvas.save();
    canvas.clipPath(egg);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.78),
          width: w * 0.9,
          height: h * 0.5),
      Paint()..color = const Color(0xFFE4D9C6),
    );

    // --- Racing stripes (still clipped to the shell) ---
    final Paint stripe = Paint()..color = migoCoral;
    canvas.drawRect(
        Rect.fromLTWH(w * 0.38, eggRect.top, w * 0.085, eggRect.height),
        stripe);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.53, eggRect.top, w * 0.085, eggRect.height),
        stripe);
    canvas.restore(); // end shell clip

    // Shell outline.
    canvas.drawPath(
      egg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.02)
        ..color = const Color(0xFF3A3344).withValues(alpha: 0.55),
    );

    // --- Crack with peeking eyes ---
    // A jagged opening just left of the stripes so the eyes aren't covered.
    final double cx = w * 0.30;
    final double cy = h * 0.42;
    final Path crack = Path()
      ..moveTo(cx - w * 0.11, cy)
      ..lineTo(cx - w * 0.055, cy - h * 0.055)
      ..lineTo(cx - w * 0.01, cy - h * 0.02)
      ..lineTo(cx + w * 0.045, cy - h * 0.06)
      ..lineTo(cx + w * 0.10, cy - h * 0.005)
      ..lineTo(cx + w * 0.075, cy + h * 0.055)
      ..lineTo(cx - w * 0.06, cy + h * 0.06)
      ..close();
    canvas.drawPath(crack, Paint()..color = const Color(0xFF2A2233));

    // Two round white eyes peeking out of the dark.
    final double eyeR = w * 0.030;
    for (final double ex in <double>[cx - w * 0.038, cx + w * 0.038]) {
      canvas.drawCircle(
          Offset(ex, cy), eyeR, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(ex + eyeR * 0.25, cy + eyeR * 0.15),
          eyeR * 0.45, Paint()..color = const Color(0xFF2A2233));
    }

    // Hairline fracture lines spreading from the hole — reads as "hatching"
    // even at small map sizes.
    final Paint crackLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.014)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF3A3344).withValues(alpha: 0.75);
    final Path fracture1 = Path()
      ..moveTo(cx + w * 0.10, cy - h * 0.005)
      ..lineTo(cx + w * 0.165, cy - h * 0.03)
      ..lineTo(cx + w * 0.21, cy - h * 0.012)
      ..lineTo(cx + w * 0.265, cy - h * 0.04);
    canvas.drawPath(fracture1, crackLine);
    final Path fracture2 = Path()
      ..moveTo(cx - w * 0.06, cy + h * 0.06)
      ..lineTo(cx - w * 0.09, cy + h * 0.095)
      ..lineTo(cx - w * 0.055, cy + h * 0.12);
    canvas.drawPath(fracture2, crackLine);
    // A lone crack on the far side of the shell — it's coming apart soon.
    final Path fracture3 = Path()
      ..moveTo(w * 0.68, h * 0.28)
      ..lineTo(w * 0.72, h * 0.315)
      ..lineTo(w * 0.69, h * 0.35);
    canvas.drawPath(fracture3, crackLine);

    // --- Wheels (a car in the making) ---
    final Paint tire = Paint()..color = const Color(0xFF3A3A44);
    final Paint hub = Paint()..color = const Color(0xFF8B8B98);
    for (final double wx in <double>[w * 0.30, w * 0.70]) {
      canvas.drawCircle(Offset(wx, h * 0.88), w * 0.085, tire);
      canvas.drawCircle(Offset(wx, h * 0.88), w * 0.038, hub);
    }

    canvas.restore(); // end rock transform

    // --- Floating "?" (counter-bobs, outside the rock transform) ---
    final double qLift = math.sin(rock * 2 * math.pi + math.pi) * h * 0.015;
    final TextPainter q = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: migoCoral,
          fontSize: h * 0.16,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    q.paint(canvas, Offset(w * 0.72, h * 0.02 + qLift));
  }

  @override
  bool shouldRepaint(MysteryEggPainter old) => old.rock != rock;
}
