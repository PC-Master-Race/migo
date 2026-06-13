// settings_screen.dart — All user-facing toggles, grouped and labeled.
// Full implementation is Phase 7. The group skeleton exists now so other
// phases have a stable place to register their settings.

import 'package:flutter/material.dart';

// --- SCREEN ---

/// Settings, grouped per PRODUCT_BRIEF: route preferences, privacy, vehicle
/// profile, notifications, map preferences.
class SettingsScreen extends StatelessWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  /// Route name used in main.dart's route table.
  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const <Widget>[
          // TODO: [Route preferences group: fuel efficient, shortest, fastest,
          // fewest stops, avoid freeway/tolls/popular] [deferred to Phase 7]
          ListTile(title: Text('Route preferences'), enabled: false),
          // TODO: [Privacy group: ALPR avoidance, location sharing, family
          // group management, privacy windows] [deferred to Phase 7]
          ListTile(title: Text('Privacy'), enabled: false),
          // TODO: [Vehicle profile editor] [deferred to Phase 7]
          ListTile(title: Text('Vehicle profile'), enabled: false),
          // TODO: [Notification preferences] [deferred to Phase 7]
          ListTile(title: Text('Notifications'), enabled: false),
          // TODO: [Map preferences: offline cache radius, WiFi-only updates]
          // [deferred to Phase 7]
          ListTile(title: Text('Map preferences'), enabled: false),
        ],
      ),
    );
  }
}
