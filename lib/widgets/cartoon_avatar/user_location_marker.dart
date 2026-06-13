// user_location_marker.dart — The user's own marker on the map.
// Placeholder dot until Phase 4 replaces it with the archetype cartoon car
// avatar painted in the user's real car color.

import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../theme/bravo_theme.dart';

// --- WIDGET ---

/// The user's position marker.
/// TODO: [replace with the cartoon car avatar: archetype body shape +
/// real car color + heading rotation] [deferred to Phase 4 avatar system]
class UserLocationMarker extends StatelessWidget {
  /// Creates the user marker.
  const UserLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: userMarkerSize,
      height: userMarkerSize,
      decoration: BoxDecoration(
        color: migoCoral,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const <BoxShadow>[
          BoxShadow(blurRadius: 6, color: Colors.black26),
        ],
      ),
    );
  }
}
