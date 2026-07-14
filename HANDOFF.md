# Migo — Project Handoff

> Purpose of this doc: get a new AI session productive on the **Migo** app fast.
> **START HERE:** read the "CURRENT STATE / WHAT TO DO NEXT" block inside
> SESSION UPDATE 5 (in section 6) first — it's the fastest path to productive.
> Then skim sections 1-5 for architecture, and the session updates for history.
> This doc is model-agnostic (the project has spanned multiple Claude models).

---

## 1. What Migo is

Migo is a **privacy-first navigation app** (Flutter/Android, iOS-capable). Think
Waze/Google Maps, but it does not monetize location data, and it has a couple of
distinctive features:

- **ALPR camera avoidance** — it knows where automated license-plate-reader
  cameras are (crowdsourced from DeFlock/OpenStreetMap) and can route *around*
  them. Not being passively surveilled is treated as the core value prop.
- **Cartoon driving-archetype avatars** — a code-drawn chibi avatar that reflects
  a "driving archetype" earned from how you actually drive.
- **Hazard reporting, family location sharing, gas prices**, and a reward
  currency called **"Bravos."**

The owner (Ruben) is the product lead and tester. He's a returning developer
(was away from code ~18 years), drives the AI as architect/pair. **Be hands-on,
concrete, and honest.** He runs the builds and reports back with screenshots and
error text; you can't see his device.

### Naming note (important)
The app was renamed from "Bravo Maps" → **"Migo"** for everything **user-facing**
(splash, titles, labels). But:
- The **reward currency is still called "Bravos"** (intentional — keep it).
- **Internal names were deliberately left as-is** — the package is still
  `bravo_maps`, the root widget is `BravoMapsApp`, the theme file is
  `bravo_theme.dart`, colors are `migo*`/`bravo*` mixed, etc. Do **not** mass-
  rename internals; it's not worth the churn and risk.

---

## 2. Tech stack

- **Flutter + Dart** (SDK `>=3.4.0 <4.0.0`), **Riverpod** for state.
- **flutter_map 7.0.2** (OpenStreetMap raster tiles via `TileLayer`), `latlong2`.
- **geolocator 13.0.2** for GPS (fused provider on Android).
- **Supabase** (`supabase_flutter 2.8.0`) — Postgres + RLS + anonymous auth.
- **Valhalla** routing (public/hosted instance) via HTTP in `routing_service.dart`.
- **Hive CE** for local settings + offline tile metadata.
- **flutter_tts** + **audioplayers** (+ optional ElevenLabs) for voice guidance.
- Avatars are **code-drawn** (CustomPainter), not image assets.

---

## 3. How to run it (READ THIS — easy to get wrong)

**You MUST pass the Supabase credentials at run time or the app silently runs in
offline mode** (no backend, no ALPR DB, no auth):

```
flutter run --dart-define-from-file=env.json
```

- `env.json` lives in the repo root (git-ignored). It contains
  `SUPABASE_URL` and `SUPABASE_KEY`. If it's missing, ask Ruben for it.
- There's a VS Code launch config: **Run panel → "Migo (debug)"** (or F5) which
  passes the flag automatically. `.vscode/launch.json` has debug/profile/release.
- **Symptom of forgetting the flag:** anything backend fails and the ALPR sync
  says "Offline — no Supabase connection." First thing to check on any "offline"
  complaint.

### Hot reload vs restart vs rebuild (we got burned by this)
- **`r` (hot reload):** UI/code tweaks. Does **not** re-run cached Riverpod
  `FutureProvider`s and does **not** re-bundle assets.
- **`R` (hot restart):** re-runs providers + resets app state. Use when a
  provider result is cached (e.g., tile/theme providers).
- **Asset content changes** (files under `assets/`) may need a full stop + `flutter run`
  (sometimes `flutter clean` first) to re-bundle. Asset staleness cost us hours —
  when in doubt, do a clean rebuild.

---

## 4. Backend / Supabase

- Anonymous auth signs in at startup (`SupabaseService.signInAnonymously()` in
  `main.dart`). A DB trigger `handle_new_user()` auto-creates the `public.users`
  row so foreign keys resolve.
- **Schema lives in `supabase/schema.sql`** (canonical, idempotent-ish). Seed in
  `supabase/seed.sql`.
- **Free-tier pause:** the Supabase project pauses after ~7 days idle. A GitHub
  Action (`.github/workflows/supabase-keepalive.yml`) pings it daily to keep it
  awake. Data is preserved across pause; just annoying.
