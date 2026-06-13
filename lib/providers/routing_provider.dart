// routing_provider.dart — Riverpod state for active route and turn-by-turn
// navigation. All routing state flows through these providers; screens and
// widgets only read/watch — they never call RoutingService directly.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/route_model.dart';
import '../services/geocoding_service.dart';
import '../services/routing_service.dart';
import '../services/tts_service.dart';
import 'location_provider.dart';

// ============================================================
// DESTINATION
// ============================================================

/// The user's chosen destination. NULL when no navigation is active.
/// Set by the search bar / map long-press; cleared when the user cancels.
final StateProvider<LatLng?> destinationProvider =
    StateProvider<LatLng?>((Ref ref) => null);

// ============================================================
// ROUTE PREFERENCES
// ============================================================

/// The user's current route option toggles. Watched by [activeRouteProvider]
/// — any change triggers an immediate recalculation.
final StateProvider<RoutePreferences> routePreferencesProvider =
    StateProvider<RoutePreferences>(
  (Ref ref) => const RoutePreferences(),
);

// ============================================================
// ACTIVE ROUTE (StateNotifier)
// ============================================================

/// Holds the computed route (or null when no navigation is active) plus a
/// loading/error state. Exposes [RouteNotifier.calculate] and [.clear].
///
/// Screens call [RouteNotifier.calculate] to kick off a new route request;
/// the provider automatically recalculates when preferences change while a
/// destination is set (see [prefAutoRecalcProvider]).
final StateNotifierProvider<RouteNotifier, AsyncValue<BravoRoute?>>
    activeRouteProvider =
    StateNotifierProvider<RouteNotifier, AsyncValue<BravoRoute?>>(
  (Ref ref) => RouteNotifier(ref),
);

/// Exposes the underlying [RouteNotifier] for imperative calls.
RouteNotifier routeNotifierOf(WidgetRef ref) =>
    ref.read(activeRouteProvider.notifier);

// ============================================================
// NOTIFIER
// ============================================================

class RouteNotifier extends StateNotifier<AsyncValue<BravoRoute?>> {
  RouteNotifier(this._ref) : super(const AsyncValue<BravoRoute?>.data(null));

  final Ref _ref;
  final RoutingService _service = RoutingService();

  // Debounce token: if a recalculation is in-flight and a new request arrives,
  // the first is cancelled (token no longer matches when it finishes).
  int _calcToken = 0;

  /// Calculates a route from the user's current GPS position to [destination]
  /// using the current [RoutePreferences]. Cancels any in-flight calculation.
  Future<void> calculate({
    required LatLng destination,
    List<LatLng> alprLocations = const <LatLng>[],
  }) async {
    final int token = ++_calcToken;
    state = const AsyncValue<BravoRoute?>.loading();

    final position = _ref.read(positionStreamProvider).valueOrNull;
    if (position == null) {
      state = AsyncValue<BravoRoute?>.error(
        'Waiting for GPS fix',
        StackTrace.current,
      );
      return;
    }

    final RoutePreferences prefs = _ref.read(routePreferencesProvider);
    final LatLng origin = LatLng(position.latitude, position.longitude);

    final AsyncValue<BravoRoute?> result = await AsyncValue.guard<BravoRoute?>(
      () => _service.calculateRoute(
        origin: origin,
        destination: destination,
        preferences: prefs,
        alprLocations: alprLocations,
      ),
    );

    // Ignore if a newer calculation has started since we were called.
    if (token != _calcToken) return;
    state = result;
  }

  /// Recalculates from the current GPS position using the same destination
  /// and updated preferences. Called on preference toggle changes or off-route.
  Future<void> recalculate({List<LatLng> alprLocations = const <LatLng>[]}) async {
    final BravoRoute? current = state.valueOrNull;
    if (current == null) return;
    await calculate(
      destination: current.destination,
      alprLocations: alprLocations,
    );
  }

  /// Clears the active route and cancels any in-flight calculation.
  void clear() {
    _calcToken++;
    state = const AsyncValue<BravoRoute?>.data(null);
  }
}

// ============================================================
// AUTO-RECALCULATE ON PREFERENCE CHANGE
// ============================================================

/// Side-effect provider: watches [routePreferencesProvider] and triggers
/// [RouteNotifier.recalculate] whenever preferences change while a route is
/// active. Using a Provider (not a StateProvider) means this watcher is
/// always alive while the ProviderScope is alive.
final Provider<void> prefAutoRecalcProvider = Provider<void>((Ref ref) {
  // Watch ONLY preferences. Do NOT watch activeRouteProvider here — that
  // creates an infinite recalculation loop:
  //   route resolves → provider re-runs → recalculate() → loading()
  //   → route resolves → provider re-runs → ∞
  // Symptom: map flickers flat↔angled and routing appears permanently broken.
  ref.watch(routePreferencesProvider);
  Future<void>.microtask(() {
    // read (not watch) — this provider must NOT re-run when the route changes,
    // only when preferences change.
    final AsyncValue<BravoRoute?> routeState = ref.read(activeRouteProvider);
    if (routeState.valueOrNull != null) {
      ref.read(activeRouteProvider.notifier).recalculate();
    }
  });
});

