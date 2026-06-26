// family_provider.dart — Riverpod state for family groups and live locations.
//
// PRIVACY: locationPublisherProvider only fires when the user's own
// location_sharing_enabled setting is true. If it's false, nothing is
// ever sent — not even a "I'm offline" ping.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/family_model.dart';
import '../services/family_service.dart';
// currentUserIdProvider
import 'location_provider.dart';  // positionStreamProvider
import 'settings_provider.dart';  // locationSharingEnabledProvider

// ---------------------------------------------------------------------------
// Current family group
// ---------------------------------------------------------------------------

final StateNotifierProvider<FamilyGroupNotifier, AsyncValue<FamilyGroup?>>
    familyGroupProvider =
    StateNotifierProvider<FamilyGroupNotifier, AsyncValue<FamilyGroup?>>(
  (Ref ref) => FamilyGroupNotifier(ref),
);

class FamilyGroupNotifier
    extends StateNotifier<AsyncValue<FamilyGroup?>> {
  FamilyGroupNotifier(this._ref)
      : super(const AsyncValue<FamilyGroup?>.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = const AsyncValue<FamilyGroup?>.loading();
    state = await AsyncValue.guard<FamilyGroup?>(
      FamilyService.instance.loadMyGroup,
    );
  }

  Future<void> createGroup(String name) async {
    state = const AsyncValue<FamilyGroup?>.loading();
    state = await AsyncValue.guard<FamilyGroup?>(
      () => FamilyService.instance.createGroup(name),
    );
  }

  Future<void> joinByCode(String code) async {
    state = const AsyncValue<FamilyGroup?>.loading();
    state = await AsyncValue.guard<FamilyGroup?>(
      () => FamilyService.instance.joinByCode(code),
    );
  }

  Future<void> leaveGroup() async {
    final FamilyGroup? current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncValue<FamilyGroup?>.loading();
    await FamilyService.instance.leaveGroup(current.id);
    state = const AsyncValue<FamilyGroup?>.data(null);
  }

  Future<String> regenerateCode() async {
    final FamilyGroup? current = state.valueOrNull;
    if (current == null) throw const FamilyServiceException('No active group.');
    final String newCode =
        await FamilyService.instance.regenerateInviteCode(current.id);
    // Update local state with new code.
    state = AsyncValue<FamilyGroup?>.data(
      FamilyGroup(
        id: current.id,
        name: current.name,
        inviteCode: newCode,
        createdBy: current.createdBy,
        createdAt: current.createdAt,
      ),
    );
    return newCode;
  }

  void refresh() => _load();
}

// ---------------------------------------------------------------------------
// Family members list
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<List<FamilyMember>> familyMembersProvider =
    AutoDisposeFutureProvider<List<FamilyMember>>(
        (Ref ref) async {
  final FamilyGroup? group = ref.watch(familyGroupProvider).valueOrNull;
  if (group == null) return <FamilyMember>[];
  return FamilyService.instance.loadMembers(group.id);
});

// ---------------------------------------------------------------------------
// Live family locations — Supabase Realtime stream
// ---------------------------------------------------------------------------

final StreamProvider<List<FamilyLocation>> familyLocationsProvider =
    StreamProvider<List<FamilyLocation>>((Ref ref) {
  final FamilyGroup? group = ref.watch(familyGroupProvider).valueOrNull;
  if (group == null) {
    return const Stream<List<FamilyLocation>>.empty();
  }
  return FamilyService.instance.streamFamilyLocations(group.id);
});

// ---------------------------------------------------------------------------
// Location publisher — side-effect provider.
// Pushes GPS position to Supabase every 10 seconds ONLY when:
//   1. User has location_sharing_enabled = true
//   2. User is in a family group
//   3. A valid GPS fix is available
// ---------------------------------------------------------------------------

final Provider<void> locationPublisherProvider = Provider<void>((Ref ref) {
  final bool sharingEnabled = ref.watch(locationSharingEnabledProvider);
  final FamilyGroup? group = ref.watch(familyGroupProvider).valueOrNull;
  final AsyncValue<Object?> locationAsync = ref.watch(positionStreamProvider);

  if (!sharingEnabled || group == null) return;

  locationAsync.whenData((Object? pos) async {
    if (pos == null) return;
    // pos is a Position from geolocator
    // We cast carefully to avoid hard dependency on geolocator type here.
    try {
      final dynamic position = pos;
      final double lat = position.latitude as double;
      final double lon = position.longitude as double;
      final double speed = (position.speed as double?) ?? 0.0;

      await FamilyService.instance.publishLocation(
        groupId: group.id,
        position: LatLng(lat, lon),
        speedMps: speed,
      );
    } catch (_) {
      // Never crash the UI over a location publish failure.
    }
  });
});

// ---------------------------------------------------------------------------
// Member lookup by userId (for avatar rendering on map)
// ---------------------------------------------------------------------------

final AutoDisposeProvider<Map<String, FamilyMember>> familyMemberMapProvider =
    AutoDisposeProvider<Map<String, FamilyMember>>((Ref ref) {
  final List<FamilyMember> members =
      ref.watch(familyMembersProvider).valueOrNull ?? <FamilyMember>[];
  return <String, FamilyMember>{
    for (final FamilyMember m in members) m.userId: m,
  };
});
