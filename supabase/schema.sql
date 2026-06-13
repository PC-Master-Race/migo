-- schema.sql — Full Migo database schema.
-- Deploy this in the Supabase SQL editor (Dashboard > SQL Editor > New query).
-- Every table uses Row Level Security (RLS) — no user can read another user's
-- data except through explicitly designed sharing features (family groups).
-- Every column has a comment explaining what it stores and why.

-- Enable UUID generation (built into Supabase by default).
create extension if not exists "uuid-ossp";

-- ============================================================
-- TABLE: users
-- Core user account and preferences. Created automatically on
-- first auth; updated through the settings screen.
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
  id           uuid primary key default uuid_generate_v4(),
  owner_id     uuid not null references public.users(id) on delete cascade,
  -- Manufacturer name, e.g. "Toyota". Free text from onboarding.
  make         text not null,
  -- Model name, e.g. "Corolla". Free text from onboarding.
  model        text not null,
  -- Model year, e.g. 2019.
  year         integer not null check (year >= 1886 and year <= 2100),
  -- Real car color as hex string ("#FF6B5E"). Avatar is painted this color.
  color_hex    text not null check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  -- Body class: sedan, suv, truck, sportsCar, van, motorcycle.
  -- Determines the avatar's base body shape (Phase 4).
  vehicle_class text not null default 'sedan',
  created_at   timestamptz not null default now()
);

alter table public.vehicles enable row level security;

create policy "vehicles: owner only"
  on public.vehicles
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ============================================================
-- TABLE: archetypes
-- The user's current driving personality, recalculated after
-- each session. Archetypes evolve and are never permanently locked.
-- ============================================================
create table public.archetypes (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null unique references public.users(id) on delete cascade,
  -- The archetype currently shown on the user's avatar (enum name string).
  current_archetype text not null default 'responsibleEmployee',
  -- JSON blob of per-archetype affinity scores 0.0–1.0.
  -- Highest score wins the avatar; all scores kept so evolution is smooth.
  scores            jsonb not null default '{}',
  -- Earned overlay badges as a JSON array of badge name strings.
  badges            jsonb not null default '[]',
  updated_at        timestamptz not null default now()
);

alter table public.archetypes enable row level security;

create policy "archetypes: owner only"
  on public.archetypes
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
  -- >1.0 means arrived faster than estimated (good for Time Lord archetype).
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
-- User-reported map hazards with location and type.
-- Unconfirmed until community votes validate them.
-- ============================================================
create table public.hazards (
  id                    uuid primary key default uuid_generate_v4(),
  reporter_id           uuid not null references public.users(id) on delete cascade,
  -- Hazard type enum name (crash, alprCamera, debris, ice, construction,
  -- speedTrap, generalDisturbance). Maps to icon and alert sound.
  hazard_type           text not null,
  latitude              double precision not null,
  longitude             double precision not null,
  -- "Still there" votes from nearby users.
  confirmed_votes       integer not null default 0,
  -- "Gone now" votes from nearby users.
  dismissed_votes       integer not null default 0,
  -- True once community votes confirm it. Only confirmed hazards shown to all.
  is_community_confirmed boolean not null default false,
  -- When nearby users will be prompted "Is this still there?".
  expires_at            timestamptz,
  reported_at           timestamptz not null default now()
);

alter table public.hazards enable row level security;

-- Anyone can read confirmed hazards (they are public community data).
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
  id         uuid primary key default uuid_generate_v4(),
  hazard_id  uuid not null references public.hazards(id) on delete cascade,
  voter_id   uuid not null references public.users(id) on delete cascade,
  -- TRUE = "still there" (confirm), FALSE = "gone now" (dismiss).
  still_there boolean not null,
  voted_at   timestamptz not null default now(),
  unique (hazard_id, voter_id)
);

alter table public.hazard_votes enable row level security;

create policy "hazard_votes: own votes"
  on public.hazard_votes
  for all
  using (auth.uid() = voter_id)
  with check (auth.uid() = voter_id);

