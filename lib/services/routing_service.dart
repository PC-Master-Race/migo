// routing_service.dart — Route calculation against OSRM or Valhalla.
// Phase 2 work. Scaffolded now so the architecture is visible from day one.

// --- ROUTING ENGINE DECISION ---
// PRODUCT_BRIEF requires evaluating OSRM vs Valhalla and documenting the
// choice here. That evaluation is Phase 2 work and has NOT happened yet.
// Criteria to weigh when it does:
//   • Flutter integration quality (HTTP API shape, community packages)
//   • Offline capability (Valhalla compiles to mobile; OSRM is server-bound)
//   • Custom costing flexibility (needed for "avoid popular routes" and
//     ALPR-avoidance penalty zones — Valhalla's dynamic costing is promising)
// TODO: [evaluate OSRM vs Valhalla and replace this stub] [deferred to
// Phase 2 per the phase plan — no routing work in Session 1]

import '../models/route_model.dart';
import 'package:latlong2/latlong.dart';

// --- SERVICE ---

/// Calculates routes between points honoring the user's RoutePreferences.
class RoutingService {
  /// Calculates a route from [origin] to [destination] using [preferences].
  /// Returns the computed route, or throws if the engine is unreachable.
  Future<MigoRoute> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutePreferences preferences,
  }) async {
    // TODO: [implement against the chosen engine] [deferred to Phase 2]
    throw UnimplementedError('Routing engine integration is Phase 2 work.');
  }
}
