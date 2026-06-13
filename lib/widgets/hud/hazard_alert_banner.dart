// hazard_alert_banner.dart — Proximity alert banner shown when the user
// enters a 2-mile radius of a confirmed hazard.
//
// PRODUCT_BRIEF rules honored:
//   • Auto-dismisses after [hazardAlertAutoDismissSeconds] — zero taps needed.
//   • Never appears during navigation with text that requires reading.
//     (Short, icon-led layout is readable at a glance.)
//   • Different color per hazard type (ALPR = plum, crash = red, etc.)
//   • Sound is played by HazardSoundService before this widget renders;
//     this widget is purely visual.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../models/hazard_model.dart';
import '../../providers/hazard_provider.dart';
import '../../theme/migo_theme.dart';
import '../hazard_icons/hazard_icon.dart';

// --- WIDGET ---

/// Displays the top-most active alert from [activeHazardAlertsProvider].
/// Fades in, lives for [hazardAlertAutoDismissSeconds] seconds, fades out,
/// then removes itself from the queue. Stacks do not overlap — only one
/// banner is shown at a time; older ones are dismissed first.
class HazardAlertBanner extends ConsumerStatefulWidget {
  /// Creates the alert banner for [hazard].
  const HazardAlertBanner({super.key, required this.hazard});

  final Hazard hazard;

  @override
  ConsumerState<HazardAlertBanner> createState() => _HazardAlertBannerState();
}

class _HazardAlertBannerState extends ConsumerState<HazardAlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _opacity;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();

    // Auto-dismiss after the configured duration.
    _dismissTimer = Timer(
      Duration(seconds: hazardAlertAutoDismissSeconds),
      _dismiss,
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _anim.reverse();
    if (mounted) {
      dismissHazardAlert(ref, widget.hazard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = HazardIcon.colorFor(widget.hazard.type);
    final IconData icon = HazardIcon.iconFor(widget.hazard.type);
    final String label = HazardIcon.labelFor(widget.hazard.type);

    return FadeTransition(
      opacity: _opacity,
      child: GestureDetector(
        // Allow manual early dismiss by tapping the banner.
        onTap: _dismiss,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _subtitleFor(widget.hazard.type),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Progress bar showing time until auto-dismiss.
              _DismissCountdown(
                duration: Duration(seconds: hazardAlertAutoDismissSeconds),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(HazardType type) {
    return switch (type) {
      HazardType.crash => 'Ahead on your route — slow down',
      HazardType.alprCamera => 'License plate reader nearby',
      HazardType.debris => 'Watch the road surface',
      HazardType.ice => 'Slippery conditions ahead',
      HazardType.construction => 'Construction zone — merge early',
      HazardType.speedTrap => 'Speed enforcement reported nearby',
      HazardType.generalDisturbance => 'Disturbance reported ahead',
    };
  }
}

// ============================================================
// COUNTDOWN INDICATOR
// ============================================================

/// A circular progress indicator that counts down the dismiss timer.
/// Gives the driver a visual "this will go away" cue without needing to tap.
class _DismissCountdown extends StatefulWidget {
  const _DismissCountdown({required this.duration});
  final Duration duration;

  @override
  State<_DismissCountdown> createState() => _DismissCountdownState();
}

class _DismissCountdownState extends State<_DismissCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext ctx, _) => CircularProgressIndicator(
          value: 1 - _ctrl.value,
          strokeWidth: 2.5,
          color: Colors.white.withValues(alpha: 0.6),
          backgroundColor: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

// ============================================================
// BANNER STACK — renders all active alerts, top-most first
// ============================================================

/// Wraps [activeHazardAlertsProvider] and renders up to one banner at a time.
/// Once the user drives past a hazard and the banner dismisses, the next one
/// (if any) slides in. Stacking more than one would be too distracting while
/// driving — PRODUCT_BRIEF: no distracting animations in active nav.
class HazardAlertStack extends ConsumerWidget {
  /// Creates the stack. Place this in the map screen's Stack widget.
  const HazardAlertStack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the watcher so it stays alive while this widget is on screen.
    ref.watch(hazardAlertWatcherProvider);

    final List<Hazard> alerts = ref.watch(activeHazardAlertsProvider);
    if (alerts.isEmpty) return const SizedBox.shrink();

    // Show only the first (oldest) pending alert.
    return HazardAlertBanner(key: ValueKey<String>(alerts.first.id), hazard: alerts.first);
  }
}
