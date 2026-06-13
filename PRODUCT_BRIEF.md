# MIGO — Product Brief & Cowork Session Prompt
**Version:** 1.0  
**Created:** June 2026  
**Author:** Ruben (Product Owner)  
**AI Development Partner:** Claude (Anthropic)  

---

## HOW TO USE THIS DOCUMENT

This is the master product brief for Migo, a privacy-first navigation app with a cartoon aesthetic. It serves two purposes:

1. **PRODUCT_BRIEF.md** — Lives in the root of the GitHub repo as portfolio documentation
2. **Cowork Session Prompt** — The section titled "COWORK SESSION PROMPT" below is copied and pasted directly into a Cowork session to begin development

Save this file as `PRODUCT_BRIEF.md` in the root of your GitHub repo before your first Cowork session.

---

## ABOUT THIS PROJECT

Migo is a personal navigation app built by one person using Claude Cowork as the primary development partner. The product owner served as architect, designer, and prompt engineer. This project demonstrates AI-assisted full-stack mobile development using Flutter, Supabase, and OpenStreetMap.

**Tech Stack:** Flutter (Android first, iOS ready), Supabase (backend), OpenStreetMap + Overpass API (map data), GitHub (version control)

**Development Model:** Claude Cowork (Opus 4.8) as co-developer across multiple sessions. Each session reads the existing repo before writing new code.

---

---

# COWORK SESSION PROMPT
> Copy everything below this line and paste it into your Cowork session.

---

## PROJECT: MIGO — Privacy-First Navigation App

You are the lead developer on Migo, a Flutter-based mobile navigation app. I am the product owner. Before writing any code, read this entire brief. Confirm you have read it and summarize the first phase of work before touching a single file.

**GitHub repo is connected. Read the existing repo structure before doing anything.** If the repo is empty, scaffold the full project structure first and commit it before writing any feature code.

---

## CORE PHILOSOPHY

Migo is a privacy-first, personality-driven navigation app. It uses OpenStreetMap data and avoids popular routes suggested by Google Maps and Waze. It never sells user data. It never shares data with insurance companies. ALPR (automated license plate reader) avoidance is a built-in feature and a core value of the app. Not being surveilled is treated as a human right in this codebase.

---

## TECH STACK — NON-NEGOTIABLE

- **Framework:** Flutter (Dart) — cross-platform, Android first. iOS support must be architecturally ready from day one even if not built yet. No Android-only APIs. No platform-specific code without a corresponding iOS stub.
- **Backend:** Supabase (Postgres, real-time, auth, storage) — no Firebase, no Google services in the backend
- **Maps:** OpenStreetMap tiles + Overpass API for POI and hazard data. Use `flutter_map` package for rendering.
- **Routing:** OSRM (Open Source Routing Machine) or Valhalla — evaluate both and choose the one with better Flutter integration and offline capability. Document your choice with reasoning in a comment at the top of the routing service file.
- **Local storage:** Hive or Isar for on-device caching — evaluate and choose, document reasoning
- **State management:** Riverpod
- **Version control:** GitHub — commit after every logical unit of work with descriptive commit messages

---

## CODE QUALITY STANDARDS — HARD REQUIREMENTS

Every file, every function, every session must follow these rules without exception:

1. **File header comment** — Every file starts with a 2-3 line comment block explaining what this file does and why it exists
2. **Function comments** — Every function gets a comment above it: what it does, what parameters mean, what it returns
3. **Section dividers** — Use `// --- SECTION NAME ---` to separate logical blocks within long files
4. **Descriptive naming** — `calculateFuelEfficientRoute()` not `calcR()`. `userDrivingArchetype` not `uda`. Names must be self-documenting.
5. **No magic numbers** — All constants defined at the top of the file or in a dedicated `constants.dart` with inline comments explaining what they represent and why that value
6. **Shallow nesting** — Maximum 2 levels of nesting inside a function. Extract deeper logic into named helper functions.
7. **TODO comments** — Every stub or placeholder gets `// TODO: [what goes here] [why it's deferred]`
8. **Commit messages** — Format: `[PHASE-X] descriptive message explaining what changed and why`

The product owner can read code but is not a daily developer. Code must be readable by someone who understands logic but has been away from development for a while.

---

## REPO STRUCTURE — SCAFFOLD THIS FIRST