- Credentials come from `--dart-define`, funneled through `supabase_service.dart`.
  `SupabaseService.isConnected` gates all backend calls.

### ALPR "owned-DB" model (this is DONE and working for storage)
We moved ALPR cameras out of live-Overpass and into our own Supabase table so
routing/map read from one fast source.

- Migration: **`supabase/migration_alpr_import.sql`** (already run by Ruben).
  It makes `alpr_locations.reporter_id` nullable, adds `source` (`'osm'` /
  `'community'`) + `osm_node_id` columns + a unique index, and adds a
  `SECURITY DEFINER` RPC **`upsert_osm_alpr(jsonb)`** for bulk import.
- In-app one-time import: **Settings → Privacy → "Sync cameras for my area"**
  calls `AlprService.importOsmAlprForRegion()`, which pulls OSM ALPR nodes near
  the user (~70 mi radius) via Overpass and bulk-upserts them through the RPC.
- **STATUS: Ruben ran the sync and it imported 6,664 cameras** for the San
  Bernardino + Los Angeles + Orange County area. Cameras **populate the map
  correctly** (toggle the camera layer). So storage + display work.

---

## 5. Repo / key files map

```
lib/
  main.dart                         app bootstrap, theme, routes, anon sign-in
  constants.dart                    ALL tunables (speeds, zooms, URLs, table names)
  theme/bravo_theme.dart            light + dark ThemeData (buildBravoTheme / buildBravoDarkTheme)
  services/
    supabase_service.dart           backend choke point; isConnected; credentials
    alpr_service.dart               ALPR DB reads + OSM import + community report
    routing_service.dart            Valhalla calls; exclude_polygons for avoidance; nearestSegmentIndex
    location_service.dart           GPS stream + Kalman piping + nav location settings
    location_filter.dart            LocationKalmanFilter (GPS smoothing)
    tts_service.dart                voice guidance (ElevenLabs + flutter_tts)
  providers/
    location_provider.dart          positionStreamProvider, displaySpeedMphProvider
    routing_provider.dart           RouteNotifier.calculate/recalculate, navigationStateProvider,
                                    offRouteProvider, _NavAnnouncer, ttsAnnouncerProvider
    alpr_provider.dart              alprServiceProvider, alprLayerEnabledProvider, nearbyAlprProvider
    settings_provider.dart          all toggles + themeModeProvider
    vector_tiles_provider.dart      (PAUSED) vector-tile pipeline
  widgets/
    hud/speed_hud.dart              speedometer (theme-aware)
    cartoon_avatar/smooth_user_marker_layer.dart   animated avatar (dead-reckoning smoothing)
    avatar/avatar_painter.dart      chibi avatar CustomPainter
  screens/
    map_screen.dart                 THE main screen (map, overlays, layers, HUD)
    settings_screen.dart            settings UI (theme-aware) + Sync cameras button
supabase/
  schema.sql, seed.sql, migration_alpr_import.sql
env.json                            (git-ignored) SUPABASE_URL + SUPABASE_KEY
.vscode/launch.json                 run configs with the --dart-define flag
```

Almost every magic number lives in **`lib/constants.dart`** — check there before
hardcoding anything.

---

## 6. OPEN PROBLEMS (the work queue)

> **SESSION UPDATE (2026-07-01):** all three problems have fixes implemented,
> pending Ruben's device/drive testing:
> 1. **ALPR avoidance** — root cause was Valhalla's 10,000 m total
>    exclude-polygon perimeter limit (~10 polygons max; we sent up to 2000).
>    Now: baseline route → exclude only budget-capped cameras near it → refine
>    once. Errors surface as SnackBars; `[routing]` console logging added.
> 2. **GPS surging/rubber-banding** — displayed avatar is now eased (never
>    teleports back), snap-to-route map matching added (accuracy-adaptive),
>    camera follows the eased point per-frame, Kalman got an outlier-streak
>    reset (the "can't lock on in weak areas" bug), off-route detection is
>    accuracy-aware (was causing wrong directions from noise fixes).
>    `[gps]` / `[geocode]` logging added. NOTE: geocoded pins on the wrong
>    side of the street (Sunright Tea Studio case) are a geocoder-data issue,
>    diagnosable via the new `[geocode]` logs.
> 3. **Vector dark map** — switched from Protomaps PMTiles to the
>    renderer-verified combo: MapTiler hosted styles (Dark Matter /
>    OSM Bright) via StyleReader, with Dart-side label boosting (bigger, bold,
>    white-on-dark-halo street names). Needs `MAPTILER_API_KEY` in env.json
>    (free at cloud.maptiler.com, 100k req/mo); without it the app stays on
>    raster. (Stadia was rejected: free tier now only a 14-day trial + ~28k.)

