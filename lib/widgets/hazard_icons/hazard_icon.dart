// hazard_icon.dart — Cartoon hazard marker widgets for the map.
// Each HazardType gets a distinctive color + icon combination so drivers
// can identify hazard type at a glance while moving.
// No external image assets needed — built entirely from Flutter widgets.
// TODO: [replace with custom hand-drawn cartoon SVG assets] [deferred to
// Phase 7 polish — requires a design/illustration pass]

import 'package:flutter/material.dart';

import '../../models/hazard_model.dart';
import '../../theme/bravo_theme.dart';

// --- SIZE CONSTANTS ---

/// Diameter of the hazard pin's colored circle on the map.
const double hazardIconSize = 36.0;

/// Size of the icon glyph inside the circle.
const double hazardGlyphSize = 20.0;

// --- WIDGET ---

/// A circular map pin for a hazard, color-coded and icon-coded by type.
/// Designed to be readable at a glance from driving speed.
class HazardIcon extends StatelessWidget {
  /// Creates a hazard icon for [type].
  /// [isOwn] dims the icon slightly for the user's own unconfirmed reports.
  const HazardIcon({
    super.key,
    required this.type,
    this.isOwn = false,
  });

  final HazardType type;

  /// True when this is the current user's own unconfirmed report — shown
  /// with reduced opacity to indicate "pending confirmation".
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final _HazardStyle style = _styleFor(type);

    return Opacity(
      opacity: isOwn ? 0.55 : 1.0,
      child: Container(
        width: hazardIconSize,
        height: hazardIconSize,
        decoration: BoxDecoration(
          color: style.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            style.icon,
            color: Colors.white,
            size: hazardGlyphSize,
          ),
        ),
      ),
    );
  }

  /// Returns the visual style config for each hazard type.
  static _HazardStyle _styleFor(HazardType type) {
    return switch (type) {
      HazardType.crash => const _HazardStyle(
          color: migoDanger,
          icon: Icons.car_crash_rounded,
        ),
      HazardType.alprCamera => const _HazardStyle(
          // Plum for ALPR — ominous/surveillance vibe, distinct from danger.
          color: migoPlum,
          icon: Icons.no_photography_rounded,
        ),
      HazardType.debris => const _HazardStyle(
          color: migoAmber,
          icon: Icons.warning_amber_rounded,
        ),
      HazardType.ice => const _HazardStyle(
          color: Color(0xFF81D4FA), // light blue — cold/ice feel
          icon: Icons.ac_unit_rounded,
        ),
      HazardType.construction => const _HazardStyle(
          color: Color(0xFFFFA726), // construction orange
          icon: Icons.construction_rounded,
        ),
      HazardType.speedTrap => const _HazardStyle(
          color: Color(0xFF1565C0), // police blue
          icon: Icons.local_police_rounded,
        ),
      HazardType.generalDisturbance => const _HazardStyle(
          color: migoCoral,
          icon: Icons.report_problem_rounded,
        ),
    };
  }

  /// Public accessor so the report sheet and alert banner can use the same
  /// color without duplicating the switch.
  static Color colorFor(HazardType type) => _styleFor(type).color;

  /// Public accessor for the icon glyph.
  static IconData iconFor(HazardType type) => _styleFor(type).icon;

  /// Human-readable label for each type — shown in the report sheet and banner.
  static String labelFor(HazardType type) {
    return switch (type) {
      HazardType.crash => 'Crash',
      HazardType.alprCamera => 'ALPR Camera',
      HazardType.debris => 'Debris',
      HazardType.ice => 'Ice / Road Hazard',
      HazardType.construction => 'Construction',
      HazardType.speedTrap => 'Speed Trap',
      HazardType.generalDisturbance => 'Disturbance',
    };
  }
}

// --- STYLE CONFIG ---

class _HazardStyle {
  const _HazardStyle({required this.color, required this.icon});
  final Color color;
  final IconData icon;
}
