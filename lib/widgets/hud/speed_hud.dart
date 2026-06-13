// speed_hud.dart — The on-map speed display: current GPS speed in mph and
// the road's speed limit from OSM ("Unknown" when OSM has no data).
// Big, glanceable, no interaction required — HUD elements never demand taps.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/location_provider.dart';
import '../../providers/speed_limit_provider.dart';
import '../../theme/bravo_theme.dart';

// --- WIDGET ---

/// Floating speed readout for the map screen.
class SpeedHud extends ConsumerWidget {
  /// Creates the speed HUD.
  const SpeedHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int currentSpeedMph = ref.watch(displaySpeedMphProvider);
    final String speedLimitLabel = ref.watch(speedLimitLabelProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Current speed — the dominant element, readable at a glance.
            Text(
              '$currentSpeedMph',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: migoInk,
              ),
            ),
            const Text('mph', style: TextStyle(fontSize: 12, color: migoInk)),
            const SizedBox(height: 4),
            // Speed limit from OSM — gracefully "Unknown" when missing.
            Text(
              'Limit: $speedLimitLabel',
              style: const TextStyle(fontSize: 13, color: migoInk),
            ),
          ],
        ),
      ),
    );
  }
}
