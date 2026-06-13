// splash_screen.dart — First screen the user sees. Shows Bravo Maps branding while
// the app decides whether to send them to onboarding or straight to the map.

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import '../theme/bravo_theme.dart';
import 'map_screen.dart';
import 'onboarding_screen.dart';

// --- LOCAL CONSTANTS ---

/// How long the splash lingers before routing on. Long enough to register the
/// brand, short enough to never feel like a loading screen.
const Duration splashDisplayDuration = Duration(milliseconds: 1500);

/// Settings key: set true once onboarding completes.
const String settingsKeyOnboardingComplete = 'onboarding_complete';

// --- SCREEN ---

/// Branded splash that routes to onboarding (first run) or the map.
class SplashScreen extends StatefulWidget {
  /// Creates the splash screen.
  const SplashScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeAfterDelay();
  }

  /// Waits [splashDisplayDuration], then routes to onboarding on first launch
  /// or the map on every launch after that.
  Future<void> _routeAfterDelay() async {
    await Future<void>.delayed(splashDisplayDuration);
    if (!mounted) {
      return;
    }
    final Box<dynamic> settings = Hive.box<dynamic>(hiveBoxSettings);
    final bool onboardingDone =
        settings.get(settingsKeyOnboardingComplete, defaultValue: false) as bool;
    final String nextRoute =
        onboardingDone ? MapScreen.routeName : OnboardingScreen.routeName;
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: migoCoral,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // TODO: [replace with the Bravo Maps cartoon mascot asset]
            // [deferred: avatar art assets are produced in Phase 4/7]
            const Icon(Icons.navigation_rounded, size: 96, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Bravo Maps',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Navigation that minds its own business.',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
