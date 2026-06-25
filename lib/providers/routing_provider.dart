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
import '../utils/map_utils.dart';
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
/// active. IMPORTANT: this is a side-effecting Provider — it only runs while
/// something is watching it. map_screen.dart keeps it alive via ref.watch for
/// the lifetime of the map. If nothing watches it, auto-recalc silently stops.
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
  final List<LatLng> wp = route.waypoints;
  if (wp.length < 2) return null;

  // Where the user is ALONG the route (index of the nearest segment). The
  // current maneuver is then the first one whose vertex lies AHEAD of us — so
  // navigation advances the moment we pass a turn, instead of clinging to
  // whichever turn happens to be closest (the "stuck on previous step" bug).
  final int segIdx = nearestSegmentIndex(userPoint, wp);
  final int nextVertex = (segIdx + 1).clamp(0, wp.length - 1);

  int stepIdx =
      route.steps.indexWhere((ManeuverStep s) => s.shapeIndex > segIdx);
  if (stepIdx == -1) stepIdx = route.steps.length - 1;
  final ManeuverStep step = route.steps[stepIdx];
  final ManeuverStep? next =
      stepIdx + 1 < route.steps.length ? route.steps[stepIdx + 1] : null;

  // Along-route distances (follow the road, not a straight line): user → the
  // next polyline vertex, then vertex → maneuver / → end.
  final int maneuverVertex = step.shapeIndex.clamp(0, wp.length - 1);
  final double toNextVertex =
      const Distance().as(LengthUnit.Meter, userPoint, wp[nextVertex]);
  final double distToManeuver =
      toNextVertex + routeDistanceMeters(wp, nextVertex, maneuverVertex);
  final double distRemaining =
      toNextVertex + routeDistanceMeters(wp, nextVertex, wp.length - 1);

  // Remaining time: sum of the remaining steps' durations (approx).
  final double timeRemaining = route.steps
      .skip(stepIdx)
      .fold(0.0, (double sum, ManeuverStep s) => sum + s.durationSeconds);

  return NavigationState(
    currentStepIndex: stepIdx,
    currentStep: step,
    nextStep: next,
    distanceToNextManeuverMeters: distToManeuver,
    isLastStep: stepIdx == route.steps.length - 1,
    distanceRemainingMeters: distRemaining,
    timeRemainingSeconds: timeRemaining,
  );
});

// ============================================================
// TTS — ANNOUNCE UPCOMING MANEUVERS
// ============================================================

/// Holds the announcer so its per-step state survives provider rebuilds.
final Provider<_NavAnnouncer> _navAnnouncerProvider =
    Provider<_NavAnnouncer>((Ref ref) => _NavAnnouncer());

/// Side-effect provider (watched by map_screen): drives tiered, EARLY turn
/// announcements. On entering a leg it speaks a lead-in ("In N, take exit
/// 59"); then it reminds the driver at thresholds that scale with leg length
/// (long legs → 5 mi + 1 mi; short legs → 40% remaining + 1 mi).
final Provider<void> ttsAnnouncerProvider = Provider<void>((Ref ref) {
  final NavigationState? navState = ref.watch(navigationStateProvider);
  if (navState == null) {
    ref.read(_navAnnouncerProvider).reset();
    return;
  }
  ref.read(_navAnnouncerProvider).onUpdate(navState);
});

/// Tracks which announcements have already fired for the current leg and
/// decides what to speak next. Speaks via [TtsService], which respects the
/// user's voice-guidance setting and won't repeat identical text.
class _NavAnnouncer {
  int? _stepIndex;
  double _legMeters = 0; // distance-to-maneuver captured when the leg began
  final Set<String> _fired = <String>{};

  void reset() {
    _stepIndex = null;
    _legMeters = 0;
    _fired.clear();
  }

  void onUpdate(NavigationState nav) {
    final double remaining = nav.distanceToNextManeuverMeters;

    // Entered a new leg → capture its length, reset, give the lead-in. This is
    // the "you just turned, here's what's next" feedback.
    if (nav.currentStepIndex != _stepIndex) {
      _stepIndex = nav.currentStepIndex;
      _legMeters = remaining;
      _fired.clear();
      _speak('In ${formatUsDistance(remaining, spoken: true)}, '
          '${_instr(nav.currentStep)}');
      return;
    }

    // Approaching reminders (far → near).
    for (final double tier in _tierMeters(_legMeters)) {
      final String key = 't${tier.round()}';
      if (remaining <= tier && !_fired.contains(key)) {
        _fired.add(key);
        _speak('In ${formatUsDistance(remaining, spoken: true)}, '
            '${_instr(nav.currentStep)}');
      }
    }
  }

  /// Reminder distances (meters), filtered to ones that make sense for the leg.
  List<double> _tierMeters(double legMeters) {
    final double legMiles = legMeters / metersPerMile;
    final List<double> miles = legMiles >= navLongLegMiles
        ? <double>[navLongLegFarAlertMiles, navNearAlertMiles]
        : <double>[legMiles * navShortLegRemainingFraction, navNearAlertMiles];

    final List<double> out = <double>[];
    for (final double m in miles) {
      final double meters = m * metersPerMile;
      // Skip thresholds basically at the leg start (the lead-in covered that)
      // and dedupe ones within ~250 m of each other.
      if (meters < legMeters - 120 &&
          m > 0.1 &&
          out.every((double o) => (o - meters).abs() > 250)) {
        out.add(meters);
      }
    }
    out.sort((double a, double b) => b.compareTo(a)); // far → near
    return out;
  }

  String _instr(ManeuverStep s) =>
      s.instruction.isNotEmpty ? s.instruction : s.verbalInstruction;

  void _speak(String text) {
    if (text.trim().isEmpty) return;
    // Fire-and-forget — TTS is non-blocking.
    Future<void>.microtask(() async {
      final TtsService tts = await TtsService.instance();
      await tts.speak(text);
    });
  }
}

// ============================================================
// GEOCODING
// ============================================================

/// Search query typed into the destination search bar.
final StateProvider<String> geocodeQueryProvider =
    StateProvider<String>((Ref ref) => '');

/// Geocoding results for the current [geocodeQueryProvider] value.
/// Auto-fires whenever the query changes. Returns empty list while loading
/// or on error — never throws.
///
/// The user's GPS position is passed to [GeocodingService.search] so
/// Nominatim receives a ~50 km viewbox and returns nearby results first.
final FutureProvider<List<GeocodingResult>> geocodeResultsProvider =
    FutureProvider<List<GeocodingResult>>((Ref ref) async {
  final String query = ref.watch(geocodeQueryProvider);
  if (query.trim().length < 2) return <GeocodingResult>[];
  // Small debounce: wait 400 ms after the last keystroke before searching.
  // Riverpod cancels+restarts if the query changes during the wait —
  // this is effectively debounced with no extra bookkeeping.
  await Future<void>.delayed(const Duration(milliseconds: 400));

  // read (not watch) the position — we don't want every GPS update to
  // re-fire a search; only query changes should trigger that.
  final position = ref.read(positionStreamProvider).valueOrNull;
  final LatLng? userPos = position != null
      ? LatLng(position.latitude, position.longitude)
      : null;

  return GeocodingService().search(query, userPosition: userPos);
});
