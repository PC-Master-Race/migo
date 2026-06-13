-- schema.sql — Full Bravo Maps database schema.
-- Deploy this in the Supabase SQL editor (Dashboard > SQL Editor > New query).
-- Runs cleanly top-to-bottom: tables are ordered by foreign-key dependency,
-- and any policy that references another table is created only after that
-- table (and any helper function it needs) already exists.
--
-- Privacy posture (PRODUCT_BRIEF): every table uses Row Level Security. No user
-- can read another user's data except through explicitly designed sharing
-- features (family groups). Every column has a comment explaining what it
-- stores and why. Table/column names here are the SINGLE SOURCE OF TRUTH and
-- match what the Dart services query — do not rename without updating the app.

-- Enable UUID generation (built into Supabase by default).
create extension if not exists "uuid-ossp";

-- ============================================================
-- TABLE: users
-- Core user account and preferences. Created on first auth;
-- updated through the settings screen.
-- ============================================================
create table public.users (
  id                       uuid primary key references auth.users(id) on delete cascade,
  -- Display name shown to family members only. Never exposed to strangers.
  display_name             text not null,
  -- Whether the user shares live location with their family group.
  -- Defaults FALSE: sharing is strictly opt-in (PRODUCT_BRIEF privacy rule).
  location_sharing_enabled boolean not null default false,
  -- Whether routing avoids known ALPR camera locations.
  -- Defaults FALSE per Phase 2 spec; user enables explicitly.
  alpr_avoidance_enabled   boolean not null default false,
  -- When the offline tile cache around home was last refreshed.
  -- NULL until the first WiFi prefetch completes.
  home_region_cached_at    timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

alter table public.users enable row level security;

-- Users can only read and write their own row.
create policy "users: own row only"
  on public.users
  for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ============================================================
-- TABLE: vehicles
-- The user's car. Make/model/year drives the avatar subtype;
-- color_hex paints the avatar the user's real car color.
-- ============================================================
create table public.vehicles (
  id            uuid primary key default uuid_generate_v4(),
  owner_id      uuid not null references public.users(id) on delete cascade,
  -- Manufacturer name, e.g. "Toyota". Free text from onboarding.
  make          text not null,
  -- Model name, e.g. "Corolla". Free text from onboarding.
  model         text not null,
  -- Model year, e.g. 2019.
  year          integer not null check (year >= 1886 and year <= 2100),
  -- Real car color as hex string ("#FF6B5E"). Avatar is painted this color.
  color_hex     text not null check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  -- Body class: sedan, suv, truck, sportsCar, van, motorcycle.
  -- Determines the avatar's base body shape (Phase 4).
  vehicle_class text not null default 'sedan',
  created_at    timestamptz not null default now()
);

alter table public.vehicles enable row level security;

create policy "vehicles: owner only"
  on public.vehicles
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ============================================================
-- TABLE: archetype_profiles
-- The user's current driving personality. One row per user,
-- recalculated at the end of each driving session. Archetypes
-- evolve and are never permanently locked. Column set matches
-- ArchetypeProfile.toJson() in lib/models/archetype_model.dart.
-- ============================================================
create table public.archetype_profiles (
  user_id           uuid primary key references public.users(id) on delete cascade,
  -- The archetype currently shown on the avatar (DrivingArchetype enum name,
  -- e.g. 'zenMaster', 'phantom', 'rocket'). 'zenMaster' is the calm default.
  current_archetype text not null default 'zenMaster',
  -- JSON map of per-archetype EMA affinity scores 0.0–1.0. Highest wins the
  -- avatar; all scores kept so evolution is smooth across sessions.
  scores            jsonb not null default '{}',
  -- A rare/secret archetype name if unlocked (RareArchetype enum), else NULL.
  rare_archetype    text,
  -- Earned overlay badges as a JSON array of AvatarBadge enum names.
  badges            jsonb not null default '[]',
  -- Total sessions completed (drives rare-unlock checks).
  session_count     integer not null default 0,
  -- Consecutive calendar days with at least one session (streak tracking).
  consecutive_days  integer not null default 0,
  updated_at        timestamptz default now()
);

alter table public.archetype_profiles enable row level security;

create policy "archetype_profiles: own only"
  on public.archetype_profiles
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- TABLE: driving_sessions
-- Raw driving data used to calculate archetypes. Anonymized:
-- never linked to real identity in any external call.
-- ============================================================
create table public.driving_sessions (
  id                    uuid primary key default uuid_generate_v4(),
  user_id               uuid not null references public.users(id) on delete cascade,
  started_at            timestamptz not null,
  ended_at              timestamptz,
  -- Total distance of the session in meters.
  distance_meters       double precision,
  -- Average GPS speed in m/s for the session.
  average_speed_mps     double precision,
  -- Max GPS speed in m/s recorded during the session.
  max_speed_mps         double precision,
  -- Aggression score 0.0–1.0 derived from acceleration/braking GPS deltas.
  aggression_score      double precision check (aggression_score between 0 and 1),
  -- Time efficiency: ratio of actual travel time to estimated travel time.
  time_efficiency_ratio double precision,
  -- Number of ALPR cameras reported during this session.
  alpr_reports_count    integer not null default 0,
  -- Number of hazards reported during this session.
  hazard_reports_count  integer not null default 0,
  created_at            timestamptz not null default now()
);

alter table public.driving_sessions enable row level security;

create policy "driving_sessions: owner only"
  on public.driving_sessions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- TABLE: hazards
-- User-reported map hazards. Unconfirmed until community votes
-- validate them. Only confirmed hazards are shown to all users.
-- ============================================================
create table public.hazards (
  id                     uuid primary key default uuid_generate_v4(),
  reporter_id            uuid not null references public.users(id) on delete cascade,
  -- Hazard type enum name (crash, alprCamera, debris, ice, construction,
  -- speedTrap, generalDisturbance). Maps to icon and alert sound.
  hazard_type            text not null,
  latitude               double precision not null,
  longitude              double precision not null,
  -- "Still there" votes from nearby users.
  confirmed_votes        integer not null default 0,
  -- "Gone now" votes from nearby users.
  dismissed_votes        integer not null default 0,
  -- True once community votes confirm it. Only confirmed hazards shown to all.
  is_community_confirmed boolean not null default false,
  -- When nearby users will be prompted "Is this still there?".
  expires_at             timestamptz,
  reported_at            timestamptz not null default now()
);

alter table public.hazards enable row level security;

-- Anyone can read confirmed hazards (public community data) or their own reports.
create policy "hazards: read confirmed"
  on public.hazards
  for select
  using (is_community_confirmed = true or auth.uid() = reporter_id);

-- Only authenticated users can insert hazards (as themselves).
create policy "hazards: insert own"
  on public.hazards
  for insert
  with check (auth.uid() = reporter_id);

-- ============================================================
-- TABLE: hazard_votes
-- Upvotes/downvotes on hazard validity. One vote per user per hazard.
-- ============================================================
create table public.hazard_votes (
  id          uuid primary key default uuid_generate_v4(),
  hazard_id   uuid not null references public.hazards(id) on delete cascade,
  voter_id    uuid not null references public.users(id) on delete cascade,
  -- TRUE = "still there" (confirm), FALSE = "gone now" (dismiss).
  still_there boolean not null,
  voted_at    timestamptz not null default now(),
  unique (hazard_id, voter_id)
);

alter table public.hazard_votes enable row level security;

create policy "hazard_votes: own votes"
  on public.hazard_votes
  for all
  using (auth.uid() = voter_id)
  with check (auth.uid() = voter_id);

-- ============================================================
-- RPC: increment_hazard_confirmed
-- Called after a "still there" vote. Increments confirmed_votes;
-- auto-confirms the hazard once the threshold (3) is reached.
--
-- SECURITY DEFINER so the owner-only UPDATE policy on hazards
-- doesn't block the counter increment. Validates the caller is
-- authenticated and the hazard exists before touching anything.
-- ============================================================
create or replace function public.increment_hazard_confirmed(hazard_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_threshold constant int := 3;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.hazards
  set
    confirmed_votes        = confirmed_votes + 1,
    is_community_confirmed = (confirmed_votes + 1) >= v_threshold
  where id = hazard_id;

  if not found then
    raise exception 'Hazard not found: %', hazard_id;
  end if;
end;
$$;

revoke all on function public.increment_hazard_confirmed(uuid) from public;
grant execute on function public.increment_hazard_confirmed(uuid) to authenticated;

-- ============================================================
-- RPC: increment_hazard_dismissed
-- Called after a "gone / false alarm" vote. Increments
-- dismissed_votes; once dismissals reach the threshold (3) the
-- hazard is expired immediately (soft delete).
--
-- Same SECURITY DEFINER rationale as increment_hazard_confirmed.
-- ============================================================
create or replace function public.increment_hazard_dismissed(hazard_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_threshold constant int := 3;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.hazards
  set
    dismissed_votes = dismissed_votes + 1,
    -- If enough people say it's gone, expire it immediately.
    expires_at      = case
                        when (dismissed_votes + 1) >= v_threshold then now()
                        else expires_at
                      end
  where id = hazard_id;

  if not found then
    raise exception 'Hazard not found: %', hazard_id;
  end if;
end;
$$;

revoke all on function public.increment_hazard_dismissed(uuid) from public;
grant execute on function public.increment_hazard_dismissed(uuid) to authenticated;

-- ============================================================
-- TABLE: alpr_locations
-- Known ALPR reader locations, community maintained.
-- ALPR avoidance data is NEVER sent to any third party.
-- ============================================================
create table public.alpr_locations (
  id               uuid primary key default uuid_generate_v4(),
  reporter_id      uuid not null references public.users(id) on delete cascade,
  latitude         double precision not null,
  longitude        double precision not null,
  -- Free-text description of the installation ("fixed gantry", "mobile van").
  description      text,
  -- Net community validation score. Positive = likely real, negative = likely wrong.
  validation_score integer not null default 0,
  -- True once validation_score crosses the confirmation threshold.
  is_validated     boolean not null default false,
  reported_at      timestamptz not null default now()
);

alter table public.alpr_locations enable row level security;

-- Validated ALPR locations are public community data (same model as hazards).
create policy "alpr_locations: read validated"
  on public.alpr_locations
  for select
  using (is_validated = true or auth.uid() = reporter_id);

create policy "alpr_locations: insert own"
  on public.alpr_locations
  for insert
  with check (auth.uid() = reporter_id);

-- ============================================================
-- TABLE: alpr_votes
-- Voting on ALPR location validity. One vote per user per location.
-- ============================================================
create table public.alpr_votes (
  id          uuid primary key default uuid_generate_v4(),
  location_id uuid not null references public.alpr_locations(id) on delete cascade,
  voter_id    uuid not null references public.users(id) on delete cascade,
  -- TRUE = "I saw it there", FALSE = "nothing there".
  confirmed   boolean not null,
  voted_at    timestamptz not null default now(),
  unique (location_id, voter_id)
);

alter table public.alpr_votes enable row level security;

create policy "alpr_votes: own votes"
  on public.alpr_votes
  for all
  using (auth.uid() = voter_id)
  with check (auth.uid() = voter_id);

-- ============================================================
-- FAMILY GROUPS & LIVE LOCATION SHARING (PRODUCT_BRIEF Phase 5)
--
-- PRIVACY: family_locations rows expire after 10 minutes. RLS
-- ensures only members of the same group can read each other's
-- data. No external service receives any location data.
--
-- ORDERING NOTE: the "members can read" policies need to test
-- group membership, which is itself stored in family_memberships.
-- A policy that subqueries its own table recursively triggers
-- Postgres "infinite recursion detected in policy". To avoid that,
-- membership is tested through the SECURITY DEFINER helper
-- is_family_group_member() defined AFTER the tables, and the
-- member-read policies are added after the helper exists.
-- ============================================================

-- TABLE: family_groups
create table public.family_groups (
  id          uuid primary key default uuid_generate_v4(),
  -- Human-readable group name chosen by the creator (e.g. "The Garcias").
  name        text not null,
  -- Alphanumeric invite code used in invite links. Never logged, never pushed.
  invite_code text not null unique,
  -- The user who created (and administers) this group.
  created_by  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

alter table public.family_groups enable row level security;

-- Any authenticated user can create a group (as themselves).
create policy "family_groups: authenticated insert"
  on public.family_groups
  for insert
  with check (auth.uid() = created_by);

-- Only the creator can update (e.g. regenerate the invite code).
create policy "family_groups: creator update"
  on public.family_groups
  for update
  using (auth.uid() = created_by);

-- Creator can delete (cascades to memberships + locations).
create policy "family_groups: creator delete"
  on public.family_groups
  for delete
  using (auth.uid() = created_by);

-- TABLE: family_memberships
create table public.family_memberships (
  group_id  uuid not null references public.family_groups(id) on delete cascade,
  user_id   uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.family_memberships enable row level security;

-- Authenticated users can join (insert themselves).
create policy "family_memberships: self insert"
  on public.family_memberships
  for insert
  with check (auth.uid() = user_id);

-- Users can only delete their own membership (leave group).
create policy "family_memberships: self delete"
  on public.family_memberships
  for delete
  using (auth.uid() = user_id);

-- TABLE: family_locations
-- Live GPS pings. expires_at enforces the 10-minute TTL. A pg_cron job
-- or Edge Function should periodically prune expired rows.
create table public.family_locations (
  user_id    uuid not null references public.users(id) on delete cascade,
  group_id   uuid not null references public.family_groups(id) on delete cascade,
  latitude   double precision not null,
  longitude  double precision not null,
  -- Speed in m/s from GPS — used for "driving vs parked" display.
  speed_mps  double precision not null default 0,
  updated_at timestamptz not null default now(),
  -- Row expires after 10 minutes. Prevents stale pings lingering on the map.
  expires_at timestamptz not null,
  primary key (user_id, group_id)
);

alter table public.family_locations enable row level security;

-- Users can only upsert/update/delete their own location row.
create policy "family_locations: own row insert"
  on public.family_locations
  for insert
  with check (auth.uid() = user_id);

create policy "family_locations: own row update"
  on public.family_locations
  for update
  using (auth.uid() = user_id);

create policy "family_locations: own row delete"
  on public.family_locations
  for delete
  using (auth.uid() = user_id);

-- Index for fast group-based queries (the Realtime stream filters by group_id).
create index idx_family_locations_group
  on public.family_locations (group_id, expires_at);

-- HELPER: is_family_group_member
-- Returns TRUE if the current auth user belongs to p_group_id.
-- SECURITY DEFINER means the internal SELECT runs as the function owner and
-- bypasses RLS on family_memberships — which is exactly what breaks the
-- recursion that a plain subquery-in-policy would cause.
create or replace function public.is_family_group_member(p_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.family_memberships
    where group_id = p_group_id and user_id = auth.uid()
  );
$$;

revoke all on function public.is_family_group_member(uuid) from public;
grant execute on function public.is_family_group_member(uuid) to authenticated;

-- Member-read policies (added now that the helper exists).
-- Members can read their group's metadata (to render the family map).
create policy "family_groups: members read"
  on public.family_groups
  for select
  using (auth.uid() = created_by or public.is_family_group_member(id));

-- Members can read the membership list of their own group.
create policy "family_memberships: members read"
  on public.family_memberships
  for select
  using (public.is_family_group_member(group_id));

-- Members can read each other's live location within a shared group.
create policy "family_locations: members read"
  on public.family_locations
  for select
  using (public.is_family_group_member(group_id));

-- ============================================================
-- TABLE: gas_prices
-- Community-reported fuel prices per station and grade. No
-- commercial feed; all data stays in Supabase. reporter_id is
-- used only to award Bravos and is never shown to others.
-- Column set matches GasPrice.toJson() in lib/models/gas_model.dart.
-- ============================================================
create table public.gas_prices (
  id               uuid primary key default uuid_generate_v4(),
  -- OSM node ID of the fuel station (text; joined with Overpass POI data).
  station_osm_id   text not null,
  -- Who reported this price — used ONLY to award Bravos, never shown to others.
  reporter_id      uuid not null references public.users(id) on delete cascade,
  -- Fuel grade (FuelGrade enum name).
  grade            text not null check (grade in ('regular','midgrade','premium','diesel')),
  -- Price in USD per gallon. Validated client-side to a sane range.
  price_per_gallon numeric(5,3) not null check (price_per_gallon between 0.50 and 15.00),
  reported_at      timestamptz not null default now()
);

alter table public.gas_prices enable row level security;

-- Any authenticated user can read gas prices (community transparency).
create policy "gas_prices: authenticated read"
  on public.gas_prices
  for select
  using (auth.role() = 'authenticated');

-- Users can only insert their own price reports.
create policy "gas_prices: insert own"
  on public.gas_prices
  for insert
  with check (auth.uid() = reporter_id);

-- Index for fast station-based lookups (merged with Overpass data).
create index idx_gas_prices_station
  on public.gas_prices (station_osm_id, reported_at desc);

-- ============================================================
-- TABLE: user_reports
-- Bad-driver reports used for archetype reputation scoring
-- (Menace badge at 100+ reports per PRODUCT_BRIEF).
-- ============================================================
create table public.user_reports (
  id          uuid primary key default uuid_generate_v4(),
  reporter_id uuid not null references public.users(id) on delete cascade,
  -- The user being reported. Never exposed to the reportee.
  reported_id uuid not null references public.users(id) on delete cascade,
  -- Brief reason (aggressive driving, reckless, etc.). Free text.
  reason      text,
  -- Approximate location of the incident (coarsened to protect both parties).
  latitude    double precision,
  longitude   double precision,
  reported_at timestamptz not null default now()
);

alter table public.user_reports enable row level security;

-- Reporter can see their own submitted reports only.
create policy "user_reports: reporter reads own"
  on public.user_reports
  for select
  using (auth.uid() = reporter_id);

create policy "user_reports: insert own"
  on public.user_reports
  for insert
  with check (auth.uid() = reporter_id);

-- Enforce one-report-per-pair-per-day.
--
-- Why an IMMUTABLE wrapper function? Postgres requires index expression
-- functions to be IMMUTABLE. date_trunc(timestamptz) is only STABLE because it
-- depends on the session timezone. Pinning to UTC inside an IMMUTABLE function
-- makes the result genuinely constant for any given input (UTC has no DST).
create or replace function public.bravo_report_day(ts timestamptz)
returns date
language sql
immutable
returns null on null input
as $$ select (ts at time zone 'UTC')::date $$;

create unique index idx_user_reports_spam_guard
  on public.user_reports (reporter_id, reported_id, public.bravo_report_day(reported_at));

-- ============================================================
-- TABLE: bravos_balance
-- Current Bravos (reward currency) balance + lifetime total per user.
-- ============================================================
create table public.bravos_balance (
  user_id         uuid primary key references public.users(id) on delete cascade,
  balance         integer not null default 0,
  lifetime_earned integer not null default 0,
  updated_at      timestamptz default now()
);

alter table public.bravos_balance enable row level security;

create policy "bravos_balance: own only"
  on public.bravos_balance
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- RPC: increment_bravos
-- Atomically increments balance and lifetime_earned, creating the
-- row on first earn. SECURITY DEFINER; rejects edits to other users.
-- ============================================================
create or replace function public.increment_bravos(p_user_id uuid, p_amount int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if auth.uid() != p_user_id then
    raise exception 'Cannot modify another user''s Bravos balance';
  end if;

  insert into public.bravos_balance (user_id, balance, lifetime_earned, updated_at)
  values (p_user_id, p_amount, p_amount, now())
  on conflict (user_id) do update
    set balance         = bravos_balance.balance + p_amount,
        lifetime_earned = bravos_balance.lifetime_earned + p_amount,
        updated_at      = now();
end;
$$;

revoke all on function public.increment_bravos(uuid, int) from public;
grant execute on function public.increment_bravos(uuid, int) to authenticated;

-- ============================================================
-- TABLE: achievements_earned
-- One row per achievement unlock per user. achievement_id is the
-- AchievementId enum name; bravos_awarded records the payout.
-- ============================================================
create table public.achievements_earned (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid not null references public.users(id) on delete cascade,
  achievement_id text not null,
  bravos_awarded integer not null default 0,
  earned_at      timestamptz not null default now(),
  unique (user_id, achievement_id)
);

alter table public.achievements_earned enable row level security;

create policy "achievements_earned: own only"
  on public.achievements_earned
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- TABLE: cosmetics_unlocked
-- Cosmetics the user has earned. is_equipped = user opted in to display.
-- ============================================================
create table public.cosmetics_unlocked (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.users(id) on delete cascade,
  cosmetic_id text not null,
  unlocked_at timestamptz not null default now(),
  is_equipped boolean not null default false,
  unique (user_id, cosmetic_id)
);

alter table public.cosmetics_unlocked enable row level security;

create policy "cosmetics_unlocked: own only"
  on public.cosmetics_unlocked
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
