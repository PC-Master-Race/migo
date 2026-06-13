// settings_screen.dart — All user-facing toggles, grouped and labeled.
// Phase 7 full implementation: account, privacy, navigation, map, gas/POI,
// Bravos & achievements, and about.
//
// Dark theme (#0D0D1A) consistent with family_screen and other overlays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/archetype_model.dart';
import '../models/poi_model.dart';
import '../providers/archetype_provider.dart';
import '../providers/gas_poi_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/supabase_service.dart';
import '../theme/bravo_theme.dart';
import '../widgets/avatar/avatar_painter.dart';

// ---------------------------------------------------------------------------
// Local constants
// ---------------------------------------------------------------------------

const Color _bg      = Color(0xFF0D0D1A);
const Color _card    = Color(0xFF161625);
const Color _divider = Color(0xFF252535);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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
    _nameCtrl = TextEditingController(text: ref.read(displayNameProvider));
  }

  @ov