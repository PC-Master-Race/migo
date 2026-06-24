// location_filter.dart — A lightweight Kalman filter for GPS coordinates.
//
// Android's fused location provider (which geolocator uses by default) already
// blends GPS + wifi + cell + sensors, but the stream it hands us still jitters
// and occasionally throws an outlier — a reflected signal that "teleports" the
// fix a block away. This filter sits on top of that stream and does what a
// navigation app's blue dot does: treat each fix as a noisy measurement, weight
// it by its accuracy, and produce one smooth, stable coordinate line.
//
// Model: the well-known KalmanLatLong approach — a 1st-order filter where the
// measurement noise is the GPS accuracy and the process (prediction) noise
// grows with elapsed time. Plus a hard outlier guard: a fix that implies a
// physically impossible speed is heavily distrusted so it can't yank the path.

import 'dart:math' as math;

import '../constants.dart';

/// Smooths a stream of raw GPS fixes. Create one per location stream.
class LocationKalmanFilter {
  double? _lat;
  double? _lng;
  int? _timestampMs;

  /// Current estimate variance in metres². Negative = uninitialised.
  double _variance = -1;

  /// True once a first fix has seeded the estimate.
  bool get hasEstimate => _variance >= 0;

  /// Feeds one raw fix and returns the smoothed `[latitude, longitude]`.
  /// [accuracyMetres] is the fix's horizontal accuracy (1-sigma).
  List<double> process(
    double lat,
    double lng,
    double accuracyMetres,
    int timestampMs,
  ) {
    double accuracy = accuracyMetres;
    if (accuracy < kalmanMinAccuracyMetres) accuracy = kalmanMinAccuracyMetres;

    // First fix — adopt it directly as the estimate.
    if (_variance < 0) {
      _lat = lat;
      _lng = lng;
      _timestampMs = timestampMs;
      _variance = accuracy * accuracy;
      return <double>[lat, lng];
    }

    // --- Predict step: uncertainty grows with the time since the last fix. ---
    final int dtMs = timestampMs - (_timestampMs ?? timestampMs);
    if (dtMs > 0) {
      final double dtSec = dtMs / 1000.0;
      _variance +=
          dtSec * kalmanProcessNoiseMetresPerSec * kalmanProcessNoiseMetresPerSec;
      _timestampMs = timestampMs;
    }

    // --- Outlier guard: distrust fixes that imply impossible speed. ---
    final double jumpMetres = _metresBetween(_lat!, _lng!, lat, lng);
    final double maxPlausibleMetres = math.max(
      kalmanMinAccuracyMetres,
      (dtMs / 1000.0) * kalmanMaxSpeedMetresPerSec,
    );
    if (jumpMetres > maxPlausibleMetres * kalmanOutlierFactor) {
      // Treat as a very inaccurate measurement so it barely moves the estimate.
      accuracy = accuracy * 8.0;
    }

    // --- Update step: blend the estimate toward the measurement. ---
    final double k = _variance / (_variance + accuracy * accuracy);
    _lat = _lat! + k * (lat - _lat!);
    _lng = _lng! + k * (lng - _lng!);
    _variance = (1 - k) * _variance;

    return <double>[_lat!, _lng!];
  }

  /// Flat-earth metre distance — accurate enough over the short spans between
  /// consecutive fixes.
  double _metresBetween(double lat1, double lng1, double lat2, double lng2) {
    const double metresPerDegLat = 111320.0;
    final double metresPerDegLng =
        111320.0 * math.cos(lat1 * math.pi / 180.0);
    final double dLat = (lat2 - lat1) * metresPerDegLat;
    final double dLng = (lng2 - lng1) * metresPerDegLng;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}
