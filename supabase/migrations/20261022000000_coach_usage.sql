-- HUX coach fair-use counter: one row per user per IST day.
-- Stores ONLY a count — never chat text or health data.
-- Only the coach-chat edge function (service role) can touch it.

create table if not exists public.coach_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0,
  primary key (user_id, day)
);

alter table public.coach_usage enable row level security;
-- No policies on purpose: app users (anon/authenticated) get no access.
revoke all on public.coach_usage from anon, authenticated;

-- Adds one message for today (IST) and returns true while within the limit.
create or replace function public.bump_coach_usage(p_user uuid, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_count integer;
begin
  insert into public.coach_usage as u (user_id, day, count)
  values (p_user, v_day, 1)
  on conflict (user_id, day) do update set count = u.count + 1
  returning u.count into v_count;

  -- Old rows are not needed once the day has passed.
  delete from public.coach_usage where user_id = p_user and day < v_day - 7;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.bump_coach_usage(uuid, integer) from public, anon, authenticated;
grant execute on function public.bump_coach_usage(uuid, integer) to service_role;
