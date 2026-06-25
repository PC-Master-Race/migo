// settings_screen.dart — Full settings UI for Migo.
// Theme-aware (light/dark), ConsumerStatefulWidget for live provider reads.
// All surface/text colors derive from the active ThemeData so the screen
// flips correctly with the Appearance setting — no hardcoded white-on-white.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../theme/bravo_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/gas_poi_provider.dart';
import '../providers/alpr_provider.dart'; // alprServiceProvider
import '../providers/location_provider.dart'; // positionStreamProvider
import '../services/alpr_service.dart'; // AlprImportResult
import '../services/map_service.dart'; // MapZoomMode

// --- THEME-AWARE PALETTE HELPERS ---
// Derive every surface/text color from the active theme so the screen reads
// correctly in both light and dark mode.

bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color _bgFor(BuildContext c) => _isDark(c) ? migoDarkBg : migoCream;
Color _cardFor(BuildContext c) => _isDark(c) ? migoDarkSurface : Colors.white;
Color _inkFor(BuildContext c) => Theme.of(c).colorScheme.onSurface;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  static const String routeName = '/settings';
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameCtrl;

  /// True while the one-time OSM camera import is running.
  bool _syncing = false;

  /// Pulls every known ALPR camera around the user's current location into the
  /// Supabase DB (one-time bulk import). After this, the map layer and routing
  /// read cameras straight from the DB — no live Overpass at drive time.
  Future<void> _syncCameras() async {
    final dynamic pos = ref.read(positionStreamProvider).valueOrNull;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Waiting for a GPS fix — try again in a moment.'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _syncing = true);
    final AlprImportResult result =
        await ref.read(alprServiceProvider).importOsmAlprForRegion(
              LatLng(pos.latitude as double, pos.longitude as double),
            );
    if (!mounted) return;
    setState(() => _syncing = false);

    final String message;
    if (result.error != null) {
      message = result.error!;
    } else if (result.added > 0) {
      message = 'Synced ${result.added} cameras for your area.';
    } else if (result.fetched > 0) {
      message = 'Already up to date (${result.fetched} cameras already in DB).';
    } else {
      message = 'No cameras found for this area.';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  void initState() {
    super.initState();
    final String savedName =
        Hive.box<dynamic>(hiveBoxSettings).get('display_name', defaultValue: '') as String;
    _nameCtrl = TextEditingController(text: savedName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    final String name = _nameCtrl.text.trim();
    Hive.box<dynamic>(hiveBoxSettings).put('display_name', name);
    ref.read(displayNameProvider.notifier).set(name);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name saved'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final Color ink = _inkFor(context);
    final Color bg = _bgFor(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings',
            style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: <Widget>[
          _sectionHeader('Account'),
          _card(<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Display name',
                    style: TextStyle(color: ink.withValues(alpha: 0.55), fontSize: 12,
                        fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 24,
                      style: TextStyle(color: ink, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Your nickname',
                        hintStyle: TextStyle(color: ink.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: ink.withValues(alpha: 0.07),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _saveName,
                    child: const Text('Save', style: TextStyle(color: migoCoral, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('Appearance'),
          _card(<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Theme',
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _ChipRow<ThemeMode>(
                  values: const <ThemeMode>[
                    ThemeMode.system,
                    ThemeMode.light,
                    ThemeMode.dark,
                  ],
                  current: ref.watch(themeModeProvider),
                  label: (ThemeMode m) => switch (m) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                  onSelect: (ThemeMode m) =>
                      ref.read(themeModeProvider.notifier).set(m),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('Privacy'),
          _card(<Widget>[
            _ToggleTile(
              icon: Icons.camera_alt_outlined,
              iconColor: migoAmber,
              title: 'ALPR camera avoidance',
              subtitle: 'Reroutes around known licence-plate reader locations.',
              value: ref.watch(alprAvoidanceEnabledProvider),
              onToggle: () => ref.read(alprAvoidanceEnabledProvider.notifier).toggle(),
            ),
            _dividerLine(context),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: migoCoral.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9)),
                child: _syncing
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: migoCoral))
                    : const Icon(Icons.cloud_download_outlined,
                        color: migoCoral, size: 18),
              ),
              title: Text('Sync cameras for my area',
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  _syncing
                      ? 'Downloading known cameras nearby…'
                      : 'One-time download of known ALPR cameras near you.',
                  style: TextStyle(color: ink.withValues(alpha: 0.5), fontSize: 12, height: 1.4)),
              trailing: _syncing
                  ? null
                  : Icon(Icons.chevron_right_rounded, color: ink.withValues(alpha: 0.3)),
              onTap: _syncing ? null : _syncCameras,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            _dividerLine(context),
            _ToggleTile(
              icon: Icons.people_alt_outlined,
              iconColor: migoTeal,
              title: 'Share location with family',
              subtitle: 'Visible only to your family group. Stored in your Supabase account.',
              value: ref.watch(locationSharingEnabledProvider),
              onToggle: () => ref.read(locationSharingEnabledProvider.notifier).toggle(),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('Navigation'),
          _card(<Widget>[
            _ToggleTile(
              icon: Icons.record_voice_over_outlined,
              iconColor: migoTeal,
              title: 'Voice guidance',
              subtitle: 'Turn-by-turn spoken directions.',
              value: ref.watch(ttsEnabledProvider),
              onToggle: () => ref.read(ttsEnabledProvider.notifier).toggle(),
            ),
            _dividerLine(context),
            _ToggleTile(
              icon: Icons.warning_amber_rounded,
              iconColor: migoAmber,
              title: 'Hazard alerts',
              subtitle: 'Audio + visual alerts for reported hazards ahead.',
              value: ref.watch(hazardAlertsEnabledProvider),
              onToggle: () => ref.read(hazardAlertsEnabledProvider.notifier).toggle(),
            ),
            _dividerLine(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Default route preference',
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _ChipRow<RoutePreference>(
                  values: RoutePreference.values,
                  current: ref.watch(routePreferenceProvider),
                  label: (RoutePreference v) => v.label,
                  onSelect: (RoutePreference v) => ref.read(routePreferenceProvider.notifier).set(v),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('Map'),
          _card(<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Default zoom mode',
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _ChipRow<MapZoomMode>(
                  // Street/satellite mode is disabled for now (see
                  // MapService.zoomModeForLevel) — only offer cartoon + hybrid.
                  values: MapZoomMode.values
                      .where((MapZoomMode m) => m != MapZoomMode.street)
                      .toList(),
                  current: ref.watch(defaultZoomModeProvider),
                  label: (MapZoomMode v) => v.name[0].toUpperCase() + v.name.substring(1),
                  onSelect: (MapZoomMode v) => ref.read(defaultZoomModeProvider.notifier).set(v),
                ),
              ]),
            ),
            _dividerLine(context),
            _ToggleTile(
              icon: Icons.wifi_rounded,
              iconColor: migoTeal,
              title: 'WiFi-only tile sync',
              subtitle: 'Downloads map tiles only on WiFi to save mobile data.',
              value: ref.watch(wifiOnlyTileSyncProvider),
              onToggle: () => ref.read(wifiOnlyTileSyncProvider.notifier).toggle(),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('Gas & Places'),
          _card(<Widget>[
            _ToggleTile(
              icon: Icons.local_gas_station_rounded,
              iconColor: migoAmber,
              title: 'Show gas stations',
              subtitle: 'Community-reported prices near your route.',
              value: ref.watch(gasLayerEnabledProvider),
              onToggle: () => ref.read(gasLayerEnabledProvider.notifier).state = !ref.read(gasLayerEnabledProvider),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('About'),
          _card(<Widget>[
            const _InfoTile(label: 'Version', value: '0.7.0-alpha'),
            _dividerLine(context),
            const _InfoTile(label: 'Privacy policy', value: 'bravomaps.com/privacy'),
            _dividerLine(context),
            const _InfoTile(label: 'Open source licenses', value: ''),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: _inkFor(context).withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: _cardFor(context), borderRadius: BorderRadius.circular(14)),
      child: Column(children: children),
    );
  }

  Widget _dividerLine(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: _inkFor(context).withValues(alpha: 0.08),
        indent: 16,
      );
}

// ---------------------------------------------------------------------------
// Reusable tiles — each reads Theme.of(context) so colors flip with the theme.
// ---------------------------------------------------------------------------

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onToggle,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Color ink = _inkFor(context);
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: ink.withValues(alpha: 0.5), fontSize: 12, height: 1.4)),
      trailing: Switch(
        value: value,
        onChanged: (_) => onToggle(),
        activeColor: migoCoral,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.current,
    required this.label,
    required this.onSelect,
  });
  final List<T> values;
  final T current;
  final String Function(T) label;
  final void Function(T) onSelect;

  @override
  Widget build(BuildContext context) {
    final bool dark = _isDark(context);
    final Color ink = _inkFor(context);
    return Wrap(
      spacing: 8,
      children: values.map((T v) {
        final bool selected = v == current;
        return ChoiceChip(
          label: Text(label(v)),
          selected: selected,
          onSelected: (_) => onSelect(v),
          selectedColor: migoCoral,
          // Solid opaque background + no M3 surface tint so the chip can never
          // pick up an unexpected surface color (the old white-on-white bug).
          backgroundColor: dark ? const Color(0xFF2A2A3A) : const Color(0xFFEDE2D2),
          surfaceTintColor: Colors.transparent,
          showCheckmark: false,
          labelStyle: TextStyle(
              color: selected ? Colors.white : ink.withValues(alpha: 0.7),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12),
          side: BorderSide.none,
        );
      }).toList(),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Color ink = _inkFor(context);
    return ListTile(
      title: Text(label, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: value.isEmpty
          ? Icon(Icons.chevron_right_rounded, color: ink.withValues(alpha: 0.3))
          : Text(value, style: TextStyle(color: ink.withValues(alpha: 0.45), fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }
}
