// smooth_user_marker_layer.dart — The user's car marker, predicted forward.
//
// Raw GPS arrives in discrete ~1 Hz fixes, so placing the marker straight on
// each fix makes it teleport. The previous approach (dead-reckon forward, then
// re-anchor hard on every fix) fixed the stutter but introduced RUBBER-BANDING:
// the marker projected ahead of the car, then teleported BACKWARD to each new
// (older, Kalman-lagged) fix. This version has three layers:
//
//   1. SNAP-TO-ROUTE (map matching): during navigation each fix is projected
//      onto the route polyline (within routeSnapMaxDistanceMeters) and the
//      heading comes from the ROAD segment, not GPS heading jitter. This is
//      the "glued to the road" behavior of Google/Waze.
//   2. DEAD-RECKONING: between fixes, the anchor is projected forward along
//      the heading at the measured speed (capped at markerPredictMaxSeconds).
//   3. DISPLAY EASING: the drawn marker exponentially chases the target
//      (tau = markerEaseTauSeconds) instead of jumping to it — re-anchor
//      discontinuities become a short glide, never a visible teleport.
//      Jumps beyond markerTeleportMeters snap instantly (real relocations).
//
// The eased position is also published to displayedPositionProvider so the
// map camera follows the same smooth point the avatar is drawn at.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../constants.dart';
import '../../models/route_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import '../../providers/routing_provider.dart';
import '../../services/routing_service.dart';
import 'user_location_marker.dart';

/// A flutter_map layer that renders the user's avatar: route-snapped,
/// dead-reckoned between fixes, and eased on screen.
class SmoothUserMarkerLayer extends ConsumerStatefulWidget {
  const SmoothUserMarkerLayer({super.key});

  @override
  ConsumerState<SmoothUserMarkerLayer> createState() =>
      _SmoothUserMarkerLayerState();
}

class _SmoothUserMarkerLayerState extends ConsumerState<SmoothUserMarkerLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick)..start();
  Duration _lastTick = Duration.zero;

  LatLng? _anchor; // last fix (route-snapped when navigating)
  double _speed = 0; // m/s
  double _heading = 0; // degrees (road bearing when snapped, else GPS)
  bool _hasHeading = false;
  DateTime _anchorTime = DateTime.now();

  /// What's actually drawn — eased toward the dead-reckoned target each frame.
  LatLng? _displayed;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Records a fresh fix as the new dead-reckoning anchor, snapping it (and
  /// the heading) onto the active route when we're on it.
  void _onFix(Position p) {
    LatLng fix = LatLng(p.latitude, p.longitude);
    final double speed = (p.speed.isFinite && p.speed > 0) ? p.speed : 0;
    double? heading =
        (p.heading.isFinite && p.heading >= 0) ? p.heading : null;

    // Map matching: while navigating, the route polyline is ground truth.
    final BravoRoute? route = ref.read(activeRouteProvider).valueOrNull;
    if (route != null && route.waypoints.length >= 2) {
      // Accuracy-adaptive threshold: in weak-signal areas fixes wander far
      // from the road even though the car is ON it. Trust the route harder
      // the worse the fix accuracy claims to be (capped — a 500 m cell fix
      // must not glue us to a route we may have left).
      final double accuracy =
          (p.accuracy.isFinite && p.accuracy > 0) ? p.accuracy : 0;
      final double snapThreshold = math.max(
        routeSnapMaxDistanceMeters,
        math.min(
            accuracy * routeSnapAccuracyFactor, routeSnapMaxDistanceCapMeters),
      );
      final RouteSnap? snap = snapToPolyline(fix, route.waypoints);
      if (snap != null && snap.distanceMeters <= snapThreshold) {
        fix = snap.point;
        // Road bearing beats GPS heading — it can't jitter mid-turn. Only
        // while moving: a parked car's "road direction" is meaningless.
        if (speed >= tripStopSpeedMps) heading = snap.headingDeg;
      }
    }

    _anchor = fix;
    _speed = speed;
    if (heading != null) {
      _heading = heading;
      _hasHeading = true;
    }
    _anchorTime = DateTime.now();
  }

  /// Dead-reckoned target: the anchor projected forward by speed × elapsed
  /// along the heading. Holds still when parked or heading is unknown.
  LatLng? _targetPoint() {
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

  /// Per-frame: ease the displayed position toward the target and publish it.
  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final double dtSec =
        ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;

    final LatLng? target = _targetPoint();
    if (target == null) return;

    final LatLng? current = _displayed;
    if (current == null) {
      _displayed = target;
    } else {
      final double gap =
          const Distance().as(LengthUnit.Meter, current, target);
      if (gap > markerTeleportMeters) {
        // Real relocation — don't animate the car across the map.
        _displayed = target;
      } else if (gap > 0.05) {
        // Exponential approach: frame-rate independent, converges within
        // ~3·tau, turns re-anchor jumps into a short glide.
        final double alpha = 1 - math.exp(-dtSec / markerEaseTauSeconds);
        _displayed = LatLng(
          current.latitude + (target.latitude - current.latitude) * alpha,
          current.longitude + (target.longitude - current.longitude) * alpha,
        );
      }
    }

    // Publish for the camera (map_screen follows this, not the raw fixes).
    ref.read(displayedPositionProvider.notifier).state = _displayed;
    setState(() {});
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

    if (_anchor == null && pos == null && _displayed == null) {
      return const SizedBox.shrink();
    }

    final double sz = _sizeForZoom(zoom);
    final LatLng point = _displayed ??
        _anchor ??
        LatLng(pos!.latitude, pos.longitude);

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
