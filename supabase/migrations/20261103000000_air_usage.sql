-- Allow the per-user daily counter to count "air" (air-heat function).
alter table public.ai_usage drop constraint if exists ai_usage_kind_check;
alter table public.ai_usage
  add constraint ai_usage_kind_check check (kind in ('coach', 'meal', 'report', 'air'));
