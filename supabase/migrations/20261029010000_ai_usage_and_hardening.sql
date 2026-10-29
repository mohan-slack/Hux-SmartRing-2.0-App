-- 1) One fair-use counter for every paid AI feature (coach, meal photos).
--    Replaces coach_usage for new code; coach_usage stays (harmless) until
--    a later cleanup migration drops it.
-- 2) Hardening: app users (anon/authenticated) get NO direct table access
--    in the public schema by default. HUX v1 clients never query tables —
--    all server data goes through edge functions with the secret key.
--    Any future table the APP must read needs an explicit GRANT + RLS
--    policy in its own migration.

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('coach', 'meal')),
  count integer not null default 0,
  primary key (user_id, day, kind)
);

alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

create or replace function public.bump_ai_usage(p_user uuid, p_kind text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_count integer;
begin
  insert into public.ai_usage as u (user_id, day, kind, count)
  values (p_user, v_day, p_kind, 1)
  on conflict (user_id, day, kind) do update set count = u.count + 1
  returning u.count into v_count;

  delete from public.ai_usage where user_id = p_user and day < v_day - 7;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.bump_ai_usage(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.bump_ai_usage(uuid, text, integer) to service_role;

-- Default privileges: future tables/functions/sequences in public are NOT
-- reachable by app users unless a migration grants it on purpose.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- Existing HUX tables: belt and braces.
revoke all on public.coach_usage from anon, authenticated;
revoke all on public.coach_reports from anon, authenticated;
revoke all on function public.bump_coach_usage(uuid, integer) from public, anon, authenticated;
