// route_options_screen.dart — Mid-route toggles for route recalculation.
// Phase 2 work: every toggle here must trigger an instant recalculation.

import 'package:flutter/material.dart';

// --- SCREEN ---

/// Route option toggles (fastest, shortest, fuel efficient, fewest stops,
/// avoid freeways/tolls/popular routes, ALPR avoidance).
class RouteOptionsScreen extends StatelessWidget {
  /// Creates the route options screen.
  const RouteOptionsScreen({super.key});

  /// Route name for navigation pushes once Phase 2 wires this in.
  static const String routeName = '/route-options';

  @override
  Widget build(BuildContext context) {
    // TODO: [toggle list bound to RoutePreferences provider; any change
    // triggers instant recalculation] [deferred to Phase 2 with the routing
    // engine integration]
    return Scaffold(
      appBar: AppBar(title: const Text('Route options')),
      body: const Center(child: Text('Route options arrive in Phase 2.')),
    );
  }
}
