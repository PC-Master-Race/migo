// smooth_user_marker_layer.dart — The user's car marker, but it GLIDES.
//
// Raw GPS arrives in discrete jumps, so a marker placed directly at each fix
// teleports/hops across the map. This layer tweens the marker's position from
// where it currently appears to each new fix at a constant rate, so the avatar
// slides smoothly along the road instead of stuttering.
//
// Scope: this smooths only the marker. The follow-camera still centers on the
// raw fix (small steps now that the GPS distance filter is 3 m). A future
// refinement could glide the camera too.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import 'user_location_marker.dart';

/// A flutter_map layer that renders the user's avatar marker and animates its
/// position between GPS fixes.
class SmoothUserMarkerLayer extends ConsumerStatefulWidget {
  const SmoothUserMarkerLayer({super.key});

  @override
  ConsumerState<SmoothUserMarkerLayer> createState() =>
      _SmoothUserMarkerLayerState();
}

class _SmoothUserMarkerLayerState extends ConsumerState<SmoothUserMarkerLayer>
    with SingleTickerProviderStateMixin {
  // One glide segment lasts this long. Kept short so the marker stays close to
  // the true position; if fixes arrive faster, each new fix restarts the glide
  // from the current interpolated point, giving continuous motion.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  LatLng? _from; // where the current glide started
  LatLng? _to; // the latest fix we're gliding toward

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  /// Begins a new glide from the currently-displayed point to [next].
  void _glideTo(LatLng next) {
    _from = _displayedPoint() ?? next;
    _to = next;
    _glide
      ..reset()
      ..forward();
  }

  /// The point to render right now — a linear blend from [_from] to [_to].
  /// Linear (not eased) so a moving car keeps a steady pace across fixes.
  LatLng? _displayedPoint() {
    if (_from == null || _to == null) return _to ?? _from;
    final double t = _glide.value;
    return LatLng(
      _from!.latitude + (_to!.latitude - _from!.latitude) * t,
      _from!.longitude + (_to!.longitude - _from!.longitude) * t,
    );
  }

  /// Marker size scaled by zoom — mirrors map_screen's _markerSizeForZoom.
  double _sizeForZoom(double zoom) {
    final double scale = math.pow(1.4, zoom - 15.0).toDouble();
    return (60.0 * scale).clamp(30.0, 80.0);
  }

  @override
  Widget build(BuildContext context) {
    // Kick off a new glide whenever a fresh GPS fix arrives.
    ref.listen<AsyncValue<Position>>(positionStreamProvider,
        (AsyncValue<Position>? prev, AsyncValue<Position> next) {
      final Position? p = next.valueOrNull;
      if (p == null) return;
      final LatLng fix = LatLng(p.latitude, p.longitude);
      if (_to == null || fix != _to) _glideTo(fix);
    });

    final Position? pos = ref.watch(positionStreamProvider).valueOrNull;
    final double zoom = ref.watch(currentZoomProvider);

    // Nothing to show until the first fix.
    if (pos == null && _to == null) return const SizedBox.shrink();

    final double sz = _sizeForZoom(zoom);

    return AnimatedBuilder(
      animation: _glide,
      builder: (BuildContext context, Widget? _) {
        final LatLng point = _displayedPoint() ??
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
      },
    );
  }
}
