// avatar_picker_sheet.dart — Choose which EARNED archetype to display.
//
// Archetypes accumulate in ArchetypeProfile.unlockedArchetypes as driving
// habits earn them; this sheet is the trophy cabinet. Locked archetypes show
// as dark silhouettes with a lock — visible so there's something to chase,
// unnamed so discovery stays fun. "Automatic" follows the current dominant
// archetype (the default behavior since Phase 4).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../models/archetype_model.dart';
import '../../providers/archetype_provider.dart';
import '../../theme/bravo_theme.dart';
import 'avatar_painter.dart';

/// Opens the picker. Safe to call from any context under the root navigator.
void showAvatarPickerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AvatarPickerSheet(),
  );
}

class _AvatarPickerSheet extends ConsumerWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color panel = dark ? migoDarkSurface : Colors.white;
    final Color ink = dark ? Colors.white : const Color(0xFF1C1712);

    final ArchetypeProfile? profile =
        ref.watch(archetypeNotifierProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();

    // Creator builds own the whole garage — needed to test every look.
    final List<DrivingArchetype> unlocked =
        creatorMode ? DrivingArchetype.values : profile.unlockedArchetypes;
    debugPrint('[avatar] picker: creatorMode=$creatorMode '
        'unlocked=${unlocked.length} selected=${profile.selectedArchetype} '
        'sessions=${profile.sessionCount}');

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Your avatars',
                style: TextStyle(
                    color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              creatorMode
                  ? 'Creator mode — the whole garage is yours.'
                  : '${unlocked.length} of ${DrivingArchetype.values.length}'
                      ' earned — your driving habits unlock the rest.',
              style: TextStyle(
                  color: ink.withValues(alpha: 0.55), fontSize: 12),
            ),
            const SizedBox(height: 16),

            // "Automatic" — follow the current dominant archetype.
            _AutomaticTile(
              selected: profile.selectedArchetype == null,
              current: profile.currentArchetype,
              ink: ink,
              onTap: () {
                ref
                    .read(archetypeNotifierProvider.notifier)
                    .selectArchetype(null);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 12),

            // The trophy grid.
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: DrivingArchetype.values.map((DrivingArchetype a) {
                final bool owned = unlocked.contains(a);
                final bool active = profile.selectedArchetype == a;
                return _ArchetypeCell(
                  archetype: a,
                  owned: owned,
                  active: active,
                  ink: ink,
                  onTap: owned
                      ? () {
                          ref
                              .read(archetypeNotifierProvider.notifier)
                              .selectArchetype(a);
                          Navigator.of(context).pop();
                        }
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomaticTile extends StatelessWidget {
  const _AutomaticTile({
    required this.selected,
    required this.current,
    required this.ink,
    required this.onTap,
  });

  final bool selected;
  final DrivingArchetype current;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? migoCoral : ink.withValues(alpha: 0.15),
              width: selected ? 2 : 1),
        ),
        child: Row(
          children: <Widget>[
            AvatarWidget(archetype: current, size: 44, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Automatic',
                      style: TextStyle(
                          color: ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text(
                    'Follows your driving — right now: '
                    '${current.displayLabel}',
                    style: TextStyle(
                        color: ink.withValues(alpha: 0.55), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: migoCoral, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ArchetypeCell extends StatelessWidget {
  const _ArchetypeCell({
    required this.archetype,
    required this.owned,
    required this.active,
    required this.ink,
    required this.onTap,
  });

  final DrivingArchetype archetype;
  final bool owned;
  final bool active;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? migoCoral : ink.withValues(alpha: 0.12),
              width: active ? 2 : 1),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Locked = dark silhouette; a mystery worth chasing.
            owned
                ? AvatarWidget(archetype: archetype, size: 56, animate: false)
                : ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                        Color(0xFF555560), BlendMode.srcIn),
                    child: AvatarWidget(
                        archetype: archetype, size: 56, animate: false),
                  ),
            const SizedBox(height: 4),
            owned
                ? Text(
                    archetype.displayLabel.replaceFirst('The ', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ink,
                        fontSize: 10,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600),
                  )
                : Icon(Icons.lock_rounded,
                    size: 12, color: ink.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}
