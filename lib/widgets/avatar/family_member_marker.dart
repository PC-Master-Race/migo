// family_member_marker.dart — Map marker for a family member's live position.
// Shows their chibi avatar (archetype-based) with their display name below.
// Tapping the marker shows a small card with name, speed, and last-seen time.

import 'package:flutter/material.dart';

import '../../models/archetype_model.dart';
import '../../models/family_model.dart';
import '../../theme/bravo_theme.dart';
import 'avatar_painter.dart';

class FamilyMemberMarker extends StatelessWidget {
  const FamilyMemberMarker({
    super.key,
    required this.member,
    required this.location,
    this.onTap,
  });

  final FamilyMember member;
  final FamilyLocation location;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DrivingArchetype archetype = _parseArchetype(member.archetype);
    final bool isMoving = location.speedMps > 1.0; // >3.6 km/h = moving

    return GestureDetector(
      onTap: onTap ?? () => _showMemberCard(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Avatar with optional movement ring
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (isMoving)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: migoTeal.withAlpha(180), width: 2),
                  ),
                ),
              AvatarWidget(archetype: archetype, size: 48),
            ],
          ),
          const SizedBox(height: 2),
          // Name label
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(170),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              member.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showMemberCard(BuildContext context) {
    final String speed = location.speedMps < 0.5
        ? 'Parked'
        : '${(location.speedMps * 2.237).round()} mph';
    final Duration ago =
        DateTime.now().difference(location.updatedAt);
    final String lastSeen = ago.inSeconds < 60
        ? '${ago.inSeconds}s ago'
        : '${ago.inMinutes}m ago';

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          member.displayName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _infoRow('Speed', speed),
            _infoRow('Updated', lastSeen),
            _infoRow(
                'Status', location.speedMps > 1 ? 'Driving' : 'Parked'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                const Text('Close', style: TextStyle(color: migoTeal)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Text('$label: ',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  DrivingArchetype _parseArchetype(String? name) {
    if (name == null) return DrivingArchetype.zenMaster;
    try {
      return DrivingArchetype.values.byName(name);
    } catch (_) {
      return DrivingArchetype.zenMaster;
    }
  }
}
