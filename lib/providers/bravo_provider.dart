// bravo_provider.dart — Riverpod state for Bravos balance, achievements,
// cosmetics, and the achievement unlock notification queue.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bravo_model.dart';
import '../services/bravo_service.dart';
import 'archetype_provider.dart'; // for currentUserIdProvider

// ---------------------------------------------------------------------------
// Bravos balance
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<BravosBalance?> bravosBalanceProvider =
    AutoDisposeFutureProvider<BravosBalance?>((Ref ref) async {
  final String? userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return BravoService.instance.loadBalance(userId);
});

// ---------------------------------------------------------------------------
// Unlocked cosmetics
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<List<UnlockedCosmetic>> cosmeticsProvider =
    AutoDisposeFutureProvider<List<UnlockedCosmetic>>(
        (Ref ref) async {
  final String? userId = ref.watch(currentUserIdProvider);
  if (userId == null) return <UnlockedCosmetic>[];
  return BravoService.instance.loadCosmetics(userId);
});

// ---------------------------------------------------------------------------
// Pending achievement unlock notifications
// (shown as a banner/toast — user can dismiss, auto-clears after 10s)
// ---------------------------------------------------------------------------

class _UnlockNotification {
  const _UnlockNotification({required this.achievement, this.cosmetic});
  final AchievementId achievement;
  final CosmeticId? cosmetic;
}

class AchievementNotifier
    extends StateNotifier<List<_UnlockNotification>> {
  AchievementNotifier() : super(<_UnlockNotification>[]) {
    BravoService.instance.onAchievementEarned = _onEarned;
  }

  void _onEarned(AchievementId id, CosmeticId? cosmetic) {
    state = <_UnlockNotification>[
      ...state,
      _UnlockNotification(achievement: id, cosmetic: cosmetic),
    ];
  }

  void dismiss(AchievementId id) {
    state = state
        .where((_UnlockNotification n) => n.achievement != id)
        .toList();
  }
}

final StateNotifierProvider<AchievementNotifier, List<_UnlockNotification>>
    achievementNotifierProvider =
    StateNotifierProvider<AchievementNotifier, List<_UnlockNotification>>(
  (_) => AchievementNotifier(),
);

// ---------------------------------------------------------------------------
// Equip / unequip a cosmetic
// ---------------------------------------------------------------------------

/// Call to toggle a cosmetic. Invalidates [cosmeticsProvider] on completion.
Future<void> setEquippedCosmetic(
  WidgetRef ref,
  CosmeticId cosmeticId,
  bool equipped,
) async {
  final String? userId = ref.read(currentUserIdProvider);
  if (userId == null) return;
  await BravoService.instance.setEquipped(userId, cosmeticId, equipped);
  ref.invalidate(cosmeticsProvider);
}
