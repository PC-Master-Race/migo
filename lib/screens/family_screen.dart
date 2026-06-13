// family_screen.dart — Family group management and live family map.
// Phase 5 work: invite links/codes, real-time avatars, privacy windows.

import 'package:flutter/material.dart';

// --- SCREEN ---

/// Family location sharing (Life360-style, but privacy-first and opt-in).
class FamilyScreen extends StatelessWidget {
  /// Creates the family screen.
  const FamilyScreen({super.key});

  /// Route name for navigation pushes once Phase 5 wires this in.
  static const String routeName = '/family';

  @override
  Widget build(BuildContext context) {
    // TODO: [family groups: invite via link/code, member list, privacy
    // windows toggle, sharing on/off] [deferred to Phase 5 per the phase plan]
    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: const Center(child: Text('Family sharing arrives in Phase 5.')),
    );
  }
}
