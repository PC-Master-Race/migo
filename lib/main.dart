// main.dart — Migo app entry point.
// Boots local storage and Supabase, installs the Riverpod scope, applies the
// Migo theme, and defines top-level navigation routes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'constants.dart';
import 'screens/family_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/route_options_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/supabase_service.dart';
import 'services/bravo_service.dart';
import 'services/tts_service.dart';
import 'theme/bravo_theme.dart';

// --- BOOTSTRAP ---

/// App entry point. Initializes storage and backend before the first frame.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local storage first — cheap, synchronous-ish, needed by everything.
  await Hive.initFlutter();
  await Hive.openBox<dynamic>(hiveBoxSettings);
  await Hive.openBox<dynamic>(hiveBoxTileMetadata);

  // Backend second — safe to call offline; Supabase queues until reachable.
  await SupabaseService.initialize();

  // Init BravoService — loads already-earned achievements so we don't re-award.
  final String? uid = SupabaseService.client.auth.currentSession?.user.id;
  if (uid != null) unawaited(BravoService.instance.init(uid));

  // Warm up the TTS singleton so the first navigation instruction has no
  // perceptible delay. Fire-and-forget; errors inside TtsService are silent.
  unawaited(TtsService.instance());

  runApp(const ProviderScope(child: BravoMapsApp()));
}

/// Discards a [Future] intentionally — suppresses the unawaited-future lint
/// for known fire-and-forget calls at startup.
void unawaited(Future<void> future) {}

// --- APP SHELL ---

/// Root widget: theme + route table.
class BravoMapsApp extends StatelessWidget {
  /// Creates the root app widget.
  const BravoMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bravo Maps',
      theme: buildBravoTheme(),
      debugShowCheckedModeBanner: false,
      initialRoute: SplashScreen.routeName,
      routes: <String, WidgetBuilder>{
        SplashScreen.routeName: (_) => const SplashScreen(),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        MapScreen.routeName: (_) => const MapScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
        // RouteOptionsScreen is normally opened as a bottom sheet from
        // map_screen (RouteOptionsScreen.showSheet), but a named route
        // is registered here for deep-link / testing access.
        RouteOptionsScreen.routeName: (_) => const RouteOp