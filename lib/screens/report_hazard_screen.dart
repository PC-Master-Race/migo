// report_hazard_screen.dart — Bottom sheet for reporting a new hazard.
// User selects a type from a 7-icon cartoon grid, then submits at their
// current GPS position. Loading state shown during submit; success toast
// on confirmation. ALPR quick-report is also accessible from here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/hazard_model.dart';
import '../providers/hazard_provider.dart';
import '../providers/driving_session_provider.dart';
import '../providers/location_provider.dart';
import '../theme/bravo_theme.dart';
import '../widgets/hazard_icons/hazard_icon.dart';

// --- SCREEN ---

/// The hazard reporting bottom sheet. Open via [ReportHazardSheet.show].
class ReportHazardSheet extends ConsumerWidget {
  /// Creates the report sheet.
  const ReportHazardSheet({super.key});

  /// Opens the sheet as a modal bottom sheet from [context].
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: migoCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext ctx) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const ReportHazardSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HazardType? selected = ref.watch(selectedHazardTypeProvider);
    final AsyncValue<void> submitState = ref.watch(reportHazardProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Drag handle
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

            // Header
            const Text(
              'Report a hazard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: migoInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'What do you see ahead?',
              style: TextStyle(
                fontSize: 13,
                color: migoInk.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),

            // 7-icon hazard type grid (2 columns)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
              children: HazardType.values.map((HazardType type) {
                final bool isSelected = selected == type;
                final Color color = HazardIcon.colorFor(type);
                return _HazardTypeButton(
                  type: type,
                  isSelected: isSelected,
                  color: color,
                  onTap: () => ref
                      .read(selectedHazardTypeProvider.notifier)
                      .state = isSelected ? null : type,
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Submit button
            if (submitState.isLoading)
              const Center(
                child: CircularProgressIndicator(color: migoCoral),
              )
            else if (submitState.hasError)
              _ErrorMessage(
                message: submitState.error.toString().replaceAll(
                      'HazardServiceException: ',
                      '',
                    ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Report at my location'),
                  onPressed: selected == null
                      ? null
                      : () => _submit(context, ref, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        selected != null ? HazardIcon.colorFor(selected) : null,
                    disabledBackgroundColor: migoInk.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // ALPR quick-report link
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.no_photography_rounded,
                    size: 16, color: migoPlum),
                label: const Text(
                  'Quick-report an ALPR camera',
                  style: TextStyle(color: migoPlum, fontSize: 13),
                ),
                onPressed: () => _submitAlpr(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    HazardType type,
  ) async {
    final position = ref.read(positionStreamProvider).valueOrNull;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS fix — try again in a moment.')),
      );
      return;
    }

    await ref.read(reportHazardProvider.notifier).submit(
          type,
          LatLng(position.latitude, position.longitude),
        );

    if (!context.mounted) return;

    if (!ref.read(reportHazardProvider).hasError) {
      // Count this report toward the current trip (feeds the Scout archetype).
      ref.read(drivingSessionTrackerProvider).noteHazardReported();
      // Reset selection and close.
      ref.read(selectedHazardTypeProvider.notifier).state = null;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${HazardIcon.labelFor(type)} reported — thanks!',
          ),
          backgroundColor: HazardIcon.colorFor(type),
        ),
      );
    }
  }

  Future<void> _submitAlpr(BuildContext context, WidgetRef ref) async {
    await _submit(context, ref, HazardType.alprCamera);
  }
}

// --- HAZARD TYPE BUTTON ---

class _HazardTypeButton extends StatelessWidget {
  const _HazardTypeButton({
    required this.type,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final HazardType type;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : migoInk.withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            HazardIcon(type: type),
            const SizedBox(height: 6),
            Text(
              HazardIcon.labelFor(type),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : migoInk.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- ERROR MESSAGE ---

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: migoDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: migoDanger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: migoDanger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