```
migo/
├── android/                    ← Flutter-generated, minimal customization
├── ios/                        ← Flutter-generated, stubbed and ready
├── lib/
│   ├── main.dart               ← App entry point, theme, routing
│   ├── constants.dart          ← All app-wide constants in one place
│   ├── theme/
│   │   └── migo_theme.dart     ← Colors, fonts, cartoon style guide
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── route_model.dart
│   │   ├── hazard_model.dart
│   │   ├── archetype_model.dart
│   │   └── vehicle_model.dart
│   ├── services/
│   │   ├── map_service.dart        ← OSM tile fetching, offline cache
│   │   ├── routing_service.dart    ← OSRM/Valhalla route calculation
│   │   ├── location_service.dart   ← GPS, speed, background location
│   │   ├── hazard_service.dart     ← Hazard fetching, voting, reporting
│   │   ├── alpr_service.dart       ← ALPR database fetch and avoidance logic
│   │   ├── archetype_service.dart  ← Driving habit tracking and archetype calculation
│   │   ├── gas_price_service.dart  ← Gas price data fetching
│   │   └── supabase_service.dart   ← All Supabase interactions in one place
│   ├── providers/
│   │   └── [riverpod providers, one file per domain]
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── onboarding_screen.dart
│   │   ├── map_screen.dart         ← Main navigation screen
│   │   ├── settings_screen.dart
│   │   ├── route_options_screen.dart
│   │   └── family_screen.dart
│   ├── widgets/
│   │   ├── cartoon_avatar/         ← All avatar/archetype widgets
│   │   ├── hazard_icons/           ← Cartoon hazard marker widgets
│   │   ├── hud/                    ← Speed display, alert banners
│   │   └── map_controls/           ← Route option toggles, search bar
│   └── utils/
│       ├── map_utils.dart
│       ├── speed_utils.dart
│       └── archetype_utils.dart
├── assets/
│   ├── avatars/                ← SVG/PNG cartoon avatar assets
│   ├── hazard_icons/           ← Cartoon hazard marker assets
│   └── sounds/                 ← Alert sounds per hazard type
├── supabase/
│   ├── schema.sql              ← Full database schema
│   ├── seed.sql                ← Seed data for development
│   └── functions/              ← Supabase edge functions
├── docs/                       ← GitHub Pages site (portfolio landing page)
├── PRODUCT_BRIEF.md            ← This file
└── README.md                   ← Setup instructions, tech decisions log
```

---

## DATABASE SCHEMA — SUPABASE

Design and implement the following tables. Document every column with a SQL comment.

```sql
-- users: core user account and preferences
-- vehicles: user's car info, influences avatar color and type
-- archetypes: calculated driving personality, updates over time
-- driving_sessions: raw driving data used to calculate archetypes (anonymized)
-- hazards: user-reported map hazards with location and type
-- hazard_votes: upvotes/downvotes on hazard validity
-- alpr_locations: known ALPR reader locations, community maintained
-- alpr_votes: voting on ALPR location validity
-- family_groups: invite-based family location sharing groups
-- family_members: members of a family group with privacy settings
-- gas_prices: community-reported gas prices by station location
-- user_reports: bad driver reports, used for archetype reputation scoring
-- achievements: unlockable archetype milestones and rare discoveries
```

---

## PHASE PLAN

Build in this exact order. Do not skip ahead. Complete each phase fully before moving to the next. At the end of each phase, commit everything and write a summary of what was built and what comes next in `README.md`.

### PHASE 1 — Foundation & Map (Session 1-2)
- Flutter project scaffold with full folder structure
- `flutter_map` rendering OSM tiles
- GPS location tracking (background capable)
- Basic map display centered on user location
- Offline tile caching: auto-download 100-mile radius around user location on WiFi, dynamic fetch outside that radius
- Map update strategy: weekly base sync on WiFi only, delta updates on app launch
- Speed display HUD (GPS-based, mph)
- Speed limit display from OSM data, shows "Unknown" gracefully when data missing
- Zoom behavior: cartoon art style at zoom out, transitions to satellite/street view on deep zoom
- Supabase project connected, schema deployed, auth working

### PHASE 2 — Routing Engine (Session 2-3)
- Integrate OSRM or Valhalla (document choice)
- Route calculation with these toggle options (all can be changed mid-route, triggers instant recalculation):
  - Fastest route (default)
  - Shortest distance
  - Most fuel efficient
  - Fewest stops
  - Avoid freeways
  - Avoid toll roads
  - Avoid popular routes (deprioritize high-traffic corridors used by Google/Waze)
- ALPR avoidance toggle (off by default, uses ALPR location database)
- Turn-by-turn directions
- Route recalculation on deviation
- Voice guidance infrastructure: build the text-to-speech hook but use Flutter's default TTS for now. Leave a clearly marked TODO for ElevenLabs integration later.

### PHASE 3 — Hazard System (Session 3-4)
- Hazard reporting: users drop a pin and select from cartoon icon list
- Hazard icon types (all cartoon style, cute but clear):
  - Crashed car
  - ALPR camera (camera icon + "ALPR" label)
  - Debris/trash on road
  - Ice/road hazard (ice cube)
  - Construction
  - Speed trap (cartoon cop looking into car with clipboard)
  - General disturbance
