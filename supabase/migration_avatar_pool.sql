-- migration_avatar_pool.sql — Avatar pool (earned archetypes + user pick).
-- Run once in the Supabase SQL editor (idempotent).
--
-- unlocked_archetypes: every DrivingArchetype the user has EVER earned
--   (was dominant after a completed session, post-reveal). JSON array of
--   enum names, e.g. '["rocket","nightOwl"]'. Trophies — never removed.
-- selected_archetype: the user's chosen display override from that pool,
--   or NULL for automatic (show the current dominant archetype).

alter table public.archetype_profiles
  add column if not exists unlocked_archetypes jsonb not null default '[]';

alter table public.archetype_profiles
  add column if not exists selected_archetype text;
