// supabase_service.dart — Every Supabase interaction funnels through here.
// One choke point makes the privacy guarantees auditable: if a data flow
// isn't in this file, it doesn't talk to the backend.

import 'package:supabase_flutter/supabase_flutter.dart';

// --- PROJECT CREDENTIALS ---
// The anon key is safe to ship in a client (it's public by design; row-level
// security is the real gate). Values are placeholders until the product
// owner's Supabase project is connected.
// TODO: [fill in real project URL + anon key] [deferred: product owner
// supplies credentials / deploys schema.sql via the Supabase SQL editor]

/// Supabase project URL. Placeholder until the real project is connected.
const String supabaseProjectUrl = 'https://YOUR-PROJECT.supabase.co';

/// Supabase anon (public) key. Placeholder — see TODO above.
const String supabaseAnonKey = 'YOUR-ANON-KEY';

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
