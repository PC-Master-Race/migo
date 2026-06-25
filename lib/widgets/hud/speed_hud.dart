// speed_hud.dart — The on-map speed display: current GPS speed in mph and
// the road's speed limit from OSM ("Unknown" when OSM has no data).
// Big, glanceable, no interaction required — HUD elements never demand taps.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/location_provider.dart';
import '../../providers/speed_limit_provider.dart';

// --- WIDGET ---

/// Floating speed readout for the map screen.
class SpeedHud extends ConsumerWidget {
  /// Creates the speed HUD.
  const SpeedHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int currentSpeedMph = ref.watch(displaySpeedMphProvider);
    final String speedLimitLabel = ref.watch(speedLimitLabelProvider);

    // Theme-aware text color so the readout stays legible on the Card surface
    // in both light and dark mode (dark ink on light card / light ink on dark).
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Current speed — the dominant element, readable at a glance.
            Text(
              '$currentSpeedMph',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text('mph', style: TextStyle(fontSize: 12, color: ink)),
            const SizedBox(height: 4),
            // Speed limit from OSM — gracefully "Unknown" when missing.
            Text(
              'Limit: $speedLimitLabel',
              style: TextStyle(fontSize: 13, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
