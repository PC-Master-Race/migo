# Migo — Project Handoff

> Purpose of this doc: get a new AI session productive on the **Migo** app fast,
> and hand off three specific problems we're stuck on. Read this top to bottom
> once, then use the "Open Problems" section as the work queue.

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