> **SESSION UPDATE 2 (2026-07-02):** shakedown fixes + avatar system.
> - **Release builds work now**: AndroidManifest was missing INTERNET
>   permission (debug injects it silently; release = blank map). Fixed.
> - **Routing outage**: FOSSGIS Valhalla was 502-ing from Ruben's region on
>   every network/method (even browser) while healthy elsewhere. Added: retry
>   w/ backoff, GET-request fallback, proper identifying User-Agent
>   ('Migo/0.1 (+repo; email)'). Self-hosting Valhalla is the real fix.
> - **Search**: tiered near(15mi)→region(50mi)→US-wide (wide gated on query
>   specificity), nearby results always ranked first, distance labels on each
>   suggestion, results panel capped at 40% screen height.
> - **Favorites**: long-press chip → rename/delete (provider rename() added).
> - **Settings**: the ALPR-avoidance toggle and Default-route-preference were
>   DEAD (routing never read them) — now they seed routePreferencesProvider
>   as defaults; route-options sheet overrides per trip. Licenses tile wired,
>   stale bravomaps.com URL removed. Onboarding page-dots no longer overlap
>   the Continue button.
> - **AVATAR SYSTEM (big)**: new users show a rocking mystery EGG (racing
>   stripes, peeking eyes) until archetypeRevealSessionCount (3) sessions,
>   then a hatch-celebration dialog reveals the earned archetype (Zen is no
>   longer the freebie default). Earned archetypes accumulate in
>   ArchetypeProfile.unlockedArchetypes (NEEDS MIGRATION:
>   supabase/migration_avatar_pool.sql — run before next build!). Tap your
>   map avatar → picker sheet (Automatic or any earned archetype; locked =
>   silhouettes). Painter now supports per-archetype VEHICLES — all nine
>   implemented: Zen=cloud, Rocket=rocket ship, Phantom=UFO (abduction beam,
>   no plates to read), Ghost=spectral float, Grandpa=vintage sedan w/
>   eternal blinker, NightOwl=crescent moon, Chaos=shopping cart w/ wobbling
>   caster, StreetRat=longboard, Scout=open jeep. Rare archetypes still ride
>   the classic car (design ideas: Creature=monster truck, Guardian=winged
>   car, SilkHands=hovering car).
> - **Heading-up camera**: map rotates road-ahead-up during navigation
>   (smoothed shortest-arc), resets north-up after; all markers pinned
>   upright. True TILTED view needs the MapLibre GL migration (maplibre_gl
>   consumes the same MapTiler style URL) — planned, not started.
> - **STILL PENDING**: real drive test of GPS smoothing + snap-to-route +
>   rotation; Valhalla recovery check; MapTiler dark map field test.

