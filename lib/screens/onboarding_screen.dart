// onboarding_screen.dart — Minimal first-run setup: name + car info, done.
// Full implementation is Phase 7; this stub collects nothing yet and simply
// forwards to the map so Phase 1 testing isn't blocked.

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import 'map_screen.dart';
import 'splash_screen.dart' show settingsKeyOnboardingComplete;

// --- SCREEN ---

/// First-run onboarding. Phase 7 adds the real form (name, make, model,
/// year, color); for now it's a pass-through so the map is reachable.
class OnboardingScreen extends StatelessWidget {
  /// Creates the onboarding screen.
  const OnboardingScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/onboarding';

  /// Marks onboarding complete and continues to the map.
  void _completeOnboarding(BuildContext context) {
    Hive.box<dynamic>(hiveBoxSettings)
        .put(settingsKeyOnboardingComplete, true);
    Navigator.of(context).pushReplacementNamed(MapScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                // Copy specified verbatim in PRODUCT_BRIEF Phase 7.
                'You can add more in Settings anytime — favorite places, '
                'route preferences, privacy options, and more.',
                textAlign: TextAlign.center,
              ),
            ),
            // TODO: [real onboarding form: name, car make/model/year/color]
            // [deferred to Phase 7 per the phase plan]
            ElevatedButton(
              onPressed: () => _completeOnboarding(context),
              child: const Text('Let\'s drive'),
            ),
          ],
        ),
      ),
    );
  }
}
