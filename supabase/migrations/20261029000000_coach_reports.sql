-- Reports of AI coach replies (Google Play AI-Generated Content policy).
-- Holds the reported reply + the question before it. No health summary.
-- Only the coach-report edge function (service role) can write; the HUX
-- team reviews in the Supabase dashboard. Deleted with the account.

create table if not exists public.coach_reports (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  reason text not null check (reason in ('harmful', 'wrong', 'offensive', 'other')),
  reply text not null,
  question text,
  reviewed boolean not null default false
);

alter table public.coach_reports enable row level security;
-- No policies on purpose: app users (anon/authenticated) get no access.
revoke all on public.coach_reports from anon, authenticated;

create index if not exists coach_reports_created_idx on public.coach_reports (created_at);

-- Retention: 90 days. Run daily (Supabase → Database → Cron, pg_cron):
--   select cron.schedule('purge-coach-reports', '15 3 * * *',
--     $$delete from public.coach_reports where created_at < now() - interval '90 days'$$);
