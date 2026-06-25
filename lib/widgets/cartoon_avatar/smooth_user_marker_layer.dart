// smooth_user_marker_layer.dart — The user's car marker, predicted forward.
//
// Raw GPS arrives in discrete fixes, so placing the marker straight on each fix
// makes it teleport, and gliding toward each (old) fix makes it lag and surge.
// Instead we DEAD-RECKON: between fixes we keep moving the marker forward from
// the last fix at the measured speed + heading (what Waze/Google do), then
// re-anchor on each new (Kalman-smoothed) fix. The result is continuous motion
// that stays near the true position — no stutter, minimal lag.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../constants.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import 'user_location_marker.dart';

/// A flutter_map layer that renders the user's avatar and predicts its motion
/// between GPS fixes.
class SmoothUserMarkerLayer extends ConsumerStatefulWidget {
  const SmoothUserMarkerLayer({super.key});

  @override
  ConsumerState<SmoothUserMarkerLayer> createState() =>
      _SmoothUserMarkerLayerState();
}

class _SmoothUserMarkerLayerState extends ConsumerState<SmoothUserMarkerLayer>
    with SingleTickerProviderStateMixin {
  // Rebuild every frame so the predicted position advances smoothly.
  late final Ticker _ticker = createTicker((Duration _) {
    if (mounted) setState(() {});
  })..start();

  LatLng? _anchor; // last smoothed fix
  double _speed = 0; // m/s
  double _heading = 0; // degrees (direction of travel)
  bool _hasHeading = false;
  DateTime _anchorTime = DateTime.now();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Records a fresh fix as the new dead-reckoning anchor.
  void _onFix(Position p) {
    _anchor = LatLng(p.latitude, p.longitude);
    _speed = (p.speed.isFinite && p.speed > 0) ? p.speed : 0;
    if (p.heading.isFinite && p.heading >= 0) {
      _heading = p.heading;
      _hasHeading = true;
    }
    _anchorTime = DateTime.now();
  }

  /// Marker position right now: the anchor projected forward by speed × elapsed
  /// along the heading. Holds still when parked or heading is unknown, and caps
  /// how far it will project without a fresh fix.
  LatLng? _displayedPoint() {
    final LatLng? a = _anchor;
    if (a == null) return null;
    if (!_hasHeading || _speed < tripStopSpeedMps) return a;
    final double dtSec =
        DateTime.now().difference(_anchorTime).inMilliseconds / 1000.0;
    final double secs = dtSec.clamp(0.0, markerPredictMaxSeconds);
    final double dist = _speed * secs;
    if (dist < 0.5) return a;
    return const Distance().offset(a, dist, _heading);
  }

  /// Marker size scaled by zoom (~25% smaller than the original per feedback).
  double _sizeForZoom(double zoom) {
    final double scale = math.pow(1.4, zoom - 15.0).toDouble();
    return (45.0 * scale).clamp(22.0, 60.0);
  }

  @override
  Widget build(BuildContext context) {
    // Re-anchor whenever a fresh GPS fix arrives.
    ref.listen<AsyncValue<Position>>(positionStreamProvider,
        (AsyncValue<Position>? prev, AsyncValue<Position> next) {
      final Position? p = next.valueOrNull;
      if (p != null) _onFix(p);
    });

    final Position? pos = ref.watch(positionStreamProvider).valueOrNull;
    final double zoom = ref.watch(currentZoomProvider);

    if (_anchor == null && pos == null) return const SizedBox.shrink();

    final double sz = _sizeForZoom(zoom);
    final LatLng point = _displayedPoint() ??
        (pos != null ? LatLng(pos.latitude, pos.longitude) : _anchor!);

    return MarkerLayer(
      markers: <Marker>[
        Marker(
          point: point,
          width: sz,
          height: sz,
          rotate: true,
          child: const UserLocationMarker(),
        ),
      ],
    );
  }
}
