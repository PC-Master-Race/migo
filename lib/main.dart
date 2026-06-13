// main.dart — Migo app entry point.
// Boots local storage and Supabase, installs the Riverpod scope, applies the
// Migo theme, and defines top-level navigation routes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'constants.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/supabase_service.dart';
import 'theme/migo_theme.dart';

// --- BOOTSTRAP ---

/// App entry point. Initializes storage and backend before the first frame:
/// Hive must be open before any service reads settings, and Supabase must be
/// initialized before auth state can be checked.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local storage first — cheap, synchronous-ish, needed by everything.
  await Hive.initFlutter();
  await Hive.openBox<dynamic>(hiveBoxSettings);
  await Hive.openBox<dynamic>(hiveBoxTileMetadata);

  // Backend second — safe to call offline; Supabase queues until reachable.
  await SupabaseService.initialize();

  runApp(const ProviderScope(child: MigoApp()));
}

// --- APP SHELL ---

/// Root widget: theme + route table. Kept deliberately thin; all real logic
/// lives in screens and services.
class MigoApp extends StatelessWidget {
  /// Creates the root app widget.
  const MigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Migo',
      theme: buildMigoTheme(),
      debugShowCheckedModeBanner: false,
      initialRoute: SplashScreen.routeName,
      routes: <String, WidgetBuilder>{
        SplashScreen.routeName: (BuildContext context) => const SplashScreen(),
        OnboardingScreen.routeName: (BuildContext context) =>
            const OnboardingScreen(),
        MapScreen.routeName: (BuildContext context) => const MapScreen(),
        SettingsScreen.routeName: (BuildContext context) =>
            const SettingsScreen(),
      },
    );
  }
}
