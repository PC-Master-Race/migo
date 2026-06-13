// driving_session_provider.dart — Connects live GPS to the driving-session
// tracker, the archetype engine, and the Bravos POI unlock system.
//
// This closes the Phase 4 loop that was scaffolded but never wired:
//   GPS update ──► checkPoiVisit()        (the "where you go" unlocks)
//             └──► DrivingSessionTracker  (the "how you drive" metrics)
//                        └─ on trip end ─► archetype recalc + driving_sessions
//
// PRIVACY: POI unlocks only ADD a cosmetic to the user's locker — nothing is
// shown on the avatar unless the user equips it (BravoService.setEquipped).
// Positions are never stored or transmitted beyond the anonymous lookups the
// existing services already make.
//
// LIVENESS: [drivingSessionEngineProvider] is a side-effecting Provider — it
// only runs while something watches it. map_screen.dart keeps it alive with
// ref.watch for the lifetime of the map.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/bravo_service.dart';
import '../services/driving_session_tracker.dart';
import '../services/supabase_service.dart';
import 'archetype_provider.dart';
import 'location_provider.dart';
import 'speed_limit_provider.dart';

// --- TRACKER INSTANCE ---

/// The single tracker for the app session. Held in a Provider so app-event
/// hooks (hazard report, reroute) can reach the same instance the GPS engine
/// feeds.
final Provider<DrivingSessionTracker> drivingSessionTrackerProvider =
    Provider<DrivingSessionTracker>((Ref ref) => DrivingSessionTracker());

// --- ENGINE ---

/// Side-effect provider: subscribes to the GPS stream and drives the tracker +
/// POI checks. Watch it (don't read) to keep it alive.
final Provider<void> drivingSessionEngineProvider = Provider<void>((Ref ref) {
  final DrivingSessionTracker tracker =
      ref.watch(drivingSessionTrackerProvider);

  ref.listen<AsyncValue<Position>>(
    positionStreamProvider,
    (AsyncValue<Position>? previous, AsyncValue<Position> next) {
      final Position? pos = next.valueOrNull;
      if (pos == null) return;
      _onPosition(ref, tracker, pos);
    },
  );
});

// --- HANDLERS ---

/// Handles a single GPS tick: POI unlock check + metric accumulation.
void _onPosition(Ref ref, DrivingSessionTracker tracker, Position pos) {
  final LatLng point = LatLng(pos.latitude, pos.longitude);

  // "Where you go" — eating/POI unlocks. Best-effort and fire-and-forget;
  // BravoService throttles by distance internally and fails silently offline.
  unawaited(BravoService.instance.checkPoiVisit(point));

  // "How you drive" — feed the tracker.
  final String? userId = ref.read(currentUserIdProvider);
  final double? limitMph = _parseLimitMph(ref.read(speedLimitLabelProvider));
  final FinishedSession? finished = tracker.recordPosition(
    pos,
    speedLimitMph: limitMph,
    userId: userId ?? '',
  );
  if (finished != null) _onTripFinished(ref, finished, userId);
}

/// Parses the speed-limit label ("45", "Unknown") into mph, or null if unknown.
double? _parseLimitMph(String label) => double.tryParse(label);

/// Processes a completed trip: update the avatar (always, so it's visible even
/// offline in dev) and persist the raw session when signed in + online.
void _onTripFinished(Ref ref, FinishedSession session, String? userId) {
  // Update the archetype from this drive. recalculateAfterSession runs the
  // engine and updates the in-memory profile; archetype_service skips the
  // Supabase write when offline, so the avatar still changes in dev.
  unawaited(
    ref
        .read(archetypeNotifierProvider.notifier)
        .recalculateAfterSession(session.metrics),
  );

  // Persist the raw session row only when there's a real backend + user.
  if (userId == null || userId.isEmpty || !SupabaseService.isConnected) return;
  unawaited(_persistSession(session, userId));
}

/// Inserts the finished trip into the `driving_sessions` table (best-effort —
/// the avatar has already updated regardless of whether this write succeeds).
Future<void> _persistSession(FinishedSession s, String userId) async {
  try {
    await SupabaseService.client.from('driving_sessions').insert(
      <String, dynamic>{
        'user_id': userId,
        'started_at': s.metrics.startedAt.toUtc().toIso8601String(),
        'ended_at': s.metrics.endedAt.toUtc().toIso8601String(),
        'distance_meters': s.distanceMeters,
        'average_speed_mps': s.averageSpeedMps,
        'max_speed_mps': s.maxSpeedMps,
        'aggression_score': s.aggressionScore,
        'alpr_reports_count': s.metrics.alprAvoidanceCount,
        'hazard_reports_count': s.metrics.hazardReportsCount,
      },
    );
  } catch (_) {
    // Best-effort: a failed insert must never disrupt the drive experience.
  }
}
