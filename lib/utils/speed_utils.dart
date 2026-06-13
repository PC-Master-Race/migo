// speed_utils.dart — Speed conversion and smoothing helpers for the HUD.
// Pure functions only: no state, no I/O, fully unit-testable.

import '../constants.dart';

// --- CONVERSIONS ---

/// Converts a GPS speed in meters/second to miles/hour, with jitter
/// suppression: readings below [speedJitterFloorMph] return 0 so the HUD
/// doesn't flicker 1–2 mph while the user is standing still.
/// [metersPerSecond] is the raw value from the GPS fix; returns whole mph.
int gpsSpeedToDisplayMph(double metersPerSecond) {
  final double milesPerHour = metersPerSecond * metersPerSecondToMph;
  if (milesPerHour < speedJitterFloorMph) {
    return 0;
  }
  return milesPerHour.round();
}

/// Parses an OSM `maxspeed` tag value into a display string for the HUD.
/// OSM values vary wildly: "45", "45 mph", "70 km/h", "none", "walk".
/// [rawMaxspeedTag] is the tag value or null when missing; returns a clean
/// label, falling back to [speedLimitUnknownLabel] for anything unparseable.
String parseOsmMaxspeedTag(String? rawMaxspeedTag) {
  if (rawMaxspeedTag == null || rawMaxspeedTag.isEmpty) {
    return speedLimitUnknownLabel;
  }
  final String normalized = rawMaxspeedTag.trim().toLowerCase();

  // "45 mph" or bare "45" — US roads tag in mph; bare numbers in the US
  // dataset are mph by convention when the way is in the United States.
  final RegExp leadingNumber = RegExp(r'^(\d+)');
  final RegExpMatch? match = leadingNumber.firstMatch(normalized);
  if (match == null) {
    // Values like "none", "walk", "signals" — show as unknown rather than
    // confusing the driver with jargon.
    return speedLimitUnknownLabel;
  }

  final int numericValue = int.parse(match.group(1)!);
  if (normalized.contains('km/h') || normalized.contains('kmh')) {
    // Convert km/h to mph for a consistent US-facing HUD.
    const double kmhToMph = 0.621371; // exact conversion factor
    return '${(numericValue * kmhToMph).round()}';
  }
  return '$numericValue';
}
