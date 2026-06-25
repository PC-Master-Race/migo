// gas_station_marker.dart — Map pin for a gas station showing price badge.

import 'package:flutter/material.dart';

import '../../models/gas_model.dart';
import '../../theme/bravo_theme.dart';

class GasStationMarker extends StatelessWidget {
  const GasStationMarker({
    super.key,
    required this.station,
    required this.onTap,
    this.isSelected = false,
  });

  final GasStation station;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final double? price = station.regularPrice;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Price bubble
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? migoTeal : const Color(0xFF0288D1),
              borderRadius: BorderRadius.circular(10),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withAlpha(isSelected ? 100 : 60),
                  blurRadius: isSelected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.local_gas_station,
                    color: Colors.white, size: 14),
                Text(
                  price != null
                      ? '\$${price.toStringAsFixed(2)}'
                      : '---',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          // Pointer triangle
          CustomPaint(
            size: const Size(10, 5),
            painter: _TrianglePainter(
                isSelected ? migoTeal : const Color(0xFF0288D1)),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// POI marker — generic colored circle + icon
// ---------------------------------------------------------------------------

class PoiMarker extends StatelessWidget {
  const PoiMarker({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          CustomPaint(
            size: const Size(8, 4),
            painter: _TrianglePainter(color),
          ),
        ],
      ),
    );
  }
}
