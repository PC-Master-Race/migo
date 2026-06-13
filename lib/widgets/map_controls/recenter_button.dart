// recenter_button.dart — Floating button that snaps the camera back to the
// user's position and re-enables follow mode after manual panning.

import 'package:flutter/material.dart';

import '../../theme/migo_theme.dart';

// --- WIDGET ---

/// Recenter control shown when the user has panned away from their position.
class RecenterButton extends StatelessWidget {
  /// Creates the recenter button. [onPressed] re-enables follow mode.
  const RecenterButton({required this.onPressed, super.key});

  /// Called when tapped; map_screen recenters and resumes following.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: migoTeal,
      foregroundColor: Colors.white,
      child: const Icon(Icons.my_location_rounded),
    );
  }
}
