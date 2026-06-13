-- seed.sql — Development seed data for Migo.
-- Run this AFTER schema.sql in the Supabase SQL editor (with service role,
-- which is the default in the SQL editor).
--
-- Why we insert into auth.users first:
-- public.users has a FK to auth.users(id). Supabase manages auth.users through
-- its Auth service, but the SQL editor runs as the postgres superuser and can
-- insert directly. We create minimal auth rows so the FK is satisfied, then
-- create the corresponding public.users profile rows.
--
-- pgcrypto is required for crypt() and gen_salt(). It ships with Supabase by
-- default and is already enabled in most projects. If not: run
-- CREATE EXTENSION IF NOT EXISTS pgcrypto; before this file.

-- ============================================================
-- STEP 1: Auth users (satisfies the FK on public.users)
-- ============================================================
insert into auth.users (
  id,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  role,
  aud
)
values
  (
    '00000000-0000-0000-0000-000000000001',
    'devowner@migo.test',
    -- Password: migo-dev-owner (hashed with bcrypt — only for dev, never ship)
    crypt('migo-dev-owner', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    false, 'authenticated', 'authenticated'
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'testuser@migo.test',
    crypt('migo-test-user', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    false, 'authenticated', 'authenticated'
  )
on conflict (id) do nothing;

-- ============================================================
-- STEP 2: Public user profiles
-- ============================================================
insert into public.users (id, display_name, location_sharing_enabled, alpr_avoidance_enabled)
values
  ('00000000-0000-0000-0000-000000000001', 'Dev Owner', true,  true),
  ('00000000-0000-0000-0000-000000000002', 'Test User', false, false)
on conflict (id) do nothing;

-- ============================================================
-- STEP 3: Vehicles
-- ============================================================
insert into public.vehicles (owner_id, make, model, year, color_hex, vehicle_class)
values
  ('00000000-0000-0000-0000-000000000001', 'Tesla',  'Model 3', 2022, '#2C2C2C', 'sedan'),
  ('00000000-0000-0000-0000-000000000002', 'Toyota', 'Tacoma',  2020, '#B5A642', 'truck')
on conflict do nothing;

-- ============================================================
-- STEP 4: Archetypes
-- ============================================================
insert into public.archetypes (user_id, current_archetype, scores)
values
  ('00000000-0000-0000-0000-000000000001', 'secretAgent',
   '{"secretAgent": 0.72, "ecoWarrior": 0.45, "timeLord": 0.38}'),
  ('00000000-0000-0000-0000-000000000002', 'responsibleEmployee',
   '{"responsibleEmployee": 0.61, "trucker": 0.29}')
on conflict (user_id) do nothing;

-- ============================================================
-- STEP 5: Hazards (community-confirmed, Bay Area coordinates)
-- ============================================================
insert into public.hazards
  (reporter_id, hazard_type, latitude, longitude,
   confirmed_votes, dismissed_votes, is_community_confirmed)
values
  ('00000000-0000-0000-0000-000000000001', 'alprCamera',
   37.7749, -122.4194, 5, 0, true),
  ('00000000-0000-0000-0000-000000000001', 'speedTrap',
   37.7851, -122.4081, 3, 1, true),
  ('00000000-0000-0000-0000-000000000002', 'crash',
   37.7693, -122.4287, 4, 0, true)
on conflict do nothing;

-- ============================================================
-- STEP 6: ALPR locations (validated)
-- ============================================================
insert into public.alpr_locations
  (reporter_id, latitude, longitude, description, validation_score, is_validated)
values
  ('00000000-0000-0000-0000-000000000001', 37.7749, -122.4194,
   'Fixed gantry above Market St', 8, true),
  ('00000000-0000-0000-0000-000000000001', 37.7821, -122.4136,
   'Mobile unit spotted near Civic Center', 5, true)
on conflict do nothing;

-- ============================================================
-- STEP 7: Gas prices
-- ============================================================
insert into public.gas_prices
  (reporter_id, osm_station_node_id, latitude, longitude,
   price_usd_per_gallon, fuel_grade)
values
  ('00000000-0000-0000-0000-000000000002', 123456789, 37.7712, -122.4089, 4.599, 'regular'),
  ('00000000-0000-0000-0000-000000000002', 987654321, 37.7803, -122.4201, 4.799, 'premium')
on conflict do nothing;

-- ============================================================
-- STEP 8: Family group
-- ============================================================
insert into public.family_groups (owner_id, name, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'Dev Family', 'MIGO-DEV1')
on conflict do nothing;
