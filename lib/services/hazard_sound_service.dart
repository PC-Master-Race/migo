// hazard_sound_service.dart — Alert sounds and haptics for hazard proximity.
//
// SOUND DESIGN PER HAZARD TYPE (PRODUCT_BRIEF Phase 3):
//   crash          — urgent, high-attention sound (e.g. sharp alert tone)
//   alprCamera     — ominous, subtle tone (e.g. low beep, plum UI)
//   speedTrap      — distinct police-radio-style chirp
//   ice            — soft chime, cold/delicate feel
//   construction   — lower-pitched alert, workaday feel
//   debris         — quick double-beep
//   generalDisturbance — neutral short tone
//
// IMPLEMENTATION:
//   Tier 1 — HapticFeedback: always fires, immediate, no file needed.
//   Tier 2 — audioplayers from assets/sounds/{type}.mp3: fires when the
//             asset exists. Files not committed yet; add them to assets/sounds/
//             and the service picks them up automatically.
// TODO: [produce/source audio files for each hazard type and add to
// assets/sounds/] [deferred: needs sound design work / licensing]

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

// --- SERVICE ---

/// Plays the appropriate haptic + audio alert for each [HazardType].
/// Stateless: callers fire-and-forget. Any audio error is swallowed silently.
class HazardSoundService {
  static const Map<String, _SoundConfig> _configs = <String, _SoundConfig>{
    'crash': _SoundConfig(
      assetPath: 'sounds/crash.mp3',
      haptic: HapticIntensity.heavy,
    ),
    'alprCamera': _SoundConfig(
      assetPath: 'sounds/alpr.mp3',
      haptic: HapticIntensity.medium,
    ),
    'speedTrap': _SoundConfig(
      assetPath: 'sounds/speed_trap.mp3',
      haptic: HapticIntensity.heavy,
    ),
    'ice': _SoundConfig(
      assetPath: 'sounds/ice.mp3',
      haptic: HapticIntensity.light,
    ),
    'construction': _SoundConfig(
      assetPath: 'sounds/construction.mp3',
      haptic: HapticIntensity.medium,
    ),
    'debris': _SoundConfig(
      assetPath: 'sounds/debris.mp3',
      haptic: HapticIntensity.medium,
    ),
    'generalDisturbance': _SoundConfig(
      assetPath: 'sounds/general.mp3',
      haptic: HapticIntensity.light,
    ),
  };

  /// Plays the alert for [hazardTypeName] (matches [HazardType.name]).
  /// Fire-and-forget — caller does not await.
  static Future<void> playAlert(String hazardTypeName) async {
    final _SoundConfig config =
        _configs[hazardTypeName] ?? _configs['generalDisturbance']!;

    // Tier 1: haptic feedback (always works, no asset required).
    await _playHaptic(config.haptic);

    // Tier 2: audio (requires the mp3 asset to exist; fails silently otherwise).
    await _playAudio(config.assetPath);
  }

  static Future<void> _playHaptic(HapticIntensity intensity) async {
    switch (intensity) {
      case HapticIntensity.heavy:
        await HapticFeedback.heavyImpact();
      case HapticIntensity.medium:
        await HapticFeedback.mediumImpact();
      case HapticIntensity.light:
        await HapticFeedback.lightImpact();
    }
  }

  static Future<void> _playAudio(String assetPath) async {
    try {
      final AudioPlayer player = AudioPlayer();
      // onPlayerComplete disposes the player to avoid memory leaks.
      player.onPlayerComplete.listen((_) => player.dispose());
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Sound file not yet present — haptic already fired, nothing to show.
    }
  }
}

// --- INTERNAL TYPES ---

enum HapticIntensity { heavy, medium, light }

class _SoundConfig {
  const _SoundConfig({required this.assetPath, required this.haptic});
  final String assetPath;
  final HapticIntensity haptic;
}
