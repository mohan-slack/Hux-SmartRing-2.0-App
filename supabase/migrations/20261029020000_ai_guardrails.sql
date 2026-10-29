-- AI guardrails (pre-launch hardening).
--
-- 1) A GLOBAL daily ceiling per AI feature, across all users. Per-user
--    limits alone don't bound the bill or protect the shared Groq rate
--    limit from scripted sign-ups or a launch spike.
-- 2) Refunds: a failed AI call (provider down, empty reply) gives the
--    user's — and the global — count back.
-- 3) 'report' as an ai_usage kind, so coach-report has a daily limit.
-- 4) Retention actually enforced (pg_cron), not just written in a comment:
--    coach_reports 90 days, usage counters 7 / 30 days.
-- 5) coach_usage (replaced by ai_usage) is dropped.

-- ---- 3) allow 'report' ---------------------------------------------------
alter table public.ai_usage drop constraint if exists ai_usage_kind_check;
alter table public.ai_usage
  add constraint ai_usage_kind_check check (kind in ('coach', 'meal', 'report'));

-- ---- 1) global counter ---------------------------------------------------
create table if not exists public.ai_usage_global (
  day date not null,
  kind text not null,
  count integer not null default 0,
  primary key (day, kind)
);
alter table public.ai_usage_global enable row level security;
revoke all on public.ai_usage_global from anon, authenticated;

create or replace function public.bump_ai_global(p_kind text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_count integer;
begin
  insert into public.ai_usage_global as g (day, kind, count)
  values (v_day, p_kind, 1)
  on conflict (day, kind) do update set count = g.count + 1
  returning g.count into v_count;
  return v_count <= p_limit;
end;
$$;

-- ---- 2) refunds ----------------------------------------------------------
create or replace function public.refund_ai_usage(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
begin
  update public.ai_usage set count = greatest(count - 1, 0)
    where user_id = p_user and day = v_day and kind = p_kind;
  update public.ai_usage_global set count = greatest(count - 1, 0)
    where day = v_day and kind = p_kind;
end;
$$;

revoke all on function public.bump_ai_global(text, integer) from public, anon, authenticated;
revoke all on function public.refund_ai_usage(uuid, text) from public, anon, authenticated;
grant execute on function public.bump_ai_global(text, integer) to service_role;
grant execute on function public.refund_ai_usage(uuid, text) to service_role;

-- ---- 4) retention (pg_cron) ----------------------------------------------
create extension if not exists pg_cron;

-- 03:15 IST = 21:45 UTC. Re-running this migration replaces the job.
select cron.unschedule('hux-retention') where exists (
  select 1 from cron.job where jobname = 'hux-retention'
);
select cron.schedule(
  'hux-retention',
  '45 21 * * *',
  $$
    delete from public.coach_reports where created_at < now() - interval '90 days';
    delete from public.ai_usage where day < (now() at time zone 'Asia/Kolkata')::date - 7;
    delete from public.ai_usage_global where day < (now() at time zone 'Asia/Kolkata')::date - 30;
  $$
);

-- ---- 5) old counter ------------------------------------------------------
drop function if exists public.bump_coach_usage(uuid, integer);
drop table if exists public.coach_usage;