- Voting system: hazards require community confirmation before showing to all users
- Hazard expiry: system prompts nearby users "Is this still there?" after time threshold
- 2-mile proximity alert: audio + visual banner when approaching a hazard
- Auto-dismiss alerts: banners close automatically, never require user tap
- Different alert sounds per hazard type. ALPR = ominous/subtle tone. Crash = urgent. Speed trap = distinct alert.
- ALPR database: pull from open community databases (research best available open ALPR location datasets). Layer user reports on top. Secret Agent archetype reward for frequent ALPR reporters.

### PHASE 4 — Avatar & Archetype System (Session 4-5)
- Driving session data collection: speed consistency, aggression (acceleration/braking patterns via GPS delta), time efficiency, fuel efficiency proxy, ALPR reports submitted, hazard reports submitted, bad driver reports received
- Archetype calculation engine: runs after each session, updates user's archetype score over time. Archetypes evolve as habits change, never permanently locked.
- **Core archetypes (implement all, each has a unique cartoon avatar):**
  - Grandpa Driver — consistently slow, smooth, cautious (little old man with cane and beret in a classic car)
  - Angsty Teen — aggressive, fast, frequent hard braking (teen with headphones in a beat-up car)
  - Responsible Employee — consistent, average, reliable (slightly harried middle-aged person in a sensible sedan)
  - Speed Demon — consistently high speed, time efficient (racing helmet, flames)
  - Eco Warrior — fuel efficient routes, smooth driving (green leaf motif, hybrid car)
  - Trucker — long drives, highway miles, consistent pace (happy big rig, CB radio)
  - Secret Agent — high ALPR reporter, privacy-conscious routes (trench coat, fedora, sleek dark car)
  - Time Lord — consistently arrives at ETA or earlier (pocket watch, bow tie)
  - Chili Pepper — crowdsourced hotness badge, 100+ people must mark. Icon added as overlay on existing avatar.
  - Menace Badge — 100+ bad driver reports. Escalates: badge → crown of thorns → elaborate bling crown as reports accumulate. Gender agnostic design.
  - **Creator Badge** — hardcoded to one specific account (product owner). Unique icon, never earnable by others. Flag this in code with a comment explaining it.
- **Rare/secret archetypes:** Build the infrastructure for hidden unlock conditions. Stub at least 3 rare archetypes with TODO comments describing what triggers them. Players should discover these organically.
- Avatar properties: cartoon style, color matches user's real car color from vehicle profile, moves on map
- Gas station behavior: when user is at a gas station (detected by location + OSM POI data), avatar switches to a cute eating/fueling animation
- Car info influences avatar subtype: user enters make, model, year, color. Color maps to avatar color. Vehicle class (sedan, truck, SUV, sports car, etc.) influences base avatar body shape.

### PHASE 5 — Social & Family Features (Session 5-6)
- Family groups: invite via link or code (Life360-style)
- Family members see each other's avatars on map in real time via Supabase real-time
- Location context for family only:
  - At home: avatar does a gentle idle animation in home location
  - At work (learned from habit): avatar shows working pose — family only
  - At gas station: eating animation — family only context
  - Moving: normal driving avatar
- Non-family users: see cars on map as anonymous avatars only, no location context
- Optional location sharing: users can toggle off entirely
- Privacy windows: build the data model and UI toggle for time-based sharing (e.g. share only 8am-6pm) — implement fully, this is important
- Demo mode: simulate multiple users on the map for solo testing. Generates fake avatar cars with randomized archetypes moving on nearby roads realistically.

### PHASE 6 — Gas Prices & POI (Session 6)
- Research and integrate best available free gas price data source (check OSM fuel data, GasBuddy open endpoints, any others with free tier)
- Community gas price reporting: users can report price at any gas station
- Gas station POI display: show price on map marker when available
- Location star ratings: when zoomed into street level, show star rating and busyness if available from a free data source. If no free source with adequate coverage exists, omit this feature entirely and leave a TODO.

### PHASE 7 — Onboarding, Settings & Polish (Session 7)
- Splash screen with Migo branding and cartoon character
- Minimal onboarding: name, car info (make, model, year, color), done
- Splash screen text: "You can add more in Settings anytime — favorite places, route preferences, privacy options, and more."
- Settings screen with all toggles clearly labeled and grouped:
  - Route preferences (fuel efficient, shortest, fastest, fewest stops, avoid freeway, avoid tolls, avoid popular routes)
  - Privacy (ALPR avoidance toggle, location sharing toggle, family group management)
  - Vehicle profile
  - Notification preferences
  - Map preferences (offline cache radius, update on WiFi only)