> **SESSION UPDATE 3 (2026-07-02, evening): MAPLIBRE IS IN AND WORKING.**
>
> **MapLibre GL migration (Phases 0-3 DONE, verified on the Pixel 8 Pro —
> Ruben's words: "working awesome"):**
> - `maplibre_gl: ^0.26.1` behind `USE_MAPLIBRE` in env.json (currently the
>   flag Ruben tests with; flutter_map path still fully working when false).
> - `lib/widgets/map/migo_maplibre_view.dart` — self-contained GL view:
>   MapTiler styles fetched as JSON, run through the SAME Google-night
>   recolor + park injection + label boost, passed as styleString. Camera:
>   heading-up bearing + 55° TILT during nav (constants: navCameraTiltDegrees),
>   native 900ms animateCamera per fix, DEADBAND (5m/3°) — without it GPS
>   jitter kept labels re-placing (blinking bug, fixed). Neon route = 3 GL
>   line layers. Compass button enabled (two-finger rotate exists now).
>   Placeholder neon-dot puck.
> - map_screen: all flutter_map controller calls guarded with `useMapLibre`
>   (it THROWS if touched with no FlutterMap built — was crashing first fix).
> - **PHASE 4 TODO:** avatar/Tux as symbol images (render CustomPainter →
>   PNG → addImage+symbol), destination flag, hazard/ALPR/gas/POI markers,
>   marker taps. **PHASE 5 TODO:** proper follow-pause/recenter parity
>   (currently: any touch pauses follow 8s), zoom-mode sync, then flip
>   default + retire flutter_map path.
> - Heading-up on MapLibre needs a REAL DRIVE to verify (stationary bearing
>   is always 0 by design).
>
> **Search overhaul v2 (geocoding_service):**
> - Photon FIRST always (autocomplete engine; Nominatim can't do partials —
>   it was leading for address-like queries and starving nearby results).
> - Photon: zoom=14 + location_bias_scale=0.5 + limit 12 (deep pool, we pick).
> - RELEVANCE GATE: every typed word token must prefix-match result words;
>   number-only queries require the number. Kills Photon fuzzy junk
>   ("1515 ver" → San Fernando garbage: gone).
> - Street-only rescue: number+partial queries retry without the number so
>   matching STREETS show while typing.
> - TWO-STAGE RESOLVE (Ruben's idea): when number typed but unresolved,
>   compose "number + candidate street displayName" → Nominatim in 5mi box →
>   exact address inserted on top. Works from "1515 vernes" (was full-address
>   only). True Google-grade prefix ("1515 ver") needs a self-hosted geocoder
>   with autocomplete index — roadmap.
> - Search anchor falls back to displayedPosition; US-wide tier hard-gated on
>   query specificity ALWAYS; per-tier client-side distance enforcement;
>   final nearest-first sort + house-number matches ranked on top.
>
> **Nav/UX (drive-test feedback round):** search bar HIDES during nav, banner
> at very top (Google-style); banner "Then in <dist> → <street>"; bottom bar
> true black w/ 26pt ETA + "End" (was "Exit"); look-ahead camera on
> flutter_map path (22% scrn ahead); voice ON by default (BOTH
> settings_provider AND tts_service defaults — they must match), reminder at
> 25% of leg remaining (navTurnReminderFraction) + chained "then..." for
> back-to-back turns (navChainManeuverMeters 300m).
>
> **ALPR avoidance is now LOCAL-FIRST:** one request w/ alternates:2 →
> score all candidates against on-device camera DB (countCamerasNearRoute)
> → cleanest wins; zero cameras = done with NO exclude_polygons. Only if all
> candidates cross cameras → exclusions for that route's cameras w/ adaptive
> HALVING retry (never dies, degrades). Notices tell the user which mode won.
> Ruben's earlier drive: total avoidance failure notice → the halving+
> alternates flow shipped AFTER that; needs retest. If it still fails,
> capture `adb logcat | findstr routing` — Valhalla's rejection body.
>
> **Misc fixes:** layer toggles (gas/hazard/ALPR camera) now Hive-persisted
> via ref.listenSelf w/ `Object?` params (typed params don't compile);
> settings' dead ALPR-avoidance + route-preference toggles now SEED
> routePreferencesProvider (settings=default, route sheet=per-trip);
> routing costing audit: eco/fewestStops were no-ops, now top_speed=105 /
> maneuver_penalty=30, avoidances clamp LAST; onboarding requests location
> permission at END of onboarding (was mid-navigation = dropped dialog =
> "restart to get prompt" bug) + recenter button re-asks and invalidates the
> stream; creator builds have ALL archetypes unlocked in the picker;
> Settings → Avatar section (preview + count + opens picker); zoom-mode
> labels renamed "Zoomed out"/"Close up" (internals untouched).
>
> **PENDING DECISIONS (Ruben was answering when session ended):**
> 1. Self-hosted Valhalla approach (full guide + app config vs config-only
>    vs hold). App-side needed either way: valhallaApiUrl → env-configurable,
>    raise valhallaExcludePerimeterBudgetMeters + drop halving floor when
>    self-hosted. This unlocks "avoid EVERY camera" — the core feature at
>    full strength, plus origin/destination privacy.
> 2. Voice commands: YAY given. Stage 1 = one mic tap, parse "navigate to X"
>    from existing speech_to_text, geocode top hit, auto-route + TTS confirm.
>    Stage 2 = "Migo" wake word via Picovoice Porcupine (on-device, free
>    tier, needs Ruben account + key). Whisper NOT needed/appropriate.
>
> **UNVERIFIED:** egg-hatch ceremony live; hazard pin on-map visibility
> (check hazard layer toggle first); MapLibre real-drive behavior;
> avoidance retest post-alternates.

> **SESSION UPDATE 4 (2026-07-03): reliability pivot + provider config.**
> Ruben's directive, now a DESIGN PRINCIPLE: *reliability is a feature
> privacy depends on — privacy second to functionality. California-first
> accuracy matters; Europe-first does not.*
>
> - **Routing → managed provider (config swap):** valhallaApiUrl +
>   valhallaApiKey now come from env.json (VALHALLA_URL / VALHALLA_API_KEY).
>   Pre-pointed at Stadia's hosted Valhalla (https://api.stadiamaps.com/route/v1
>   — SAME Valhalla API, all exclude_polygons/alternates logic intact).
>   Ruben has a Stadia account (free tier: 200k credits/mo, NON-COMMERCIAL
>   only — fine pre-revenue). AWAITING: his key pasted into env.json + first
>   route test. If free tier gates the route endpoint, error surfacing will
>   say so. DO NOT swap to OSRM (no exclusions = kills ALPR avoidance);
>   OpenCage won't fix OSM address gaps (it's OSM under the hood).
> - **US CENSUS GEOCODER FALLBACK (big win):** when a typed house number
>   resolves nowhere in OSM, the Census TIGER geocoder (free, keyless,
>   public domain, every US address by block range) resolves it — fixed
>   "2229 S Mountain Ave Ontario" which OSM simply lacks. _censusSearch in
>   geocoding_service; results labeled "(US Census)".
> - Geocoding step-2 IF addresses still go missing after a test day: RADAR
>   (US-first autocomplete, ~100k/mo free) as primary. Smarty evaluated:
>   best US accuracy but 250 free lookups/mo = non-starter for autocomplete;
>   noted as future paid verification step.
> - **GL map fixes from road test:** avatar iconSize 1.0→1.25; camera CHASE
>   fix (avatar was outrunning the animating camera off-screen: target now
>   leads by speed×2s+50m, animation 600ms); follow-pause now on DRAG only
>   (onPointerMove — incidental taps were silently killing follow).
> - **Long-press map → save EXACT spot** (alley parking etc.) via the save
>   sheet; hint in empty saved-chips card. No "Save here" chip (space).
> - **Mission statement**: Settings → About → "Why Migo exists" — 4th
>   Amendment, "privacy doesn't make you a criminal", "Drive free."
> - **OPEN BUG — avatar picker "cannot select":** diagnostic debugPrint added
>   ('[avatar] picker: creatorMode=... unlocked=... selected=...').
>   PENDING Ruben's answer: are picker cells COLORED (creatorMode true,
>   selection plumbing bug) or PADLOCKED (CREATOR_MODE define not reaching
>   build)? Egg-hides-selection ordering already fixed in both render paths.
> - Egg got visible fracture lines. Avatar PNG spec for Ruben's ComfyUI art:
>   192×240 (or 384×480) transparent, base at ~90% height; two-layer
>   (vehicle + rider) enables auto-bob; drop in assets/avatars/, then wire
>   an asset-override in the avatar pipeline (NOT yet implemented).

