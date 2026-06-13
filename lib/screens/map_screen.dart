// map_screen.dart — The main navigation screen: live map, user location,
// zoom-mode switching, and the speed HUD. Placeholder during scaffold;
// implemented in the map-rendering step of Phase 1.

import 'package:flutter/material.dart';

// --- SCREEN ---

/// Main map screen. Placeholder — replaced by the flutter_map implementation
/// in the next Phase 1 commit.
class MapScreen extends StatelessWidget {
  /// Creates the map screen.
  const MapScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/map';

  @override
  Widget build(BuildContext context) {
    // TODO: [flutter_map with OSM tiles, follow-user camera, zoom modes,
    // speed HUD] [implemented in the next commit of this same session]
    return const Scaffold(body: Center(child: Text('Map loading…')));
  }
}
