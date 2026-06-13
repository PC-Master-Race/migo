// saved_location_provider.dart — Riverpod state for saved places.
// Persists to the existing Hive settings box as a JSON string so we don't
// need a new box or any Hive TypeAdapter codegen.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/saved_location_model.dart';
import '../models/route_model.dart'; // GeocodingResult

// --- PROVIDER ---

final StateNotifierProvider<SavedLocationNotifier, List<SavedLocation>>
    savedLocationsProvider =
    StateNotifierProvider<SavedLocationNotifier, List<SavedLocation>>(
  (Ref ref) => SavedLocationNotifier()..load(),
);

// --- NOTIFIER ---

class SavedLocationNotifier extends StateNotifier<List<SavedLocation>> {
  SavedLocationNotifier() : super(const <SavedLocation>[]);

  // ------------------------------------------------------------------ load --

  Future<void> load() async {
    try {
      final Box<dynamic> box =
          await Hive.openBox<dynamic>(hiveBoxSettings);
      final String? raw =
          box.get(hiveKeySavedLocations) as String?;
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((dynamic e) =>
              SavedLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt data — start with empty list.
    }
  }

  // ----------------------------------------------------------------- save ---

  /// Saves [result] as [type]. Home and Work replace any existing entry of
  /// that type; Favorites accumulate (capped at 10).
  Future<void> saveFromResult({
    required SavedLocationType type,
    required GeocodingResult result,
    String? customLabel,
  }) async {
    final String id =
        '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    final String label = customLabel ?? type.defaultLabel;

    final List<SavedLocation> existing = type == SavedLocationType.favorite
        ? state.where((SavedLocation l) => l.id != id).toList()
        : state.where((SavedLocation l) => l.type != type).toList();

    // Cap favorites at 10 — remove oldest if needed.
    final List<SavedLocation> favorites = existing
        .where((SavedLocation l) => l.type == SavedLocationType.favorite)
        .toList();
    if (type == SavedLocationType.favorite && favorites.length >= 10) {
      existing.removeAt(
        existing.indexOf(favorites.first),
      );
    }

    state = <SavedLocation>[
      ...existing,
      SavedLocation(
        id: id,
        type: type,
        label: label,
        position: result.position,
        address: result.displayName,
      ),
    ];
    await _persist();
  }

  // ---------------------------------------------------------------- remove --

  Future<void> remove(String id) async {
    state = state.where((SavedLocation l) => l.id != id).toList();
    await _persist();
  }

  // ---------------------------------------------------------------- helpers -

  Future<void> _persist() async {
    final Box<dynamic> box =
        await Hive.openBox<dynamic>(hiveBoxSettings);
    await box.put(
      hiveKeySavedLocations,
      jsonEncode(
        state.map((SavedLocation l) => l.toJson()).toList(),
      ),
    );
  }
}