> **SESSION UPDATE 5 (2026-07-03, later): ROUTING FIXED + GL PARITY.**
> This is the "make everything actually work" session. Note: model changed
> mid-project (Fable → Opus) — this doc is model-agnostic; whoever reads it
> next has the full story. Git remote had a parallel session's commit
> (someone else pushing to main); coordinate with `git pull --rebase origin
> main` before pushing.
>
> - **✅ MANAGED VALHALLA VERIFIED WORKING.** Ruben's Stadia key is in
>   env.json (VALHALLA_API_KEY) pointing at https://api.stadiamaps.com/route/v1.
>   A live test route (Upland→West Covina) returned a full valid route —
>   "status_message: Found route between points". The free-tier 502 hell is
>   OVER. `_routeUri()` in routing_service appends ?api_key= when a key is
>   set. NOTE: Stadia defaults to KILOMETERS; our request body forces
>   directions_options.units=miles so the parser (which expects miles) is
>   correct — leave that in.
> - **✅ CLUSTERED ALPR EXCLUSION POLYGONS (Ruben's idea, implemented).**
>   Instead of one octagon per camera (N×~919 m perimeter → Valhalla rejects
>   past ~10), cameras within alprClusterDistanceMeters (90 m ≈ 100 yd) merge
>   into ONE padded bounding box; lone cameras keep their octagon.
>   `_clusteredExcludePolygons` + `_clusterBox` in routing_service.
>   Selection cap raised (valhallaExcludePerimeterBudgetMeters 9500→45000)
>   since clustering compresses; halving-retry still the safety net.
>   `[routing] N cameras → M polygons after clustering` logs the compression.
>   FULL avoidance pipeline now: alternates:2 → local camera scoring → pick
>   cleanest (often 0 exclusions) → else clustered exclusions → halving retry,
>   all on reliable Stadia. STRONGEST it has ever been; still needs the final
>   on-road "Avoiding N zones" confirmation.
> - **✅ MAPLIBRE PHASE 4 + 5 DONE (GL map at feature parity):**
>   - All overlay markers render as GL symbols (painted offscreen → PNG →
>     addImage): ALPR (plum), all 7 hazard types (per-type icon via feature
>     'icon' property, one layer), gas (tap → price sheet), POIs (icon +
>     name label, zoom-gated at 14), destination = coral flag pin.
>     `_addPinImage` bakes them; `_syncOverlays` pushes GeoJSON honoring
>     layer toggles; `_onMapClick` queries rendered features for taps.
>   - Avatar is a real symbol now (Tux/egg/archetype, same rules as
>     UserLocationMarker) with a BAKED 10-FRAME BOB CYCLE cycled by a 110ms
>     timer (GL can't run CustomPainter per frame — flip-book trick).
>     iconSize 1.25. Egg-hides-selection bug fixed (selectedArchetype checked
>     before egg in BOTH paths).
>   - Camera parity: glFollowingProvider (drag pauses follow via
>     onPointerMove — taps don't), glRecenterSignalProvider (recenter button
>     bumps it → GL snaps back), onCameraIdle syncs currentZoomProvider.
>   - Chase fix: camera targets a point AHEAD (speed×2s+50m) so the avatar
>     rides lower-third and can't outrun the animation.
> - **US CENSUS FALLBACK confirmed fixing real addresses** (2229 S Mountain
>   Ave Ontario). Geocoding stack: Photon (autocomplete) → Nominatim
>   (compose/resolve) → Census (TIGER safety net). Radar is the paid step-2
>   if still weak. Geocodio noted (US-only, county data, good resolver).
> - **Long-press GL map → save exact spot** wired (onLongPress →
>   MigoMapLibreView → save sheet).
>
> **=== CURRENT STATE / WHAT TO DO NEXT (read this first) ===**
> - **DEFAULT MAP:** USE_MAPLIBRE=true in Ruben's env.json. The GL (tilted)
>   map has full marker + camera parity now. Once Ruben confirms a clean
>   drive, RETIRE the flutter_map path (it's the legacy fallback; both still
>   compile). flutter_map controller calls are all `useMapLibre`-guarded.
> - **env.json keys (git-ignored):** SUPABASE_URL/KEY, MAPTILER_API_KEY,
>   VALHALLA_URL (Stadia), VALHALLA_API_KEY (Stadia), CREATOR_MODE=true,
>   USE_MAPLIBRE=true. A fresh clone needs all of these.
> - **MIGRATIONS to run in Supabase SQL editor (idempotent):**
>   migration_alpr_import.sql (done long ago), migration_avatar_pool.sql
>   (adds unlocked_archetypes + selected_archetype — REQUIRED or profile
>   saves fail → coral-dot fallback avatar).
> - **OPEN/UNVERIFIED:**
>   1. Avatar picker "cannot select" — diagnostic `[avatar] picker:` line
>      added; need Ruben's report (colored cells = plumbing bug; padlocked =
>      CREATOR_MODE not reaching build). Egg-override already fixed.
>   2. Final on-road avoidance confirmation ("Avoiding N zones" / "Route is
>      clear"). Everything's in place; just needs the drive.
>   3. Real-drive feel of tilt/chase/heading-up at speed.
> - **NOT STARTED (agreed roadmap):**
>   - Voice commands Stage 1: one mic tap → parse "navigate to X" from
>     existing speech_to_text → geocode top hit → auto-route + TTS confirm.
>     Stage 2 = "Migo" wake word via Picovoice Porcupine (on-device, free
>     tier, needs Ruben's key). Whisper NOT appropriate.
>   - Avatar PNG asset override (Ruben making art in ComfyUI; spec above).
>   - Self-hosted Valhalla + Pelias/OpenAddresses geocoder = the privacy
>     endgame (unlimited exclusions, no third party, rooftop CA accuracy).
>     Deferred; Stadia bought the uptime for now.
>   - HANDOFF NOTE: this file (HANDOFF.md) is the canonical project handoff
>     regardless of which Claude model is driving.

These are the three things we were stuck on. Priority order is roughly 1 → 3.

### PROBLEM 1 — ALPR avoidance routing "dies" ⚠️ (highest priority)
**Symptom:** Cameras are now in the DB and show on the map. But when the user
enables **"ALPR camera avoidance"** (Settings → Privacy) and sets a destination,
**the routing fails / dies** — no route comes back (before the owned-DB change,
avoidance at least partially worked near the origin).

**Where to look:**
- `routing_provider.dart` → `RouteNotifier.calculate()`. When
  `prefs.avoidAlprCameras` is true it calls
  `alprService.fetchAlprForRoute(origin, destination)`.
- `alpr_service.dart` → `fetchAlprForRoute()` builds a bounding box around the
  **entire origin→destination corridor** (padded ~0.1°) and queries
  `alpr_locations` (`is_validated = true`) with **`.limit(2000)`**.
- `routing_service.dart` → `calculateRoute(...)` turns each camera into a Valhalla
  **`exclude_polygons`** entry.

**Strong hypothesis (please verify first):** SoCal is camera-dense (6,664 in the
region). The corridor query can now return **hundreds to 2,000** cameras, and we
hand all of them to Valhalla as `exclude_polygons`. Valhalla almost certainly
**rejects or times out** on a request with that many exclusion polygons — so the
route request errors and the UI shows nothing. Previously (live Overpass near
origin) the camera count was small, so it worked.

**Suggested directions (pick after confirming the cause):**
- Cap and prioritize: only exclude cameras **near the candidate route**, not the
  whole bbox. Chicken-and-egg (need a route first), so: get a baseline route
  without avoidance, then exclude only cameras within ~X meters of that polyline,
  then re-route once. Iterate at most once or twice.
- Or cluster nearby cameras into fewer, larger avoid-polygons to stay under
  Valhalla's limits.
- Or switch from `exclude_polygons` to Valhalla `exclude_locations` (avoid points)
  which may scale differently — test limits.
- Add real **error surfacing**: right now routing failure likely just yields an
  `AsyncError`/empty. Log the actual Valhalla HTTP response body so we can see
  the rejection reason. (We used the same "surface the error" trick to debug the
  vector tiles — do the same here.)
- Confirm the Valhalla endpoint/limits in `routing_service.dart` and
  `constants.dart`.

**Definition of done:** with avoidance on, a 10–30 mi SoCal route returns a valid
route that visibly bends around camera clusters, in reasonable time.

---

### PROBLEM 2 — GPS surging / rubber-banding + unstable position 🚗
**Symptom:** While actually driving, the avatar **surges and rubber-bands**
(jumps forward/back), especially around turns, and the GPS position is generally
**not stable/accurate** the way Google Maps feels glued to the road. Ruben has a
7" screen and drives in real traffic to test.

**What's already implemented (so you don't redo it):**
- `location_filter.dart` — a **Kalman filter** smooths raw GPS (outlier rejection
  via a max-speed guard). Piped through `location_service.dart`'s position stream.
- `location_service.dart` — navigation location settings use the **fused provider**
  (`forceLocationManager: false`), `distanceFilter: 0`, ~**1 Hz** interval,
  `LocationAccuracy.bestForNavigation` / automotive.
- `smooth_user_marker_layer.dart` — a **Ticker + dead-reckoning** approach that
  projects the avatar forward along its heading at current speed between fixes,
  re-anchoring on each new fix, holding still when parked.
- Relevant tunables in `constants.dart`: `kalmanProcessNoiseMetresPerSec`,
  `locationIntervalMs`, `markerPredictMaxSeconds`, `tripStart/StopSpeedMps`.

**IMPORTANT — this was NOT yet drive-tested after the latest smoothing changes.**
Treat current behavior as unverified.

**Analysis / recommended direction (agreed with Ruben):**
- Do **not** bother adding raw accelerometer sensor fusion. The Android **fused
  location provider already fuses** GPS + accelerometer + gyro internally;
  hand-rolling it means integration drift, unknown phone-to-car orientation, and
  reinventing the OS. Ruben ran a suggestion to "feed accelerometer into the
  Kalman velocity" past us and we (correctly) pushed back — don't go there first.
- The real "glued to the road" trick is **map-matching / snap-to-route.** During
  active navigation we already have the route polyline. **Project the displayed
  position onto the nearest point of the route** (within a threshold) so the
  avatar tracks the road instead of scattering onto parallel streets — this kills
  most of the visible surging on turns. When off-route (no active route), fall
  back to lighter smoothing.
- Also consider **softening the dead-reckoning** in `smooth_user_marker_layer.dart`
  (it may be over-projecting on turns) and tuning the Kalman noise.
- `routing_service.dart` already has `nearestSegmentIndex(point, polyline)` you can
  reuse for the snap.

**Definition of done:** on a real drive, the avatar glides smoothly, stays on the
road through turns, and doesn't jump backward.

---

### PROBLEM 3 — Dark map: roads/labels won't render (vector tiles) 🌙 (paused)
**Context:** We built a proper light/dark theme system (`buildBravoDarkTheme`,
`themeModeProvider`, Settings → Appearance toggle). The **UI/overlays flip
correctly** in dark mode, and there's a dark **raster** map (dark scrim over OSM
tiles) that works. The problem was making it a *real* Google-style dark map with
**big, bold, bright labels**, which raster tiles can't do (labels are baked into
the tile image).

