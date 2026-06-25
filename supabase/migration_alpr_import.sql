-- migration_alpr_import.sql — ALPR camera bulk-import support.
-- Run this ONCE in the Supabase SQL Editor (it's idempotent — safe to re-run).
--
-- Lets OSM/DeFlock-imported cameras live in alpr_locations alongside community
-- reports, and adds a function the app calls to bulk-load them.

-- 1. Reporter is optional now: OSM-imported cameras have no user reporter.
alter table public.alpr_locations alter column reporter_id drop not null;

-- 2. Where a row came from: 'osm' (bulk import) or 'community' (user report).
alter table public.alpr_locations
  add column if not exists source text not null default 'community';

-- 3. OSM node id, for de-duplicating on re-import (NULL for community reports).
alter table public.alpr_locations
  add column if not exists osm_node_id bigint;

-- Unique index: NULLs are distinct in Postgres, so community rows (NULL node id)
-- never collide; OSM rows de-dupe by their node id.
create unique index if not exists idx_alpr_osm_node
  on public.alpr_locations (osm_node_id);

-- 4. Bulk-upsert OSM cameras. SECURITY DEFINER so the trusted import bypasses
-- the per-user insert RLS. Input: a JSON array of {id, lat, lon}.
create or replace function public.upsert_osm_alpr(p_cameras jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
  cam jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  for cam in select * from jsonb_array_elements(p_cameras)
  loop
    insert into public.alpr_locations
      (latitude, longitude, source, is_validated, validation_score, osm_node_id)
    values (
      (cam->>'lat')::double precision,
      (cam->>'lon')::double precision,
      'osm', true, 5, (cam->>'id')::bigint
    )
    on conflict (osm_node_id) do nothing;
    if found then
      affected := affected + 1;
    end if;
  end loop;

  return affected;
end;
$$;

revoke all on function public.upsert_osm_alpr(jsonb) from public;
grant execute on function public.upsert_osm_alpr(jsonb) to authenticated;
