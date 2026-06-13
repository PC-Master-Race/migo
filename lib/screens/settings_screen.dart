// settings_screen.dart — Full settings UI for Bravo Maps.
// Dark theme, ConsumerStatefulWidget for live provider reads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import '../theme/bravo_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/map_provider.dart';

const Color _bg     = Color(0xFF0D0D1A);
const Color _card   = Color(0xFF161625);
const Color _divider = Color(0xFF252535);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  static const String routeName = '/settings';
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameCtrl;

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
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
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
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12,
                        fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 24,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Your nickname',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.07),
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
          _sectionHeader('Privacy'),
          _card(<Widget>[
            _ToggleTile(
              icon: Icons.camera_alt_outlined,
              iconColor: migoAmber,
              title: 'ALPR camera avoidance',
              subtitle: 'Reroutes around known licence-plate reader locations.',
              provider: alprAvoidanceEnabledProvider,
            ),
            _dividerLine,
            _ToggleTile(
              icon: Icons.people_alt_outlined,
              iconColor: migoTeal,
              title: 'Share location with family',
              subtitle: 'Visible only to your family group. Stored in your Supabase account.',
              provider: locationSharingEnabledProvider,
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
              provider: ttsEnabledProvider,
            ),
            _dividerLine,
            _ToggleTile(
              icon: Icons.warning_amber_rounded,
              iconColor: migoAmber,
              title: 'Hazard alerts',
              subtitle: 'Audio + visual alerts for reported hazards ahead.',
              provider: hazardAlertsEnabledProvider,
            ),
            _dividerLine,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Default route preference',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _ChipRow<MapZoomMode>(
                  values: MapZoomMode.values,
                  current: ref.watch(defaultZoomModeProvider),
                  label: (MapZoomMode v) => v.name[0].toUpperCase() + v.name.substring(1),
                  onSelect: (MapZoomMode v) => ref.read(defaultZoomModeProvider.notifier).set(v),
                ),
              ]),
            ),
            _dividerLine,
            _ToggleTile(
              icon: Icons.wifi_rounded,
              iconColor: migoTeal,
              title: 'WiFi-only tile sync',
              subtitle: 'Downloads map tiles only on WiFi to save mobile data.',
              provider: wifiOnlyTileSyncProvider,
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
              provider: gasLayerEnabledProvider,
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader('About'),
          _card(<Widget>[
            _InfoTile(label: 'Version', value: '0.7.0-alpha'),
            _dividerLine,
            _InfoTile(label: 'Privacy policy', value: 'bravomaps.com/privacy'),
            _dividerLine,
            _InfoTile(label: 'Open source licenses', value: ''),
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
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Column(children: children),
    );
  }

  static const Widget _dividerLine = Divider(height: 1, thickness: 1, color: _divider, indent: 16);
}

// ---------------------------------------------------------------------------
// Reusable tiles
// ---------------------------------------------------------------------------

class _ToggleTile extends ConsumerWidget {
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.provider,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final StateNotifierProvider<ToggleNotifier, bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool value = ref.watch(provider);
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.4)),
      trailing: Switch(
        value: value,
        onChanged: (_) => ref.read(provider.notifier).toggle(),
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
    return Wrap(
      spacing: 8,
      children: values.map((T v) {
        final bool selected = v == current;
        return ChoiceChip(
          label: Text(label(v)),
          selected: selected,
          onSelected: (_) => onSelect(v),
          selectedColor: migoCoral,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.65),
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
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: value.isEmpty
          ? const Icon(Icons.chevron_right_rounded, color: Colors.white38)
          : Text(value, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }
}
