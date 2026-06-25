// hazard_service.dart — Hazard reporting, fetching, voting, and expiry.
// All reads and writes go through SupabaseService so privacy is auditable.
// Gracefully degrades to an empty list when Supabase is not connected
// (offline mode / placeholder credentials) — map still works fine.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/hazard_model.dart';
import 'supabase_service.dart';

// --- SERVICE ---

/// Handles all hazard data: fetching nearby pins, reporting new ones,
/// voting on existing ones, and querying expiry candidates.
class HazardService {
  // --- FETCH ---

  /// Fetches community-confirmed hazards within [radiusMiles] of [center].
  ///
  /// Uses a lat/lon bounding box query (no PostGIS required). Slightly over-
  /// fetches at the corners; proximity filtering is done client-side in the
  /// provider layer.
  ///
  /// Returns an empty list when offline or on any network error.
  Future<List<Hazard>> fetchNearbyHazards(
    LatLng center, {
    double radiusMiles = hazardFetchRadiusMiles,
  }) async {
    if (!SupabaseService.isConnected) return <Hazard>[];

    final (double minLat, double maxLat, double minLon, double maxLon) =
        _boundingBox(center, radiusMiles);

    try {
      final List<dynamic> rows = await SupabaseService.client
          .from(tableHazards)
          .select()
          .eq('is_community_confirmed', true)
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLon)
          .lte('longitude', maxLon)
          .order('reported_at', ascending: false)
          .limit(200);

      return rows
          .map((dynamic r) => Hazard.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Hazard>[];
    }
  }

  /// Fetches the current user's own unconfirmed reports so they can see
  /// pins they submitted that haven't yet been community-confirmed.
  Future<List<Hazard>> fetchOwnPendingHazards() async {
    if (!SupabaseService.isConnected) return <Hazard>[];
    final String? uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) return <Hazard>[];

    try {
      final List<dynamic> rows = await SupabaseService.client
          .from(tableHazards)
          .select()
          .eq('reporter_id', uid)
          .eq('is_community_confirmed', false)
          .order('reported_at', ascending: false)
          .limit(50);

      return rows
          .map((dynamic r) => Hazard.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Hazard>[];
    }
  }

  // --- REPORT ---

  /// Reports a new hazard of [type] at [position].
  ///
  /// New reports start unconfirmed (isCommunityConfirmed = false) and become
  /// visible to all users only after [hazardConfirmationVoteThreshold] votes.
  ///
  /// Throws [HazardServiceException] if the insert fails.
  Future<void> reportHazard(HazardType type, LatLng position) async {
    if (!SupabaseService.isConnected) {
      throw const HazardServiceException('Cannot report: not connected.');
    }
    final String? uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) {
      throw const HazardServiceException('Cannot report: not signed in.');
    }

    await SupabaseService.client.from(tableHazards).insert(<String, dynamic>{
      'reporter_id': uid,
      'hazard_type': type.name,
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  }

  // --- VOTE ---

  /// Votes "still there" ([stillThere] = true) or "gone now" (false) on
  /// [hazardId]. One vote per user per hazard enforced by the DB unique index.
  ///
  /// Also increments the corresponding vote counter column on the hazard row
  /// so the confirmation threshold check is fast (no aggregate query needed).
  Future<void> voteOnHazard(
    String hazardId, {
    required bool stillThere,
  }) async {
    if (!SupabaseService.isConnected) return;
    final String? uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      // Insert the vote (DB unique index prevents double-voting).
      await SupabaseService.client
          .from(tableHazardVotes)
          .insert(<String, dynamic>{
        'hazard_id': hazardId,
        'voter_id': uid,
        'still_there': stillThere,
      });

      // Increment the appropriate counter and check if threshold is met.
      if (stillThere) {
        await SupabaseService.client.rpc('increment_hazard_confirmed', params: <String, dynamic>{
          'hazard_id': hazardId,
          'threshold': hazardConfirmationVoteThreshold,
        });
      } else {
        await SupabaseService.client.rpc('increment_hazard_dismissed', params: <String, dynamic>{
          'hazard_id': hazardId,
        });
      }
    } catch (_) {
      // Swallow duplicate-vote errors gracefully.
    }
  }

  // --- EXPIRY ---

  /// Fetches confirmed hazards older than [hazardExpiryPromptMinutes] that
  /// are near [center]. These are shown in the "Is this still there?" prompt.
  Future<List<Hazard>> fetchExpiryPromptCandidates(
    LatLng center, {
    double radiusMiles = 2.0,
  }) async {
    if (!SupabaseService.isConnected) return <Hazard>[];

    final (double minLat, double maxLat, double minLon, double maxLon) =
        _boundingBox(center, radiusMiles);

    final DateTime cutoff = DateTime.now().subtract(
      Duration(minutes: hazardExpiryPromptMinutes),
    );

    try {
      final List<dynamic> rows = await SupabaseService.client
          .from(tableHazards)
          .select()
          .eq('is_community_confirmed', true)
          .lt('reported_at', cutoff.toIso8601String())
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLon)
          .lte('longitude', maxLon)
          .limit(10);

      return rows
          .map((dynamic r) => Hazard.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Hazard>[];
    }
  }

  // --- GEO HELPERS ---

  /// Returns a (minLat, maxLat, minLon, maxLon) bounding box for a circle
  /// around [center] with the given [radiusMiles].
  (double, double, double, double) _boundingBox(
      LatLng center, double radiusMiles) {
    final double latDelta = radiusMiles / 69.0;
    final double lonDelta =
        radiusMiles / (69.0 * math.cos(center.latitude * math.pi / 180.0));
    return (
      center.latitude - latDelta,
      center.latitude + latDelta,
      center.longitude - lonDelta,
      center.longitude + lonDelta,
    );
  }
}

// --- EXCEPTION ---

/// Thrown by [HazardService] on recoverable errors (offline, not signed in).
class HazardServiceException implements Exception {
  const HazardServiceException(this.message);
  final String message;
  @override
  String toString() => 'HazardServiceException: $message';
}
