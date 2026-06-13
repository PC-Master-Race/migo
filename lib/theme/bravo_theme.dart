// bravo_theme.dart — Colors, fonts, and the cartoon style guide in code form.
// Single source of truth for Migo's warm, friendly visual identity. Every
// screen and widget pulls colors and text styles from here — never inline.

import 'package:flutter/material.dart';

// --- TYPOGRAPHY DECISION ---
// Evaluated (per PRODUCT_BRIEF): Nunito vs Fredoka One.
//   • Fredoka One ships a single weight (regular/display only). A navigation
//     HUD needs a full weight range for hierarchy (speed numbers vs labels).
//   • Nunito has 7+ weights, rounded terminals that match the cartoon style,
//     and excellent legibility at small sizes / at a glance while driving.
// CHOICE: Nunito for all UI text. Fredoka One may return later for logo
// lock-ups only.
// Fonts are BUNDLED locally (assets/fonts/) — the google_fonts package fetches
// from Google servers at runtime, which violates the no-Google-calls rule.
// TODO: [commit Nunito .ttf files + OFL license to assets/fonts/]
// [deferred: binary assets added separately; fontFamily falls back to system
// rounded font until then]

/// App-wide font family. Falls back to the platform default until the Nunito
/// files are bundled (see TODO above).
const String migoFontFamily = 'Nunito';

// --- COLOR PALETTE ---
// Warm and friendly per PRODUCT_BRIEF. No cold corporate blues or grays.

/// Primary brand color — warm coral. Buttons, active toggles, brand moments.
const Color migoCoral = Color(0xFFFF6B5E);

/// Secondary — sunny amber. Highlights, badges, gas-price markers.
const Color migoAmber = Color(0xFFFFB347);

/// Tertiary — soft teal. Route lines and confirmations; warm-leaning teal,
/// deliberately not a corporate blue.
const Color migoTeal = Color(0xFF4ECDC4);

/// Background — warm cream instead of stark white.
const Color migoCream = Color(0xFFFFF6E9);

/// Ink — warm dark brown for text instead of pure black.
const Color migoInk = Color(0xFF4A3F35);

/// Danger — used for urgent hazard alerts (crash). Warm red, high contrast.
const Color migoDanger = Color(0xFFE63946);

/// ALPR/privacy accent — muted plum for surveillance-related UI. Chosen to be
/// distinct from danger red: ALPR alerts are "ominous/subtle", not urgent.
const Color migoPlum = Color(0xFF6D4C7D);

// --- THEME BUILDER ---

/// Builds the app-wide [ThemeData] from the Migo palette and typography.
/// Returns a light theme; dark mode is a Phase 7 polish item.
/// TODO: [dark mode variant for night driving] [deferred to Phase 7 polish]
ThemeData buildBravoTheme() {
  final ColorScheme migoColorScheme = ColorScheme.fromSeed(
    seedColor: migoCoral,
    primary: migoCoral,
    secondary: migoAmber,
    tertiary: migoTeal,
    surface: migoCream,
    error: migoDanger,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: migoColorScheme,
    scaffoldBackgroundColor: migoCream,
    fontFamily: migoFontFamily,
    // Rounded shapes everywhere — part of the cartoon style guide.
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: migoCoral,
        foregroundColor: Colors.white,
      ),
    ),
  );
}