**What we tried (and why it's paused):**
- Added **vector tiles**: `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0`
  + `vector_tile_renderer 5.2.0` (all confirmed compatible with `flutter_map 7.0.2`).
- Source: a **Protomaps PMTiles** dated planet build
  (`https://build.protomaps.com/YYYYMMDD.pmtiles` — the date **expires**; bump it
  from https://maps.protomaps.com/builds/ if it 404s).
- Pipeline: `vector_tiles_provider.dart` builds a `PmTilesVectorTileProvider` +
  an **inline** simple style (built in Dart to dodge asset-staleness) and hands it
  to a `VectorTileLayer` in `map_screen.dart` `_baseMapLayers()`.
- **Result:** vector tiles load and **fill layers render (buildings/land/water),
  but LINES (roads) and SYMBOLS (labels) never render** — proven even with a
  dead-simple constant-width, `["get","name"]`-label style and a confirmed hot
  restart. So it's **not** a styling-complexity issue; the Dart renderer just
  won't draw line/label geometry from these Protomaps tiles.

**Current state:** vector tiles are **disabled behind a flag** —
`kVectorTilesEnabled = false` in `map_screen.dart`. The app runs on the working
raster dark map. All the vector code/packages are intact; flip the flag to resume.

**Recommended next step (agreed):** switch to a renderer-**tested** combo. The
`vector_map_tiles` README lists styles it's verified against — **Dark Matter**
(dark) and **OSM Bright** (light) — which need **OpenMapTiles-schema** tiles from
a provider with a **free API key** (Stadia Maps is used in the package's own
example; MapTiler is an alternative). Use `StyleReader(uri: '<hosted style>.json?api_key={key}', apiKey: ...)`
— it wires theme + providers + sprites automatically, minimal code. Ruben needs
to create a free key first. This trades the offline/no-key ideal for something
that actually renders; we can revisit self-hosted Protomaps offline later.
- Do the label sizing in that style (`text-size` zoom-scaled, bold `text-font`,
  white `text-color` + dark `text-halo`) — Ruben specifically wants **larger,
  bolder, bright-white** street labels than the defaults (readable at a glance on
  a 7" screen).

**Definition of done:** dark mode shows a true dark basemap with visible roads and
large bold bright street/place labels; light mode likewise.

---

## 7. Conventions & gotchas

- **Task list / clarifying questions:** the environment supports a task list and
  a multiple-choice question tool — use them; Ruben likes visible progress and
  being asked before big/ambiguous work.
- **Privacy defaults are OFF** — every privacy-sensitive toggle defaults off; the
  user opts in. Don't silently enable things.
- **Voice guidance** was just fixed: the announcer gates on `ttsEnabledProvider`
  and `TtsService` defaults OFF, so the toggle truly silences it. (Was a bug
  where it defaulted on.)
- **Git:** remote is `github.com/PC-Master-Race/migo`, branch `main`. Committing
  from the sandbox leaves stale `.git/*.lock` files it can't delete (Windows/Linux
  permission boundary). Before pushing on the Windows side you may need:
  `del .git\HEAD.lock .git\index.lock` (PowerShell: `Remove-Item`). The
  ALPR/dark-mode batch is pushed; the vector-tile WIP was committed locally.
- **Don't expose internal sandbox paths** to the user; refer to files by repo path.
- **Speed limit "Unknown"** is expected in many spots — OSM lacks `maxspeed` tags
  on lots of roads; it's a data gap, not a bug.

---

## 8. Suggested first moves for the new session
1. Get it running: `flutter run --dart-define-from-file=env.json`, confirm not offline.
2. Tackle **Problem 1 (ALPR avoidance routing)** first — highest user value, and
   the "too many exclude_polygons" hypothesis is very likely and testable. Add
   error logging of the Valhalla response, confirm, then cap/prioritize cameras.
3. Then **Problem 2 (GPS smoothing)** via snap-to-route map-matching.
4. **Problem 3 (vector dark map)** last, and only once Ruben has a Stadia/MapTiler key.

Good luck — the bones of this app are solid. The hard parts left are routing
scale, GPS map-matching, and the vector renderer swap.
