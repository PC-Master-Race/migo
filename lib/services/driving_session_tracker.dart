// driving_session_tracker.dart — Turns a stream of GPS positions into a
// finished driving session the archetype engine can score.
//
// WHY THIS EXISTS:
//   The archetype engine (archetype_service.dart) was fully built but never
//   fed — nothing detected trips or computed SessionMetrics. This class is the
//   missing half: it watches movement, decides when a trip starts and ends
//   (motion-based, no buttons), and accumulates the GPS-derived metrics the
//   engine reads. It is PURE logic — no Riverpod, no network — so it can be
//   reasoned about and unit-tested on its own. The provider layer
//   (driving_session_provider.dart) feeds it positions and reacts to the
//   FinishedSession it returns.
//
// METRIC NOTES:
//   • Hard brakes/accels come from the change in GPS speed over each interval.
//   • highway/backRoad fractions are SPEED PROXIES, not true road-class data —
//     classifying every GPS point against OSM would be far too network-heavy on
//     device. Fast sustained travel ≈ highway, slow moving travel ≈ back road.
//   • avgSpeedRatio averages (speed / posted limit) only over samples where the
//     limit is known; unknown-limit samples are skipped rather than guessed.

import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/archetype_model.dart';

// --- RESULT TYPE ---

/// Everything a finished trip produces: the [SessionMetrics] the archetype
/// engine scores, plus the raw rollups the `driving_sessions` table stores.
class FinishedSession {
  const FinishedSession({
    required this.metrics,
    required this.distanceMeters,
    required this.averageSpeedMps,
    required this.maxSpeedMps,
    required this.aggressionScore,
  });

  final SessionMetrics metrics;
  final double distanceMeters;
  final double averageSpeedMps;
  final double maxSpeedMps;

  /// 0.0–1.0 rollup of hard braking/acceleration for the session row.
  final double aggressionScore;
}

// --- TRACKER ---

/// Accumulates the current trip and decides when it begins and ends.
class DrivingSessionTracker {
  // -- Trip lifecycle --
  bool _active = false;
  DateTime? _tripStart;
  DateTime? _belowStopSince; // first moment speed dropped below the stop floor

  // -- Last sample, for computing deltas --
  Position? _lastPos;

  // -- Accumulators (reset per trip) --
  double _distanceMeters = 0;
  double _maxSpeedMps = 0;
  double _speedSumMps = 0;
  int _speedSamples = 0;
  double _ratioSum = 0; // sum of speed/limit where limit is known
  int _ratioSamples = 0;
  int _hardBrakes = 0;
  int _hardAccels = 0;
  double _nightMillis = 0;
  double _movingMillis = 0;
  double _highwayMillis = 0;
  double _backRoadMillis = 0;

  // -- External event counters set by the app during a trip --
  int _hazardReports = 0;
  int _alprAvoided = 0;
  int _reroutes = 0;
  bool _onTimeArrival = false;

  /// True while a trip is in progress.
  bool get isActive => _active;

  // --- APP EVENT HOOKS ---
  // These let the rest of the app contribute to the current trip's metrics.
  // They no-op when no trip is active so stray events can't corrupt a session.

  /// The user reported a road hazard this trip (feeds the Scout archetype).
  void noteHazardReported() {
    if (_active) _hazardReports++;
  }

  /// The route recalculated mid-trip (feeds Chaos Agent / Scout).
  void noteReroute() {
    if (_active) _reroutes++;
  }

  /// The active route avoided [count] ALPR cameras (feeds Phantom / Ghost).
  /// Stored as a max so a later smaller route doesn't erase the avoidance.
  void noteAlprAvoided(int count) {
    if (_active && count > _alprAvoided) _alprAvoided = count;
  }

  /// The trip arrived within its ETA window (feeds the Time Lord behaviour).
  void noteOnTimeArrival(bool onTime) {
    if (_active) _onTimeArrival = onTime;
  }

  // --- MAIN ENTRY ---

  /// Feeds one GPS [pos] into the tracker. [speedLimitMph] is the current
  /// road's posted limit if known (null = unknown — the ratio sample is
  /// skipped). [userId] is stamped onto the metrics. Returns a
  /// [FinishedSession] only on the position that ENDS a trip, else null.
  FinishedSession? recordPosition(
    Position pos, {
    double? speedLimitMph,
    required String userId,
  }) {
    final double speed = math.max(0.0, pos.speed); // m/s, clamp GPS negatives
    final DateTime now = pos.timestamp;

    // Not driving yet: wait for sustained motion to start a trip.
    if (!_active) {
      if (speed >= tripStartSpeedMps) _beginTrip(now);
      _lastPos = pos;
      return null;
    }

    // Active trip: fold this sample into the running totals.
    _accumulate(pos, speed, now, speedLimitMph);

    // Stop detection: stayed slow long enough → finish the trip.
    FinishedSession? finished;
    if (speed < tripStopSpeedMps) {
      _belowStopSince ??= now;
      if (now.difference(_belowStopSince!).inSeconds >= tripStopGraceSeconds) {
        finished = _finishTrip(userId);
      }
    } else {
      _belowStopSince = null; // moving again — reset the stop timer
    }

    _lastPos = pos;
    return finished;
  }

