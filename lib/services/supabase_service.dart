// supabase_service.dart — Every Supabase interaction funnels through here.
// One choke point makes the privacy guarantees auditable: if a data flow
// isn't in this file, it doesn't talk to the backend.

import 'package:supabase_flutter/supabase_flutter.dart';

// --- PROJECT CREDENTIALS ---
// Credentials are supplied at RUN/BUILD time via --dart-define, NOT hard-coded.
// This repo is public, so nothing secret is committed: the defaults below are
// harmless placeholders, and the real values live only in your local command.
//
// Run the app like this (PowerShell — one line):
//   flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_xxx
//
// Even though the Supabase publishable/anon key is designed to be exposed in a
// client (Row Level Security is the real gate), keeping it out of a PUBLIC repo
// is good hygiene — a leaked key plus any RLS gap is a bad combination.
//
// String.fromEnvironment reads the --dart-define value at compile time; when
// it's absent the app falls back to the placeholder and runs in offline mode.

/// Supabase project URL. Provided via --dart-define=SUPABASE_URL=...
/// Falls back to a placeholder (→ offline mode) when not supplied.
const String supabaseProjectUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://YOUR-PROJECT.supabase.co',
);

/// Supabase publishable/anon key. Provided via --dart-define=SUPABASE_KEY=...
/// Falls back to a placeholder (→ offline mode) when not supplied.
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'YOUR-ANON-KEY',
);

// --- SERVICE ---

/// Static facade over the Supabase client. All reads/writes to the backend
/// go through methods on this class — never call Supabase.instance directly
/// from screens or other services.
class SupabaseService {
  SupabaseService._(); // No instances; this is a static facade.

  /// True once [initialize] has run with real (non-placeholder) credentials.
  /// Other code checks this so the app works fully offline / pre-backend.
  static bool isConnected = false;

  /// Initializes the Supabase client. Safe to call with placeholder
  /// credentials: the app simply runs in offline mode until they're real.
  static Future<void> initialize() async {
    final bool credentialsAreaPlaceholder =
        supabaseProjectUrl.contains('YOUR-PROJECT');
    if (credentialsAreaPlaceholder) {
      // Offline/dev mode — map and GPS work fine without a backend.
      isConnected = false;
      return;
    }
    await Supabase.initialize(url: supabaseProjectUrl, anonKey: supabaseAnonKey);
    isConnected = true;
  }

  /// The active client. Only valid when [isConnected] is true.
  static SupabaseClient get client => Supabase.instance.client;

  /// Signs in anonymously so RLS policies have an auth.uid() to key on.
  /// Real email/social auth is wired in alongside onboarding (Phase 7).
  static Future<void> signInAnonymously() async {
    if (!isConnected) {
      return; // Offline mode: nothing to sign in to.
    }
    final Session? existingSession = client.auth.currentSession;
    if (existingSession == null) {
      await client.auth.signInAnonymously();
    }
  }

  // TODO: [typed table accessors (users, vehicles, hazards, ...) added as
  // each phase needs them] [deferred: keeps this file honest — no dead code]
}
