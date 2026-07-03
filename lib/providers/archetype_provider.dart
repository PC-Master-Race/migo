// archetype_provider.dart — Riverpod state for the user's driving archetype.
//
// Providers:
//   currentUserIdProvider     — the signed-in Supabase uid (nullable)
//   archetypeNotifierProvider — holds ArchetypeProfile, exposes recalculate()

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/archetype_model.dart';
import '../services/archetype_service.dart';
import '../services/supabase_service.dart';

// ---------------------------------------------------------------------------
// Current user id — read from Supabase auth session.
// ---------------------------------------------------------------------------

final Provider<String?> currentUserIdProvider = Provider<String?>(
  (Ref ref) => SupabaseService.isConnected
      ? SupabaseService.client.auth.currentSession?.user.id
      : null,
);

// ---------------------------------------------------------------------------
// Mutable notifier — call recalculate() at the end of a navigation session.
// ---------------------------------------------------------------------------

class ArchetypeNotifier extends StateNotifier<AsyncValue<ArchetypeProfile>> {
  ArchetypeNotifier(this._ref)
      : super(const AsyncValue<ArchetypeProfile>.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final String? userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      state = AsyncValue<ArchetypeProfile>.data(
        ArchetypeProfile(
          userId: '',
          currentArchetype: DrivingArchetype.zenMaster,
          scores: zeroScores(),
        ),
      );
      return;
    }
    state = const AsyncValue<ArchetypeProfile>.loading();
    state = await AsyncValue.guard<ArchetypeProfile>(
      () => ArchetypeService.instance.loadProfile(userId),
    );
    // A backend hiccup must never leave the map with a bare fallback dot —
    // degrade to a default in-memory profile (fresh-user look) instead.
    if (state.hasError) {
      debugPrint('[archetype] profile load failed, using in-memory default: '
          '${state.error}');
      state = AsyncValue<ArchetypeProfile>.data(
        ArchetypeProfile(
          userId: userId,
          currentArchetype: DrivingArchetype.zenMaster,
          scores: zeroScores(),
        ),
      );
    }
  }

  /// Call this when a navigation session ends with its collected metrics.
  Future<void> recalculateAfterSession(SessionMetrics metrics) async {
    final ArchetypeProfile? current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncValue<ArchetypeProfile>.loading();
    state = await AsyncValue.guard<ArchetypeProfile>(
      () =>
          ArchetypeService.instance.recalculateAfterSession(metrics, current),
    );
  }

  /// Sets which unlocked archetype the avatar displays (null = automatic,
  /// i.e. follow the current dominant archetype). Updates state immediately
  /// so the map avatar changes on the spot, persists in the background.
  Future<void> selectArchetype(DrivingArchetype? choice) async {
    final ArchetypeProfile? current = state.valueOrNull;
    if (current == null) return;
    state = await AsyncValue.guard<ArchetypeProfile>(
      () => ArchetypeService.instance.selectArchetype(current, choice),
    );
  }
}

final StateNotifierProvider<ArchetypeNotifier, AsyncValue<ArchetypeProfile>>
    archetypeNotifierProvider =
    StateNotifierProvider<ArchetypeNotifier, AsyncValue<ArchetypeProfile>>(
  (Ref ref) => ArchetypeNotifier(ref),
);
