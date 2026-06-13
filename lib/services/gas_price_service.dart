// gas_price_service.dart — Gas price data fetching and community reporting.
// Phase 6 work; scaffolded now so the service layer is complete.

import 'package:latlong2/latlong.dart';

// --- SERVICE ---

/// Fetches and reports gas prices at stations near the user.
class GasPriceService {
  /// Fetches known prices for stations near [center].
  Future<Map<String, double>> fetchNearbyPrices(LatLng center) async {
    // TODO: [research free sources: OSM fuel POI data via Overpass, community
    // reports in our gas_prices table; evaluate any GasBuddy open endpoints]
    // [deferred to Phase 6 per the phase plan]
    throw UnimplementedError('Gas prices are Phase 6 work.');
  }

  /// Records a user-reported price at [stationId].
  Future<void> reportPrice(String stationId, double pricePerGallon) async {
    // TODO: [insert into gas_prices table] [deferred to Phase 6]
    throw UnimplementedError('Gas prices are Phase 6 work.');
  }
}