// ============================================================
// OFF-ROUTE DETECTION
// ============================================================

/// True when the user's GPS position is more than [offRouteThresholdMeters]
/// from the computed route polyline. Watched by map_screen to trigger
/// recalculation.
final Provider<bool> offRouteProvider = Provider<bool>((Ref ref) {
  final BravoRoute? route = ref.watch(activeRouteProvider).valueOrNull;
  if (route == null || route.waypoints.isEmpty) return false;

  final position = ref.watch(positionStreamProvider).valueOrNull;
  if (position == null) return false;

  final LatLng userPoint = LatLng(position.latitude, position.longitude);
  final double dist =
      distanceToPolylineMeters(userPoint, route.waypoints);
  return dist > offRouteThresholdMeters;
});

// ============================================================
// NAVIGATION STATE (CURRENT STEP)
// ============================================================

/// Derives which step the user is on and how far to the next maneuver.
/// Returns null when no route is active.
final Provider<NavigationState?> navigationStateProvider =
    Provider<NavigationState?>((Ref ref) {
  final BravoRoute? route = ref.watch(activeRouteProvider).valueOrNull;
  if (route == null || route.steps.isEmpty) return null;

  final position = ref.watch(positionStreamProvider).valueOrNull;
  if (position == null) return null;

  final LatLng userPoint = LatLng(position.latitude, position.longitude);

  // Find the step whose maneuver point is closest to the user. This is a
  // simple but effective heuristic: among all maneuver waypoints, the nearest
  // one that still lies ahead of us is the current target.
  int bestIdx = 0;
  double bestDist = double.infinity;

  for (int i = 0; i < route.steps.length; i++) {
    final int shapeIdx = route.steps[i].shapeIndex;
    if (shapeIdx >= route.waypoints.length) continue;
    final LatLng maneuverPoint = route.waypoints[shapeIdx];
    final double dist =
        const Distance().as(LengthUnit.Meter, userPoint, maneuverPoint);
    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }

  // If we're within stepAdvanceRadiusMeters of the current maneuver point
  // and there's a next step, advance to it.
  if (bestDist <= stepAdvanceRadiusMeters &&
      bestIdx < route.steps.length - 1) {
    bestIdx++;
    // Recalculate distance to the new step.
    final int nextShapeIdx = route.steps[bestIdx].shapeIndex;
    if (nextShapeIdx < route.waypoints.length) {
      bestDist = const Distance().as(
        LengthUnit.Meter,
        userPoint,
        route.waypoints[nextShapeIdx],
      );
    }
  }

  // Sum remaining step durations for ETA.
  final double timeRemaining = route.steps
      .skip(bestIdx)
      .fold(0.0, (double sum, ManeuverStep s) => sum + s.durationSeconds);

  // Approximate remaining distance: sum of remaining step distances.
  final double distRemaining = route.steps
      .skip(bestIdx)
      .fold(0.0, (double sum, ManeuverStep s) => sum + s.distanceMiles) *
      metersPerMile;

  return NavigationState(
    currentStepIndex: bestIdx,
    currentStep: route.steps[bestIdx],
    distanceToNextManeuverMeters: bestDist,
    isLastStep: bestIdx == route.steps.length - 1,
    distanceRemainingMeters: distRemaining,
    timeRemainingSeconds: timeRemaining,
  );
});

// ============================================================
// TTS — ANNOUNCE UPCOMING MANEUVERS
// ============================================================

/// Side-effect provider: speaks the next maneuver instruction via [TtsService]
/// when the user is within [maneuverAlertDistanceMeters] of it.
/// Skips the announcement if TTS is disabled or if the same instruction was
/// already spoken (handled inside TtsService itself).
final Provider<void> ttsAnnouncerProvider = Provider<void>((Ref ref) {
  final NavigationState? navState = ref.watch(navigationStateProvider);
  if (navState == null) return;
  if (navState.distanceToNextManeuverMeters > maneuverAlertDistanceMeters) return;
  if (navState.isLastStep &&
      navState.distanceToNextManeuverMeters > stepAdvanceRadiusMeters * 2) {
    return; // Don't announce "You have arrived" until very close.
  }

  final String instruction = navState.currentStep.verbalInstruction;
  // Fire-and-forget — TTS is non-blocking.
  Future<void>.microtask(() async {
    final TtsService tts = await TtsService.instance();
    await tts.speak(instruction);
  });
});

// ============================================================
// GEOCODING
// ============================================================

/// Search query typed into the destination search bar.
final StateProvider<String> geocodeQueryProvider =
    StateProvider<String>((Ref ref) => '');

/// Geocoding results for the current [geocodeQueryProvider] value.
/// Auto-fires whenever the query changes. Returns empty list while loading
/// or on error — never throws.
final FutureProvider<List<GeocodingResult>> geocodeResultsProvider =
    FutureProvider<List<GeocodingResult>>((Ref ref) async {
  final String query = ref.watch(geocodeQueryProvider);
  if (query.trim().length < 2) return <GeocodingResult>[];
  // Small debounce: wait 400