  // --- LIFECYCLE HELPERS ---

  void _beginTrip(DateTime now) {
    _resetAccumulators();
    _active = true;
    _tripStart = now;
  }

  void _accumulate(
    Position pos,
    double speed,
    DateTime now,
    double? limitMph,
  ) {
    _foldInterval(pos, speed, now);
    _foldSpeedStats(speed, limitMph);
  }

  /// Distance, hard-event, and time-attribution math that needs the previous
  /// sample. Kept ≤2 levels of nesting per PRODUCT_BRIEF.
  void _foldInterval(Position pos, double speed, DateTime now) {
    final Position? last = _lastPos;
    if (last == null) return;

    final double dtSec = now.difference(last.timestamp).inMilliseconds / 1000.0;
    if (dtSec <= 0 || dtSec > maxGpsGapSeconds) return; // ignore gaps/dupes

    _distanceMeters += const Distance().as(
      LengthUnit.Meter,
      LatLng(last.latitude, last.longitude),
      LatLng(pos.latitude, pos.longitude),
    );

    // Hard brake / accel from the speed delta over this interval.
    final double accel = (speed - math.max(0.0, last.speed)) / dtSec;
    if (accel <= -hardBrakeMps2) _hardBrakes++;
    if (accel >= hardAccelMps2) _hardAccels++;

    // Time attribution only while genuinely moving.
    if (speed <= tripStopSpeedMps) return;
    final double dtMillis = dtSec * 1000.0;
    _movingMillis += dtMillis;
    if (_isNight(now)) _nightMillis += dtMillis;
    if (speed >= highwaySpeedMps) {
      _highwayMillis += dtMillis;
    } else if (speed <= backRoadSpeedMps) {
      _backRoadMillis += dtMillis;
    }
  }

  void _foldSpeedStats(double speed, double? limitMph) {
    _speedSumMps += speed;
    _speedSamples++;
    if (speed > _maxSpeedMps) _maxSpeedMps = speed;
    if (limitMph != null && limitMph > 0) {
      _ratioSum += (speed * metersPerSecondToMph) / limitMph;
      _ratioSamples++;
    }
  }

  /// Builds the [FinishedSession] and resets for the next trip. Returns null
  /// (and still resets) if the trip was too short to count.
  FinishedSession? _finishTrip(String userId) {
    final DateTime start = _tripStart ?? DateTime.now();
    final double distance = _distanceMeters;

    if (distance < tripMinDistanceMeters) {
      _resetAccumulators();
      _active = false;
      return null;
    }

    final double movingTotal = _movingMillis > 0 ? _movingMillis : 1.0;
    final double aggression = math.min(
      1.0,
      (_hardBrakes + _hardAccels) / aggressionEventsForMax,
    );

    final SessionMetrics metrics = SessionMetrics(
      sessionId: '', // assigned by the database on insert
      userId: userId,
      startedAt: start,
      endedAt: DateTime.now(),
      avgSpeedRatio: _ratioSamples > 0 ? _ratioSum / _ratioSamples : 1.0,
      hardBrakeCount: _hardBrakes,
      hardAccelCount: _hardAccels,
      nightDrivingFraction: _nightMillis / movingTotal,
      highwayFraction: _highwayMillis / movingTotal,
      backRoadFraction: _backRoadMillis / movingTotal,
      hazardReportsCount: _hazardReports,
      alprAvoidanceCount: _alprAvoided,
      rerouteCount: _reroutes,
      onTimeArrival: _onTimeArrival,
    );

    final FinishedSession result = FinishedSession(
      metrics: metrics,
      distanceMeters: distance,
      averageSpeedMps: _speedSamples > 0 ? _speedSumMps / _speedSamples : 0.0,
      maxSpeedMps: _maxSpeedMps,
      aggressionScore: aggression,
    );

    _resetAccumulators();
    _active = false;
    return result;
  }

  bool _isNight(DateTime t) {
    final int h = t.toLocal().hour;
    return h >= nightStartHour || h < nightEndHour;
  }

  void _resetAccumulators() {
    _tripStart = null;
    _belowStopSince = null;
    _distanceMeters = 0;
    _maxSpeedMps = 0;
    _speedSumMps = 0;
    _speedSamples = 0;
    _ratioSum = 0;
    _ratioSamples = 0;
    _hardBrakes = 0;
    _hardAccels = 0;
    _nightMillis = 0;
    _movingMillis = 0;
    _highwayMillis = 0;
    _backRoadMillis = 0;
    _hazardReports = 0;
    _alprAvoided = 0;
    _reroutes = 0;
    _onTimeArrival = false;
  }
}