-- ============================================================
-- TABLE: alpr_locations
-- Known ALPR reader locations, community maintained.
-- ALPR avoidance data is NEVER sent to any third party.
-- ============================================================
create table public.alpr_locations (
  id            uuid primary key default uuid_generate_v4(),
  reporter_id   uuid not null references public.users(id) on delete cascade,
  latitude      double precision not null,
  longitude     double precision not null,
  -- Free-text description of the installation (e.g. "fixed gantry", "mobile van").
  description   text,
  -- Net community validation score. Positive = likely real, negative = likely wrong.
  validation_score integer not null default 0,
  -- True once validation_score crosses the confirmation threshold.
  is_validated  boolean not null default false,
  reported_at   timestamptz not null default now()
);

alter table public.alpr_locations enable row level security;

-- Validated ALPR locations are public community data (same as hazards).
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
-- TABLE: family_groups
-- Invite-based groups for real-time family location sharing.
-- ============================================================
create table public.family_groups (
  id           uuid primary key default uuid_generate_v4(),
  -- The user who created (and administers) this group.
  owner_id     uuid not null references public.users(id) on delete cascade,
  name         text not null,
  -- Short alphanumeric code used in invite links (e.g. "MIGO-X7K2").
  invite_code  text not null unique,
  created_at   timestamptz not null default now()
);

alter table public.family_groups enable row level security;

-- Only the owner-manages policy is created here. The "members read" policy
-- references public.family_members (created below) and must come AFTER that
-- table exists — Postgres validates table references in policies at creation
-- time, not query time. See "family_groups: members read" after family_members.
create policy "family_groups: owner manages"
  on public.family_groups
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ============================================================
-- TABLE: family_members
-- Members of a family group with per-member privacy settings.
-- ============================================================
create table public.family_members (
  id               uuid primary key default uuid_generate_v4(),
  group_id         uuid not null references public.family_groups(id) on delete cascade,
  user_id          uuid not null references public.users(id) on delete cascade,
  -- The user's chosen display name within this group (may differ from global name).
  nickname         text,
  -- Whether this member is currently sharing their location with the group.
  sharing_enabled  boolean not null default true,
  -- JSON: { "start": "HH:MM", "end": "HH:MM" } defining the daily sharing window.
  -- NULL means share always (when sharing_enabled is true).
  privacy_window   jsonb,
  joined_at        timestamptz not null default now(),
  unique (group_id, user_id)
);

alter table public.family_members enable row level security;

-- A member can see sibling members in the same group (to render their avatars).
create policy "family_members: group siblings read"
  on public.family_members
  for select
  using (
    exists (
      select 1 from public.family_members me
      where me.group_id = group_id and me.user_id = auth.uid()
    )
  );

create policy "family_members: own row manage"
  on public.family_members
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Now that family_members exists, add the family_groups read policy that
-- cross-references it. Placed here so the file runs clean top-to-bottom.
-- Members can read their group's metadata (needed to render the family map).
create policy "family_groups: members read"
  on public.family_groups
  for select
  using (
    auth.uid() = owner_id or
    exists (
      select 1 from public.family_members fm
      where fm.group_id = id and fm.user_id = auth.uid()
    )
  );

-- ============================================================
-- TABLE: gas_prices
-- Community-reported gas prices by station (OSM node ID).
-- ============================================================
create table public.gas_prices (
  id                  uuid primary key default uuid_generate_v4(),
  reporter_id         uuid not null references public.users(id) on delete cascade,
  -- OSM node ID of the fuel station (links to POI data via Overpass).
  osm_station_node_id bigint not null,
  latitude            double precision not null,
  longitude           double precision not null,
  -- Price in USD per gallon. Other currencies TODO when internationalizing.
  price_usd_per_gallon numeric(5, 3) not null check (price_usd_per_gallon > 0),
  -- Fuel grade: regular, midgrade, premium, diesel.
  fuel_grade          text not null default 'regular',
  reported_at         timestamptz not null default now()
);

alter table public.gas_prices enable row level security;

-- Gas prices are public community data — any authenticated user can read.
create policy "gas_prices: authenticated read"
  on public.gas_prices
  for select
  using (auth.role() = 'authenticated');

