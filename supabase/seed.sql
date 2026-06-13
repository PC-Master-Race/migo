-- seed.sql — Development seed data for Migo.
-- Run this AFTER schema.sql in the Supabase SQL editor.
-- Provides two test users, vehicles, hazards, and ALPR locations so
-- Phase 1-2 development can run against realistic data without needing
-- a real device or community.
-- NOTE: These UUIDs are fixed for dev reproducibility. Replace with real
-- auth UUIDs from your Supabase Auth dashboard before seeding.

-- ============================================================
-- SEED USERS
-- Two test users: one as the product owner, one as a regular tester.
-- ============================================================
insert into public.users (id, display_name, location_sharing_enabled, alpr_avoidance_enabled)
values
  ('00000000-0000-0000-0000-000000000001', 'Dev Owner', true, true),
  ('00000000-0000-0000-0000-000000000002', 'Test User', false, false)
on conflict (id) do nothing;

-- ============================================================
-- SEED VEHICLES
-- ============================================================
insert into public.vehicles (owner_id, make, model, year, color_hex, vehicle_class)
values
  ('00000000-0000-0000-0000-000000000001', 'Tesla',  'Model 3', 2022, '#2C2C2C', 'sedan'),
  ('00000000-0000-0000-0000-000000000002', 'Toyota', 'Tacoma',  2020, '#B5A642', 'truck')
on conflict do nothing;

-- ============================================================
-- SEED ARCHETYPES
-- ============================================================
insert into public.archetypes (user_id, current_archetype, scores)
values
  ('00000000-0000-0000-0000-000000000001', 'secretAgent',
   '{"secretAgent": 0.72, "ecoWarrior": 0.45, "timeLord": 0.38}'),
  ('00000000-0000-0000-0000-000000000002', 'responsibleEmployee',
   '{"responsibleEmployee": 0.61, "trucker": 0.29}')
on conflict (user_id) do nothing;

-- ============================================================
-- SEED HAZARDS (community-confirmed for immediate map display)
-- Coordinates are in the San Francisco Bay Area for dev testing.
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
-- SEED ALPR LOCATIONS (validated for immediate avoidance routing)
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
-- SEED GAS PRICES (Bay Area stations)
-- ============================================================
insert into public.gas_prices
  (reporter_id, osm_station_node_id, latitude, longitude,
   price_usd_per_gallon, fuel_grade)
values
  ('00000000-0000-0000-0000-000000000002', 123456789, 37.7712, -122.4089, 4.599, 'regular'),
  ('00000000-0000-0000-0000-000000000002', 987654321, 37.7803, -122.4201, 4.799, 'premium')
on conflict do nothing;

-- ============================================================
-- SEED FAMILY GROUP
-- ============================================================
insert into public.family_groups (owner_id, name, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'Dev Family', 'MIGO-DEV1')
on conflict do nothing;
