// alpr_service.dart — ALPR (automated license plate reader) location data
// and avoidance logic. Not being surveilled is treated as a human right in
// this codebase; this service is core to that value, not an add-on.
// Phase 3 work; scaffolded now.

import 'package:latlong2/latlong.dart';

// --- PRIVACY GUARANTEE ---
// ALPR avoidance data is NEVER sent to any third party. All reads come from
// our own Supabase tables (community reports) plus open datasets imported
// server-side. No external API receives the user's location for this feature.

// --- SERVICE ---

/// Provides known ALPR camera locations and avoidance geometry.
class AlprService {
  /// Fetches known ALPR locations within the map's visible region.
  Future<List<LatLng>> fetchAlprLocations(LatLng center) async {
    // TODO: [query alpr_locations table; layer community votes on top of
    // imported open datasets — research DDoSecrets/EFF Atlas of Surveillance
    // and OpenALPR-map style community datasets as import sources]
    // [deferred to Phase 3 per the phase plan]
    throw UnimplementedError('ALPR system is Phase 3 work.');
  }

  /// Reports a newly spotted ALPR camera. Frequent reporters earn progress
  /// toward the Secret Agent archetype (Phase 4 ties this in).
  Future<void> reportAlprLocation(LatLng position) async {
    // TODO: [insert into alpr_locations + count toward archetype scoring]
    // [deferred to Phase 3]
    throw UnimplementedError('ALPR system is Phase 3 work.');
  }
}