- Notification system: hazard alerts, family location events, archetype milestone unlocks

---

## MAP BEHAVIOR DETAILS

- **Zoom levels — three distinct modes:**
  - Zoomed out: full cartoon art style, neighborhood names, simplified roads, avatar cars visible
  - Mid zoom: hybrid — road details appear, avatars still visible, cartoon color palette
  - Street level: switches to satellite or OSM street view. Cartoon avatar disappears. Store/POI icons appear with star rating if data available.
- **Tile caching:**
  - On WiFi: auto-cache 100-mile radius around user's frequent locations
  - Outside cache: dynamic tile fetch
  - Weekly full sync on WiFi
  - Delta updates (changed data only) on app launch regardless of connection
  - Never auto-download on cellular without user permission

---

## DESIGN SYSTEM

- **Art style:** Cute, cartoon, warm. Think friendly mobile game aesthetic, not sterile maps.
- **Color palette:** Warm and friendly. Avoid cold blues and corporate grays. Use the cartoon palette consistently across all UI elements.
- **Typography:** Rounded, friendly font. Nunito or Fredoka One — evaluate and choose, document in `migo_theme.dart`
- **Hazard icons:** All cartoon. Cute but immediately recognizable. Consistent art style across all icons.
- **Avatars:** All cartoon. Anthropomorphized driving archetypes. Characters should be expressive and fun. Gender agnostic where possible unless archetype is inherently gendered (grandpa is fine, but consider grandma variant too).
- **No dark patterns:** No popups that require tapping to close while driving. No distracting animations while in active navigation mode.

---

## DATA PRIVACY RULES — BAKED INTO THE ARCHITECTURE

These are not features, they are constraints. Implement them from the start.

- No analytics SDK from Google, Meta, or any ad network. Ever.
- No data sold or shared with third parties. Ever.
- No insurance company data sharing. Ever.
- Driving session data used only for archetype calculation, anonymized, never linked to real identity in any external call
- ALPR avoidance data never sent to any third party
- Location data for family sharing: transmitted only to Supabase, visible only to authorized family group members
- All Supabase tables use row-level security. No user can read another user's data except through explicitly designed sharing features.

---

## WHAT TO DO AT THE START OF EVERY SESSION

1. Read the entire repo — understand current state before writing anything
2. Read `README.md` — check the phase summary and what was completed last session
3. Summarize what you see and what you plan to do this session
4. Wait for product owner confirmation before writing code
5. After completing work, update `README.md` with what was done and what comes next
6. Commit everything with descriptive commit messages in format: `[PHASE-X] description`

---

## WHAT NOT TO DO

- Do not use any Google services in the backend (Firebase, Google Analytics, AdMob, etc.)
- Do not write platform-specific Android code without an iOS stub
- Do not skip the code quality standards — comments, naming, section dividers are required
- Do not bundle features from multiple phases in one session
- Do not use magic numbers anywhere in the codebase
- Do not use nested functions more than 2 levels deep
- Do not commit broken code — if something is incomplete, stub it with a TODO

---

## SESSION 1 SPECIFIC INSTRUCTIONS

This is the first session. The repo exists but is empty. Do the following in order:

1. Scaffold the full Flutter project with the folder structure defined above
2. Set up `flutter_map` with OSM tile rendering
3. Implement GPS location service with background capability
4. Display user location on the map centered and following
5. Implement the three zoom-level behaviors (cartoon → hybrid → satellite/street)
6. Implement offline tile caching with 100-mile auto-download on WiFi
7. Add basic speed HUD displaying GPS speed in mph
8. Connect Supabase: deploy the full schema, confirm auth works
9. Commit everything
10. Update README.md with what was built and what Phase 2 requires

Do not start Phase 2 routing work in this session. Foundation must be solid first.

---

*End of Cowork Session Prompt*

---

## APPENDIX: DESIGN DECISIONS LOG

Use this section to document major decisions made during development. Add to it each session.

| Decision | Options Considered | Choice Made | Reason |
|---|---|---|---|
| Framework | React Native, Flutter, Kotlin native | Flutter | Cross-platform ready, strong map support, single codebase |
| Backend | Firebase, Supabase, self-hosted | Supabase | Open source, Postgres, real-time, no Google dependency |
| Map rendering | Mapbox, OsmAnd, flutter_map | flutter_map | OSM native, free, no API key required for basic use |
| Routing engine | OSRM, Valhalla | TBD — Cowork to evaluate and document | — |
| Local storage | Hive, Isar, SQLite | TBD — Cowork to evaluate and document | — |
| State management | Provider, Bloc, Riverpod | Riverpod | Modern, testable, recommended for new Flutter projects |
| Typography | Nunito, Fredoka One | TBD — Cowork to evaluate and document | — |
