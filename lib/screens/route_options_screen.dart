// route_options_screen.dart — Mid-route route preference toggles.
// Every toggle write goes to [routePreferencesProvider] which triggers
// [_prefAutoRecalcProvider] to recalculate the active route immediately.
// Shown as a bottom sheet from the map screen search bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/route_model.dart';
import '../providers/routing_provider.dart';
import '../theme/bravo_theme.dart';

// --- SCREEN ---

/// Route option toggles. Can be shown as a full screen or (preferred) as a
/// bottom sheet via [RouteOptionsScreen.showSheet].
class RouteOptionsScreen extends ConsumerWidget {
  /// Creates the route options screen.
  const RouteOptionsScreen({super.key});

  /// Route name for navigator push (used when NOT a bottom sheet).
  static const String routeName = '/route-options';

  /// Shows the route options as a draggable bottom sheet from [context].
  static Future<void> showSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: migoCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const RouteOptionsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RoutePreferences prefs = ref.watch(routePreferencesProvider);
    final AsyncValue<BravoRoute?> routeState = ref.watch(activeRouteProvider);
    final BravoRoute? route = routeState.valueOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: migoInk.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Route summary (distance + ETA)
            if (route != null) ...<Widget>[
              _RouteSummaryCard(route: route),
              const SizedBox(height: 16),
            ],

            // Recalculating indicator
            if (routeState.isLoading) ...<Widget>[
              const _RecalculatingBadge(),
              const SizedBox(height: 12),
            ],

            // Optimization mode
            _SectionLabel('Optimize for'),
            const SizedBox(height: 8),
            _OptimizationSelector(
              selected: prefs.optimizeFor,
              onChanged: (RouteOptimization opt) {
                ref.read(routePreferencesProvider.notifier).state =
                    prefs.copyWith(optimizeFor: opt);
              },
            ),
            const SizedBox(height: 20),

            // Avoid toggles
            _SectionLabel('Avoid'),
            const SizedBox(height: 4),
            _AvoidToggle(
              label: 'Freeways',
              icon: Icons.no_crash_rounded,
              value: prefs.avoidFreeways,
              onChanged: (bool v) => ref
                  .read(routePreferencesProvider.notifier)
                  .state = prefs.copyWith(avoidFreeways: v),
            ),
            _AvoidToggle(
              label: 'Tolls',
              icon: Icons.money_off_rounded,
              value: prefs.avoidTolls,
              onChanged: (bool v) => ref
                  .read(routePreferencesProvider.notifier)
                  .state = prefs.copyWith(avoidTolls: v),
            ),
            _AvoidToggle(
              label: 'Popular routes (Google/Waze traffic)',
              icon: Icons.people_outline_rounded,
              value: prefs.avoidPopularRoutes,
              onChanged: (bool v) => ref
                  .read(routePreferencesProvider.notifier)
                  .state = prefs.copyWith(avoidPopularRoutes: v),
            ),
            _AvoidToggle(
              label: 'ALPR cameras',
              icon: Icons.no_photography_rounded,
              iconColor: migoPlum,
              value: prefs.avoidAlprCameras,
              onChanged: (bool v) => ref
                  .read(routePreferencesProvider.notifier)
                  .state = prefs.copyWith(avoidAlprCameras: v),
            ),

            const SizedBox(height: 16),

            // Cancel navigation
            if (route != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel navigation'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: migoDanger,
                    side: const BorderSide(color: migoDanger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    ref.read(activeRouteProvider.notifier).clear();
                    ref.read(destinationProvider.notifier).state = null;
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- ROUTE SUMMARY ---

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({required this.route});
  final BravoRoute route;

  @override
  Widget build(BuildContext context) {
    final String distMiles =
        (route.distanceMeters / 1609.344).toStringAsFixed(1);
    final int minutes = (route.estimatedSeconds / 60).round();
    final String eta = minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} hr ${minutes % 60} min';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: migoTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.route_rounded, color: migoTeal),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                eta,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: migoInk,
                ),
              ),
              Text(
                '$distMiles miles',
                style: TextStyle(
                  fontSize: 13,
                  color: migoInk.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- RECALCULATING BADGE ---

class _RecalculatingBadge extends StatelessWidget {
  const _RecalculatingBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: migoAmber,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Recalculating…',
          style: TextStyle(
            fontSize: 13,
            color: migoInk.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// --- OPTIMIZATION SELECTOR ---

class _OptimizationSelector extends StatelessWidget {
  const _OptimizationSelector({
    required this.selected,
    required this.onChanged,
  });

  final RouteOptimization selected;
  final ValueChanged<RouteOptimization> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RouteOptimization.values.map((RouteOptimization opt) {
        final bool active = opt == selected;
        return ChoiceChip(
          label: Text(_labelFor(opt)),
          selected: active,
          onSelected: (_) => onChanged(opt),
          selectedColor: migoCoral.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: active ? migoCoral : migoInk.withValues(alpha: 0.7),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: active ? migoCoral : migoInk.withValues(alpha: 0.2),
          ),
          backgroundColor: Colors.white,
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  String _labelFor(RouteOptimization opt) {
    return switch (opt) {
      RouteOptimization.fastest => 'Fastest',
      RouteOptimization.shortest => 'Shortest',
      RouteOptimization.mostFuelEfficient => 'Fuel efficient',
      RouteOptimization.fewestStops => 'Fewest stops',
    };
  }
}

// --- AVOID TOGGLE ROW ---

class _AvoidToggle extends StatelessWidget {
  const _AvoidToggle({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: iconColor ?? migoInk.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: migoInk),
          ),
        ],
      ),
      value: value,
      activeColor: migoCoral,
      onChanged: onChanged,
    );
  }
}

// --- SECTION LABEL ---

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: migoInk.withValues(alpha: 0.5),
      ),
    );
  }
}
