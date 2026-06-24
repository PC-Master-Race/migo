// tts_service.dart — Text-to-speech for navigation instructions.
//
// TWO-TIER ARCHITECTURE:
//   Primary:  ElevenLabs REST API — high-quality, human-like voice.
//             Only used when the user has configured an API key in settings.
//   Fallback: flutter_tts — on-device TTS, fully offline, always available.
//
// PRIVACY RULES (PRODUCT_BRIEF):
//   • Only the instruction text string is sent to ElevenLabs — no location
//     data, no user identity, no session metadata.
//   • If no ElevenLabs key is set, zero network calls are made for TTS.
//   • The ElevenLabs key is stored in the local Hive box only — never in
//     Supabase, never logged.
//
// USAGE:
//   Inject TtsService via Riverpod (ttsSeviceProvider in routing_provider).
//   Call speak(instruction) before each maneuver. The service handles
//   deduplication (same instruction is not spoken twice in a row).

import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

// --- SERVICE ---

/// Speaks navigation instructions via ElevenLabs (if configured) or the
/// on-device TTS engine.
class TtsService {
  TtsService._();

  static TtsService? _instance;

  /// Returns the singleton [TtsService], initializing it on first call.
  static Future<TtsService> instance() async {
    if (_instance != null) return _instance!;
    final TtsService svc = TtsService._();
    await svc._init();
    _instance = svc;
    return svc;
  }

  late final FlutterTts _flutterTts;

  /// The last instruction spoken — prevents repeating the same text.
  String _lastSpoken = '';

  /// True while audio is playing, so we don't queue multiple overlapping reads.
  bool _isSpeaking = false;

  Future<void> _init() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slightly slower for driving clarity.
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() => _isSpeaking = false);
  }

  // --- PUBLIC API ---

  /// Speaks [instruction] via ElevenLabs or flutter_tts.
  ///
  /// No-ops when:
  ///   • TTS is disabled in settings.
  ///   • [instruction] is the same as the last spoken text.
  ///   • Audio is already playing.
  Future<void> speak(String instruction) async {
    if (!_isTtsEnabled()) return;
    if (instruction == _lastSpoken) return;
    if (_isSpeaking) return;

    _lastSpoken = instruction;
    _isSpeaking = true;

    final String? apiKey = _elevenLabsApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      final bool success = await _speakViaElevenLabs(instruction, apiKey);
      if (success) return;
      // ElevenLabs failed — fall through to flutter_tts.
    }

    await _speakViaFlutterTts(instruction);
  }

  /// Stops any currently playing audio.
  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
  }

  // --- ELEVENLABS ---

  /// Calls the ElevenLabs API and plays the returned MP3 bytes.
  /// Returns true on success, false on any failure.
  Future<bool> _speakViaElevenLabs(String text, String apiKey) async {
    final String voiceId = _elevenLabsVoiceId();
    final Uri uri = Uri.parse('$elevenLabsApiUrl/$voiceId');

    try {
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{
              'xi-api-key': apiKey,
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body: '{"text":${_jsonString(text)},'
                '"model_id":"eleven_turbo_v2",'
                '"voice_settings":{"stability":0.5,"similarity_boost":0.75}}',
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return false;

      // Write audio bytes to a temp file and play it.
      await _playMp3Bytes(response.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves [bytes] to a temp MP3 file and plays it.
  /// Uses dart:io File + flutter_tts is not suitable for raw mp3;
  /// we play it using the audioplayers package.
  Future<void> _playMp3Bytes(Uint8List bytes) async {
    // Write to temp file — AudioPlayer plays from a device path.
    final Directory tmp = await getTemporaryDirectory();
    final File file = File('${tmp.path}/migo_nav_tts.mp3');
    await file.writeAsBytes(bytes, flush: true);

    final AudioPlayer player = AudioPlayer();
    player.onPlayerComplete.listen((_) {
      _isSpeaking = false;
      player.dispose();
    });
    await player.play(DeviceFileSource(file.path));
  }

  // --- FLUTTER TTS FALLBACK ---

  Future<void> _speakViaFlutterTts(String text) async {
    await _flutterTts.speak(text);
    // _isSpeaking reset in the completion handler set during _init().
  }

  // --- SETTINGS HELPERS ---

  bool _isTtsEnabled() {
    return Hive.box<dynamic>(hiveBoxSettings)
        .get(hiveKeyTtsEnabled, defaultValue: true) as bool;
  }

  String? _elevenLabsApiKey() {
    return Hive.box<dynamic>(hiveBoxSettings)
        .get(hiveKeyElevenLabsApiKey) as String?;
  }

  String _elevenLabsVoiceId() {
    return (Hive.box<dynamic>(hiveBoxSettings)
        .get(hiveKeyElevenLabsVoiceId) as String?) ??
        elevenLabsDefaultVoiceId;
  }

  // --- UTILITIES ---

  /// JSON-encodes a string including surrounding quotes.
  String _jsonString(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
