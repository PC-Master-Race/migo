// hazard_service.dart — Hazard reporting, voting, expiry, and proximity
// alerts. Phase 3 work; scaffolded now so the architecture is complete.

import '../models/hazard_model.dart';
import 'package:latlong2/latlong.dart';

// --- SERVICE ---

/// Fetches, reports, and votes on community hazards.
class HazardService {
  /// Fetches community-confirmed hazards near [center] for map display.
  Future<List<Hazard>> fetchNearbyHazards(LatLng center) async {
    // TODO: [Supabase query filtered by bounding box + is_community_confirmed]
    // [deferred to Phase 3 per the phase plan]
    throw UnimplementedError('Hazard system is Phase 3 work.');
  }

  /// Reports a new hazard of [type] at [position] from the current user.
  Future<void> reportHazard(HazardType type, LatLng position) async {
    // TODO: [insert into hazards table; new reports start unconfirmed]
    // [deferred to Phase 3]
    throw UnimplementedError('Hazard system is Phase 3 work.');
  }

  /// Records a confirm/dismiss vote on [hazardId].
  Future<void> voteOnHazard(String hazardId, {required bool stillThere}) async {
    // TODO: [insert into hazard_votes; trigger recomputes confirmation]
    // [deferred to Phase 3]
    throw UnimplementedError('Hazard system is Phase 3 work.');
  }
}
