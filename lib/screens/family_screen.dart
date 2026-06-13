// family_screen.dart — Family group management for Bravo Maps.
// Phase 5: create/join groups via invite code, live location sharing toggle,
// member list with archetype avatars.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/archetype_model.dart';
import '../models/family_model.dart';
import '../providers/family_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/bravo_theme.dart';
import '../widgets/avatar/avatar_painter.dart';

class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});
  static const String routeName = '/family';

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FamilyGroup?> groupAsync = ref.watch(familyGroupProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text(
          'Family',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: groupAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: migoTeal)),
        error: (Object e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.read(familyGroupProvider.notifier).refresh()),
        data: (FamilyGroup? group) =>
            group == null ? _NoGroupView(this) : _GroupView(group, this),
      ),
    );
  }

  Future<void> createGroup() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(familyGroupProvider.notifier).createGroup(name);
      _nameController.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> joinByCode() async {
    final String code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character invite code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(familyGroupProvider.notifier).joinByCode(code);
      _codeController.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> leaveGroup() async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Leave group?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'You will stop sharing location with this group. '
              'You can rejoin any time with the invite code.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave',
                      style: TextStyle(color: migoDanger))),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(familyGroupProvider.notifier).leaveGroup();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// _NoGroupView — create or join
// ---------------------------------------------------------------------------

class _NoGroupView extends StatelessWidget {
  const _NoGroupView(this.state);
  final _FamilyScreenState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 16),
          // Illustration
          Center(
            child: AvatarWidget(
              archetype: DrivingArchetype.scout,
              size: 96,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Drive together',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'See your family\'s chibi avatars on the map in real time.\n'
            'Location stays private — only your group can see it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 36),

          // Create group
          _SectionLabel('Create a new group'),
          const SizedBox(height: 10),
          _DarkTextField(
            controller: state._nameController,
            hint: 'Group name (e.g. "The Garcias")',
            maxLength: 32,
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Create group',
            loading: state._isLoading,
            onPressed: state.createGroup,
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 24),

          // Join group
          _SectionLabel('Join an existing group'),
          const SizedBox(height: 10),
          _DarkTextField(
            controller: state._codeController,
            hint: 'Enter 6-character invite code',
            maxLength: 6,
            allCaps: true,
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Join group',
            loading: state._isLoading,
            color: migoAmber,
            onPressed: state.joinByCode,
          ),

          if (state._error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              state._error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: migoDanger, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GroupView — member list, sharing toggle, invite code
// ---------------------------------------------------------------------------

class _GroupView extends ConsumerWidget {
  const _GroupView(this.group, this.state);
  final FamilyGroup group;
  final _FamilyScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool sharing = ref.watch(locationSharingEnabledProvider);
    final AsyncValue<List<FamilyMember>> membersAsync =
        ref.watch(familyMembersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Group name
          Text(
            group.name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),

          // Location sharing toggle
          _SharingToggle(sharing: sharing, ref: ref),
          const SizedBox(height: 24),

          // Invite code card
          _InviteCodeCard(group: group, state: state),
          const SizedBox(height: 24),

          // Members list
          _SectionLabel('Members'),
          const SizedBox(height: 12),
          membersAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: migoTeal)),
            error: (e, _) => Text(e.toString(),
                style: const TextStyle(color: migoDanger)),
            data: (List<FamilyMember> members) => Column(
              children: members
                  .map((FamilyMember m) => _MemberTile(member: m))
                  .toList(),
            ),
          ),

          const SizedBox(height: 32),
          // Leave group
          OutlinedButton(
            onPressed: state._isLoading ? null : state.leaveGroup,
            style: OutlinedButton.styleFrom(
              foregroundColor: migoDanger,
              side: const BorderSide(color: migoDanger, width: 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Leave group'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SharingToggle extends StatelessWidget {
  const _SharingToggle({required this.sharing, required this.ref});
  final bool sharing;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: sharing
                ? migoTeal.withAlpha(120)
                : Colors.white12,
            width: 1),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            sharing ? Icons.location_on : Icons.location_off,
            color: sharing ? migoTeal : Colors.white38,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sharing ? 'Sharing location' : 'Location hidden',
                  style: TextStyle(
                      color: sharing ? Colors.white : Colors.white54,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                Text(
                  sharing
                      ? 'Your family can see you on the map.'
                      : 'You are invisible to your family.',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: sharing,
            onChanged: (_) =>
                ref.read(locationSharingEnabledProvider.notifier).toggle(),
            activeColor: migoTeal,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}

class _InviteCodeCard extends StatefulWidget {
  const _InviteCodeCard({required this.group, required this.state});
  final FamilyGroup group;
  final _FamilyScreenState state;

  @override
  State<_InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<_InviteCodeCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Invite code',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              // Large code display
              Text(
                widget.group.inviteCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const Spacer(),
              // Copy button
              IconButton(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: widget.group.inviteCode));
                  setState(() => _copied = true);
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (mounted) setState(() => _copied = false);
                },
                icon: Icon(
                  _copied ? Icons.check : Icons.copy,
                  color: _copied ? migoTeal : Colors.white54,
                ),
              ),
              // Regenerate button
              IconButton(
                onPressed: widget.state._isLoading
                    ? null
                    : () async {
                        await widget.state.ref
                            .read(familyGroupProvider.notifier)
                            .regenerateCode();
                      },
                icon: const Icon(Icons.refresh, color: Colors.white38),
                tooltip: 'New code',
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Share this code with family members to invite them.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});
  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final DrivingArchetype archetype = _parseArchetype(member.archetype);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          AvatarWidget(archetype: archetype, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(member.displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(
                  archetype.name,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // Sharing indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: member.isSharingLocation
                  ? migoTeal
                  : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  DrivingArchetype _parseArchetype(String? name) {
    if (name == null) return DrivingArchetype.zenMaster;
    try {
      return DrivingArchetype.values.byName(name);
    } catch (_) {
      return DrivingArchetype.zenMaster;
    }
  }
}

// ---------------------------------------------------------------------------
// Reusable small widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8),
      );
}

class _DarkTextField extends StatelessWidget {
  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.allCaps = false,
  });

  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final bool allCaps;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLength: maxLength,
        textCapitalization:
            allCaps ? TextCapitalization.characters : TextCapitalization.words,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          counterStyle: const TextStyle(color: Colors.white24),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: migoTeal, width: 1.5),
          ),
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.color = migoTeal,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withAlpha(80),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: migoDanger, size: 48),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
                onPressed: onRetry,
                child: const Text('Retry',
                    style: TextStyle(color: migoTeal))),
          ],
        ),
      );
}