create policy "gas_prices: insert own"
  on public.gas_prices
  for insert
  with check (auth.uid() = reporter_id);

-- ============================================================
-- TABLE: user_reports
-- Bad-driver reports used for archetype reputation scoring
-- (Menace badge at 100+ reports per PRODUCT_BRIEF).
-- ============================================================
create table public.user_reports (
  id           uuid primary key default uuid_generate_v4(),
  reporter_id  uuid not null references public.users(id) on delete cascade,
  -- The user being reported. Never exposed to the reportee.
  reported_id  uuid not null references public.users(id) on delete cascade,
  -- Brief reason (aggressive driving, reckless, etc.). Free text.
  reason       text,
  -- Approximate location of the incident (coarsened to protect both parties).
  latitude     double precision,
  longitude    double precision,
  reported_at  timestamptz not null default now()
  -- Spam prevention (one report per reporter/reported pair per day) is
  -- enforced by idx_user_reports_spam_guard below, which uses a unique
  -- index on an expression — the correct Postgres pattern for functional
  -- uniqueness (an inline unique() constraint only accepts plain columns).
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
-- Why an IMMUTABLE wrapper function?
-- Postgres requires index expression functions to be IMMUTABLE (same inputs
-- always produce the same output). date_trunc(timestamptz) is only STABLE
-- because the result depends on the session timezone setting. By pinning to
-- 'UTC' inside an IMMUTABLE function we make the result genuinely constant
-- for any given input value — UTC has no DST rules, so the conversion is
-- deterministic.
create or replace function public.migo_report_day(ts timestamptz)
returns date
language sql
immutable
returns null on null input
as $$ select (ts at time zone 'UTC')::date $$;

create unique index idx_user_reports_spam_guard
  on public.user_reports (reporter_id, reported_id, public.migo_report_day(reported_at));

-- ============================================================
-- TABLE: achievements
-- Unlockable archetype milestones and rare discoveries.
-- Rare/secret achievements have obscured unlock conditions so
-- players discover them organically (Phase 4).
-- ============================================================
create table public.achievements (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references public.users(id) on delete cascade,
  -- Achievement identifier (e.g. "first_alpr_report", "secret_night_owl").
  achievement_key text not null,
  -- Human-readable title shown in the UI.
  title         text not null,
  -- Description shown after unlock. NULL for secret achievem
-- ============================================================
-- RPC: increment_hazard_confirmed
-- Called after a user casts a "still there" vote.
-- Increments confirmed_votes. If it crosses the community
-- threshold (3) the hazard is automatically marked confirmed.
--
-- Security: runs as SECURITY DEFINER so the RLS policy on
-- hazards (only owner can update) doesn't block the counter
-- increment. The function validates the caller is authenticated
-- and that the hazard exists before touching anything.
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
  -- Only authenticated callers may invoke this.
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.hazards
  set
    confirmed_votes        = confirmed_votes + 1,
    -- Auto-confirm once threshold is reached.
    is_community_confirmed = (confirmed_votes + 1) >= v_threshold
  where id = hazard_id;

  if not found then
    raise exception 'Hazard not found: %', hazard_id;
  end if;
end;
$$;

-- Only authenticated users can call this function.
revoke all on function public.increment_hazard_confirmed(uuid) from public;
grant execute on function public.increment_hazard_confirmed(uuid) to authenticated;

-- ============================================================
-- RPC: increment_hazard_dismissed
-- Called after a user casts a "gone / false alarm" vote.
-- Increments dismissed_votes. If dismissed votes dominate
-- (>= threshold) the hazard is soft-deleted (expires now).
--
-- Same SECURITY DEFINER rationale as above.
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
                        when (dismissed_votes + 1) >= v_threshold
                        then now()
                        else expires_at
                      end
  where id = hazard_id;

  if not found then
    raise exception 'Hazard not found: %', hazard_id;
  end if;
end;
$$;

revoke all on function public.increment_hazard_dismissed(uuid) from public;
grant execute on function public.increment_hazard_dismissed(uuid) to a