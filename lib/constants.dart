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

/// User-Agent sent with every tile/Overpass/Nominatim request. OSM's usage
/// policy requires apps to identify themselves; generic agents get blocked.
const String osmUserAgent = 'bravo-maps-app (privacy-first OSS project)';

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

/// Zoom snapped to on the first GPS fix. 17 ≈ individual buildings visible —
/// matches the close street-level view Waze opens to when location is acquired.
const double mapFirstFixZoom = 17.0;

/// Perspective divisor for the navigation-mode map tilt Transform.
/// Higher value = more subtle perspective shrink toward the horizon.
const double mapTiltPerspective = 0.0012;

/// Tilt angle (radians) applied to the map in active navigation mode.
/// 0.8 rad ≈ 46° — enough to give a Waze-style driving perspective without
/// the top of the map becoming unreadably small.
const double mapTiltRadians = 0.8;

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

/// Hive key for the JSON-encoded list of saved locations (home, work, favs).
const String hiveKeySavedLocations = 'saved_locations';

// --- USER MARKER ---

/// Diameter (logical pixels) of the user's position dot on the map.
const double userMarkerSize = 26.0;

// --- ROUTING ---
// Phase 2: Valhalla-based routing via the public OSM-hosted instance.
//
// Engine choice: Valhalla over OSRM because:
//   • use_tolls / use_highways are native costing options — no custom OSM
//     profiles needed on a self-hosted server (OSRM's public API lacks these).
//   • exclude_polygons supports ALPR-avoidance penalty zones natively.
//   • verbal_pre_transition_instruction strings feed directly into TTS.
//   • The OSM community hosts a public Valhalla endpoint with no API key.
//
// TODO: [self-host Valhalla for production to eliminate third-party network
// dependency] [deferred: needs server budget decision]

/// Public Valhalla routing endpoint (OSM-hosted, no API key required).
const String valhallaApiUrl = 'https://valhalla1.openstreetmap.de/route';

/// Nominatim geocoding endpoint (OSM-hosted, no API key, no tracking).
const String nominatimSearchUrl = 'https://nominatim.openstreetmap.org/search';

/// Max results returned by a Nominatim search.
const int nominatimMaxResults = 5;

/// Meters from the route polyline beyond which the user is considered off-route
/// and recalculation is triggered. 40 m covers GPS jitter + minor lane drift.
const double offRouteThresholdMeters = 40.0;

/// Meters before the next maneuver at which the TTS instruction fires.
/// 200 m gives ~10 s of warning at 45 mph — enough to change lanes.
const int maneuverAlertDistanceMeters = 200;

/// Meters from a maneuver point at which the app advances to the next step.
/// 25 m ≈ passing through the intersection.
const double stepAdvanceRadiusMeters = 25.0;

/// Stroke width (dp) for the route polyline drawn on the map.
const double routePolylineWidthDp = 6.0;

/// Valhalla costing model used for all car routing. 'auto' applies road-class
/// and turn penalties appropriate for a typical passenger vehicle.
const String valhallaCostingModel = 'auto';

/// Radius (meters) of the exclude polygon placed around each ALPR camera when
/// avoidAlprCameras is enabled. Small enough to target just the camera
/// approach, large enough to route a different street.
const double alprExcludeRadiusMeters = 150.0;

/// Number of polygon vertices used to approximate each ALPR exclusion circle.
/// 8 is a good balance between accuracy and Valhalla request payload size.
const int alprExcludePolygonVertices = 8;

// --- TTS ---
// ElevenLabs provides high-quality voiced navigation instructions. The app
// falls back to flutter_tts (on-device, fully offline) when no ElevenLabs
// key is configured, so the feature degrades gracefully.
// Privacy: only the instruction text string is sent to ElevenLabs — no
// location data, no user identity, no session metadata.

/// ElevenLabs text-to-speech base URL. Voice ID appended at runtime.
const String elevenLabsApiUrl = 'https://api.elevenlabs.io/v1/text-to-speech';

/// ElevenLabs output format: mp3_44100_128 gives good quality at ~60 KB/instruction.
const String elevenLabsOutputFormat = 'mp3_44100_128';

/// Hive key for the user's ElevenLabs API key (stored locally, never sent to
/// Supabase — stays on device only).
const String hiveKeyElevenLabsApiKey = 'elevenlabs_api_key';

/// Hive key for the chosen ElevenLabs voice ID.
const String hiveKeyElevenLabsVoiceId = 'elevenlabs_voice_id';

/// Hive key for the TTS-enabled boolean setting.
const String hiveKeyTtsEnabled = 'tts_enabled';

/// Default ElevenLabs voice ID — "Rachel" (warm, clear, calm). Users can
/// override this in settings once Phase 2 settings screen is built.
const String elevenLabsDefaultVoiceId = '21m00Tcm4TlvDq8ikWAM';

// --- PHASE 3: HAZARDS ---

/// Radius (miles) within which an incoming hazard triggers an alert banner
/// and sound. 2 miles per PRODUCT_BRIEF Phase 3 spec.
const double hazardFetchRadiusMiles = 10.0;

/// How long (seconds) a hazard alert banner stays visible before auto-
/// dismissing. Never requires a user tap — PRODUCT_BRIEF: no taps while driving.
const int hazardAlertAutoDismissSeconds = 8;

/// Minimum time (minutes) before the same hazard can trigger another alert.
/// Prevents the same camera/crash from spamming the banner on repeat passes.
const int hazardReAlertCooldownMinutes = 10;

/// Minimum "still there" votes before a hazard is shown to all users.
/// Kept low (3) so the community can confirm quickly while filtering noise.
const int hazardConfirmationVoteThreshold = 3;

/// How many minutes before Migo asks nearby users "Is this still there?"
const int hazardExpiryPromptMinutes = 60;

/// Fetch radius (meters) used when querying Overpass for OSM-tagged ALPR
/// cameras around the user's current position.
const int alprOverpassRadiusMeters = 16000; // ~10 miles

/// Supabase table names — centralized so a rename can't silently break queries.
const String tableHazards = 'hazards';
const String tableHazardVotes = 'hazard_votes';
const String tableAlprLocations = 'alpr_locations';
const String tableAlprVotes = 'alpr_votes';
