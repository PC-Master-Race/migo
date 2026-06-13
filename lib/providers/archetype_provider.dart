// archetype_provider.dart — Riverpod state for the user's driving archetype.
//
// Providers:
//   currentUserIdProvider     — the signed-in Supabase uid (nullable)
//   archetypeNotifierProvider — holds ArchetypeProfile, exposes recalculate()

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/archetype_model.dart';
import '../services/archetype_service.dart';
import '../services/supabase_service.dart';

// ---------------------------------------------------------------------------
// Current user id — read from Supabase auth session.
// ---------------------------------------------------------------------------

final Provider<String?> currentUserIdProvider = Provider<String?>(
  (Ref ref) => SupabaseService.client.auth.currentSession?.user.id,
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
}

final StateNotifierProvider<ArchetypeNotifier, AsyncValue<ArchetypeProfile>>
    archetypeNotifierProvider =
    StateNotifierProvider<ArchetypeNotifier, AsyncValue<ArchetypeProfile>>(
  (Ref ref) => ArchetypeNotifier(ref),
);
