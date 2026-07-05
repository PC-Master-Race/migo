// user_location_marker.dart — The user's chibi avatar marker on the map.
// Phase 4: replaced the placeholder dot with the archetype AvatarPainter.
// The head peeks out of the sunroof just like Waze's driver avatar.
// Heading rotation is applied by the parent MarkerLayer via `rotate: true`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../models/archetype_model.dart';
import '../../models/bravo_model.dart';
import '../../providers/archetype_provider.dart';
import '../../providers/bravo_provider.dart';
import '../../theme/bravo_theme.dart';
import '../avatar/avatar_painter.dart';
import '../avatar/avatar_picker_sheet.dart';
import '../avatar/mystery_egg.dart';

// ---------------------------------------------------------------------------
// UserLocationMarker
// ---------------------------------------------------------------------------

/// The user's map marker: a chibi avatar car sized to [userMarkerSize * 1.5].
/// Reads the current archetype + equipped cosmetic from Riverpod providers.
/// Falls back to a coral dot if the profile hasn't loaded yet.
class UserLocationMarker extends ConsumerWidget {
  const UserLocationMarker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ArchetypeProfile> profileAsync =
        ref.watch(archetypeNotifierProvider);
    final AsyncValue<List<UnlockedCosmetic>> cosmeticsAsync =
        ref.watch(cosmeticsProvider);

    // LayoutBuilder makes the avatar fill whatever Marker size map_screen
    // allocates, so zoom-scaling works without any changes here.
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        final double size = constraints.maxWidth.clamp(24.0, 200.0);

        return profileAsync.when(
          loading: () => _fallback(size),
          error: (_, __) => _fallback(size),
          data: (ArchetypeProfile profile) {
            // CREATOR EASTER EGG: Tux in a fedora in a go-kart. Only exists
            // in builds with CREATOR_MODE in env.json. Explicitly picking an
            // archetype from the pool overrides it; "Automatic" = Tux.
            if (creatorMode && profile.selectedArchetype == null) {
              return GestureDetector(
                onTap: () => showAvatarPickerSheet(ctx),
                child: AvatarWidget(
                  archetype: profile.currentArchetype,
                  size: size,
                  tux: true,
                ),
              );
            }

            // Pre-reveal: the avatar hasn't HATCHED yet. Until enough
            // sessions exist to earn a real archetype, show the mystery egg —
            // "Drive to discover your avatar," literally. An EXPLICIT pick
            // always wins over the egg (it was hiding selections).
            if (profile.selectedArchetype == null &&
                profile.rareArchetype == null &&
                profile.sessionCount < archetypeRevealSessionCount) {
              return GestureDetector(
                onTap: () => ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Still hatching — '
                        '${archetypeRevealSessionCount - profile.sessionCount}'
                        ' more drive${archetypeRevealSessionCount - profile.sessionCount == 1 ? '' : 's'} to reveal your avatar!'),
                    duration: const Duration(seconds: 3),
                  ),
                ),
                child: MysteryEggWidget(size: size),
              );
            }

            final List<UnlockedCosmetic> cosmetics =
                cosmeticsAsync.valueOrNull ?? <UnlockedCosmetic>[];
            final UnlockedCosmetic? equipped = cosmetics
                .where((UnlockedCosmetic c) => c.isEquipped)
                .toList()
                .firstOrNull;

            // Tap your own avatar to open the earned-archetype picker.
            return GestureDetector(
              onTap: () => showAvatarPickerSheet(ctx),
              child: AvatarWidget(
                // Respect the user's pick from their unlocked pool;
                // falls back to the earned dominant archetype.
                archetype: profile.displayArchetype,
                // When a rare archetype is unlocked it overrides the look.
                rareArchetype: profile.rareArchetype,
                size: size,
                // Show the unlockable the user has equipped (null = none).
                equippedCosmetic: equipped?.cosmeticId,
              ),
            );
          },
        );
      },
    );
  }

  Widget _fallback(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: migoCoral,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(blurRadius: 6, color: Colors.black26),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// BravosHudChip
// ---------------------------------------------------------------------------

/// A small Bravos balance chip for the map HUD.
/// Positioned in map_screen.dart — bottom-right, above the FABs.
class BravosHudChip extends ConsumerWidget {
  const BravosHudChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BravosBalance?> balanceAsync =
        ref.watch(bravosBalanceProvider);

    final int balance = balanceAsync.valueOrNull?.balance ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: migoTeal.withAlpha(120), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Bravo star icon
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD700),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'B',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatBalance(balance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(int b) {
    if (b >= 1000) {
      return '${(b / 1000).toStringAsFixed(1)}k';
    }
    return b.toString();
  }
}
