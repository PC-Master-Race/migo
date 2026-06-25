// hazard_provider.dart — Riverpod state for the hazard system.
// Fetches nearby hazard pins, derives which ones are in alert range,
// manages the alert queue (auto-dismissing banners), and exposes the
// hazard reporting flow state.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/hazard_model.dart';
import '../services/hazard_service.dart';
import '../services/hazard_sound_service.dart';
import 'location_provider.dart';

// ============================================================
// LAYER VISIBILITY
// ============================================================

/// Whether the hazard pin layer is visible on the map.
/// Defaults to true — hazards are an on-by-default safety feature.
final StateProvider<bool> hazardLayerEnabledProvider =
    StateProvider<bool>((_) => true);

// ============================================================
// NEARBY HAZARDS — periodic fetch
// ============================================================

/// Fetches confirmed hazards near the user's current position and refreshes
/// every 2 minutes. Returns an empty list while GPS is unavailable or offline.
///
/// Uses autoDispose so the timer stops when no widget is watching (e.g. when
/// the app is in the background with no active navigation).
final AutoDisposeStreamProvider<List<Hazard>> nearbyHazardsProvider =
    StreamProvider.autoDispose<List<Hazard>>((Ref ref) async* {
  final _service = HazardService();

  // Fetch immediately on first listen, then every 2 minutes.
  while (true) {
    final position = ref.read(positionStreamProvider).valueOrNull;
    if (position != null) {
      final List<Hazard> hazards = await _service.fetchNearbyHazards(
        LatLng(position.latitude, position.longitude),
      );
      // Also include the user's own unconfirmed pins so they can see what
      // they submitted — mixed in but visually distinguished in the map layer.
      final List<Hazard> ownPending = await _service.fetchOwnPendingHazards();
      yield <Hazard>[...hazards, ...ownPending];
    }
    await Future<void>.delayed(const Duration(minutes: 2));
  }
});

// ============================================================
// HAZARDS IN ALERT RANGE — derived from GPS + hazard list
// ============================================================

/// The subset of [nearbyHazardsProvider] that are within
/// [hazardAlertRadiusMiles] of the user's current position.
/// Only includes community-confirmed hazards (own pending pins don't alert).
final Provider<List<Hazard>> hazardsInAlertRangeProvider =
    Provider<List<Hazard>>((Ref ref) {
  final List<Hazard> all =
      ref.watch(nearbyHazardsProvider).valueOrNull ?? <Hazard>[];
  final position = ref.watch(positionStreamProvider).valueOrNull;
  if (position == null) return <Hazard>[];

  final LatLng userPos = LatLng(position.latitude, position.longitude);

  return all.where((Hazard h) {
    if (!h.isCommunityConfirmed) return false;
    final double distMiles =
        const Distance().as(LengthUnit.Mile, userPos, h.position);
    return distMiles <= hazardAlertRadiusMiles;
  }).toList();
});

// ============================================================
// ALERT QUEUE — banners to show the user
// ============================================================

/// Active alert banners. Each entry is a hazard that has just entered the
/// 2-mile radius and hasn't been shown yet. The HazardAlertBanner widget
/// removes its own entry after [hazardAlertAutoDismissSeconds].
final StateProvider<List<Hazard>> activeHazardAlertsProvider =
    StateProvider<List<Hazard>>((Ref ref) => <Hazard>[]);

/// Tracks which hazard IDs have already triggered an alert, with the
/// timestamp so they can re-alert after [hazardReAlertCooldownMinutes].
final StateProvider<Map<String, DateTime>> alertedHazardTimestampsProvider =
    StateProvider<Map<String, DateTime>>(
        (Ref ref) => <String, DateTime>{});

/// Side-effect provider: watches [hazardsInAlertRangeProvider] and adds new
/// entries to [activeHazardAlertsProvider] + fires [HazardSoundService].
/// Kept as a Provider<void> so it's always active while the ProviderScope
/// is alive — no build method needed.
final Provider<void> hazardAlertWatcherProvider = Provider<void>((Ref ref) {
  final List<Hazard> inRange = ref.watch(hazardsInAlertRangeProvider);
  final Map<String, DateTime> alerted =
      ref.read(alertedHazardTimestampsProvider);

  for (final Hazard hazard in inRange) {
    final DateTime? lastAlerted = alerted[hazard.id];
    final bool cooldownExpired = lastAlerted == null ||
        DateTime.now().difference(lastAlerted).inMinutes >=
            hazardReAlertCooldownMinutes;

    if (!cooldownExpired) continue;

    // Mark as alerted so we don't fire again until cooldown expires.
    ref.read(alertedHazardTimestampsProvider.notifier).update(
          (Map<String, DateTime> state) =>
              <String, DateTime>{...state, hazard.id: DateTime.now()},
        );

    // Add to the active banner queue.
    ref.read(activeHazardAlertsProvider.notifier).update(
          (List<Hazard> state) => <Hazard>[...state, hazard],
        );

    // Fire haptic + audio alert (fire-and-forget).
    Future<void>.microtask(
      () => HazardSoundService.playAlert(hazard.type.name),
    );
  }
});

/// Removes [hazard] from the active alert queue. Called by the banner widget
/// after [hazardAlertAutoDismissSeconds] seconds.
void dismissHazardAlert(WidgetRef ref, Hazard hazard) {
  ref.read(activeHazardAlertsProvider.notifier).update(
        (List<Hazard> state) =>
            state.where((Hazard h) => h.id != hazard.id).toList(),
      );
}

// ============================================================
// HAZARD REPORTING FLOW
// ============================================================

/// The hazard type currently selected in the report sheet.
/// Null when no sheet is open.
final StateProvider<HazardType?> selectedHazardTypeProvider =
    StateProvider<HazardType?>((Ref ref) => null);

/// Submit state for the report-hazard flow.
final StateNotifierProvider<ReportHazardNotifier, AsyncValue<void>>
    reportHazardProvider =
    StateNotifierProvider<ReportHazardNotifier, AsyncValue<void>>(
  (Ref ref) => ReportHazardNotifier(),
);

/// Handles the async submit + resets state on success.
class ReportHazardNotifier extends StateNotifier<AsyncValue<void>> {
  ReportHazardNotifier() : super(const AsyncValue<void>.data(null));

  final HazardService _service = HazardService();

  /// Submits a report of [type] at [position]. Resets to data(null) on success.
  Future<void> submit(HazardType type, LatLng position) async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard<void>(
      () => _service.reportHazard(type, position),
    );
    if (!state.hasError) {
      // Reset so the sheet can be reused without stale error state.
      await Future<void>.delayed(const Duration(seconds: 1));
      state = const AsyncValue<void>.data(null);
    }
  }
}

// ============================================================
// EXPIRY PROMPTS — "Is this still there?"
// ============================================================

/// Fetches hazards near [position] that are old enough to need a re-check.
/// Returns empty when offline or no position.
Future<List<Hazard>> fetchExpiryPromptCandidates(LatLng position) {
  return HazardService().fetchExpiryPromptCandidates(position);
}
