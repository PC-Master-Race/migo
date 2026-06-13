// constants.dart — Every app-wide constant in one place.
// PRODUCT_BRIEF rule: no magic numbers anywhere in the codebase. If a number
// or fixed string matters, it lives here (or at the top of its own file) with
// a comment explaining what it is and why it has that value.

// --- MAP TILES ---

/// Standard OpenStreetMap raster tile server. Free, no API key.
/// Usage policy requires a valid User-Agent (see [osmUserAgent]).
const String osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Esri World Imagery — free satellite tiles used for the street-level zoom
/// mode. Attribution is mandatory and rendered on the map (see map_screen).
const String satelliteTileUrlTemplate =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// User-Agent sent with every tile/Overpass request. OSM's usage policy
/// requires apps to identify themselves; generic agents get blocked.
const String osmUserAgent = 'migo-navigation-app (privacy-first OSS project)';

/// Overpass API endpoint used to query OSM data (speed limits, POIs, fuel
/// stations). The main public instance; can be swapped for a self-hosted one.
const String overpassApiUrl = 'https://overpass-api.de/api/interpreter';

// --- ZOOM MODE THRESHOLDS ---
// Three visual modes per PRODUCT_BRIEF: cartoon (zoomed out), hybrid (mid),
// street/satellite (deep zoom). Values are flutter_map zoom levels.

/// Below this zoom the map renders in full cartoon style.
/// 13 ≈ a whole town visible — names and simplified roads matter most here.
const double cartoonModeMaxZoom = 13.0;

/// Between [cartoonModeMaxZoom] and this value the map is in hybrid mode.
/// 16 ≈ individual blocks visible — road detail appears, cartoon palette stays.
const double hybridModeMaxZoom = 16.0;
// Anything above hybridModeMaxZoom is street-level mode (satellite imagery,
// avatars hidden, POI icons shown).

/// Hard zoom bounds for the map widget. 3 keeps users from zooming into empty
/// ocean-of-grey; 19 is the max OSM tile depth commonly served.
const double mapMinZoom = 3.0;
const double mapMaxZoom = 19.0;

/// Default zoom when the app opens before GPS has a fix — wide enough to be
/// useful, close enough to feel local once location arrives.
const double mapDefaultZoom = 15.0;

/// Fallback map center before the first GPS fix: geographic center of the
/// contiguous US. Replaced by the real position the moment GPS reports in.
const double fallbackCenterLatitude = 39.8283;
const double fallbackCenterLongitude = -98.5795;

// --- OFFLINE TILE CACHE ---

/// Radius (miles) auto-cached around the user's frequent locations on WiFi.
/// 100 mi per PRODUCT_BRIEF: covers a typical metro region + day trips.
const double offlineCacheRadiusMiles = 100.0;

/// Zoom levels prefetched for offline use. z8–z13 keeps a 100-mile radius in
/// the low-thousands of tiles (~100–200 MB). Deeper zooms are fetched
/// dynamically and cached opportunistically as the user browses.
/// TODO: [tune after real-device storage profiling] [deferred: needs hardware]
const int offlineCacheMinZoom = 8;
const int offlineCacheMaxZoom = 13;

/// Tiles older than this many days are re-fetched during the weekly WiFi sync.
/// 7 days per PRODUCT_BRIEF's "weekly base sync" requirement.
const int tileStaleAfterDays = 7;

// --- GEO MATH ---

/// Meters in one statute mile. Used for radius and distance conversions.
const double metersPerMile = 1609.344;

/// Conversion factor from meters/second (GPS native) to miles/hour (HUD).
const double metersPerSecondToMph = 2.23694;

// --- LOCATION TRACKING ---

/// Minimum movement (meters) before a new GPS position event fires.
/// 5 m balances battery use against smooth avatar movement on the map.
const int locationDistanceFilterMeters = 5;

/// Speeds below this (mph) display as 0 on the HUD — raw GPS jitter while
/// standing still otherwise shows phantom 1–2 mph readings.
const double speedJitterFloorMph = 2.0;

// --- SPEED LIMIT LOOKUP ---

/// Radius (meters) around the user searched for an OSM way with a maxspeed
/// tag. 30 m ≈ the road the user is actually on, without grabbing parallels.
const int speedLimitSearchRadiusMeters = 30;

/// Shown when OSM has no speed limit data for the current road.
/// PRODUCT_BRIEF: missing data must degrade gracefully, never crash or guess.
const String speedLimitUnknownLabel = 'Unknown';

// --- HAZARDS (Phase 3 — constants reserved here so callers never inline) ---

/// Distance (miles) at which an approaching-hazard alert fires.
const double hazardAlertRadiusMiles = 2.0;

// --- ARCHETYPES (Phase 4) ---

/// Community votes required before the Chili Pepper badge appears.
const int chiliPepperVoteThreshold = 100;

/// Bad-driver reports required before the Menace badge appears.
const int menaceBadgeReportThreshold = 100;

// --- HIVE BOX NAMES ---
// Box names are centralized so a typo can't silently create a second box.

/// Stores tile-cache metadata (fetch timestamps for staleness checks).
const String hiveBoxTileMetadata = 'tile_metadata';

/// Stores user settings (cache radius, WiFi-only flags, toggles).
const String hiveBoxSettings = 'settings';
