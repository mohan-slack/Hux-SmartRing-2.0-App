# Supabase security checklist (HUX v1)

**HUX v1 design:** the app never reads or writes Supabase tables directly.
It only uses:

- **Auth** — sign-in.
- **Edge functions** — `coach-chat`, `analyze-meal`, `coach-report` and
  `delete-account`. Each one checks the caller itself in
  `supabase/functions/_shared/auth.ts` and uses the secret key on the server.

Every table therefore has RLS **on**, **no policies**, and **no grants** to
`anon` or `authenticated`. Migration `20261029010000_ai_usage_and_hardening.sql`
also makes that the default for future tables.

## A. Done in code

| Item | Where |
|---|---|
| RLS on every HUX table, no client grants | migrations `*_coach_usage`, `*_coach_reports`, `*_ai_usage_and_hardening` |
| Future tables, sequences and functions not exposed by default | `alter default privileges` in the hardening migration |
| `security definer` functions pin `search_path` and run only as `service_role` | `bump_coach_usage`, `bump_ai_usage` |
| Every function verifies the user via Auth (works with the new JWT signing keys) | `_shared/auth.ts` → `callerId` |
| Per-user daily AI limits: coach 30, meal photos 20 (IST day) | `ai_usage` + `withinDailyLimit` |
| Input size caps; context passed to the AI as data; no secrets or user text in logs | `coach-chat`, `analyze-meal` |
| Secret key and AI keys only in function secrets, never in the app | `supabase/functions/.env` (git-ignored) |
| Account delete cascades to every user row, plus Apple token revoke | `delete-account`, `on delete cascade` |
| Retention: usage counts 7 days; reported replies 90 days (cron) | hardening migration; cron SQL in `*_coach_reports.sql` |

## B. Dashboard settings (do once)

**Authentication**

| Setting | Value |
|---|---|
| Providers → Email | **Confirm email ON** |
| Password requirements | **Min length 8**, require **letters + digits** |
| Leaked-password protection | **ON** (needs the Pro plan) |
| Email OTP expiry | **900 seconds** (password-reset codes) |
| Anonymous sign-ins | **OFF** |
| Manual linking | **OFF** (unless needed) |
| Sessions | Refresh-token rotation **ON** (default), reuse interval 10 s |
| Rate limits | Keep the defaults. Add CAPTCHA (hCaptcha or Turnstile) if sign-up abuse appears. |
| Email templates → Reset password | Must contain `{{ .Token }}` (HUX uses a 6-digit code) |
| SMTP | Set a custom SMTP sender (e.g. no-reply@hux.co.in). The built-in sender is rate-limited and only meant for testing. |

**Project**

| Setting | Value |
|---|---|
| Region | **Mumbai (ap-south-1)** for India (latency and DPDP comfort) |
| Data API | Expose the **public** schema only (edge functions use it with the secret key) |
| Database → Network restrictions (Pro) | Allow only your office/home IP for direct DB access |
| Backups | Daily backups on (Pro). Note backup retention in the privacy policy. |

**Accounts and billing**

- Turn on **2FA** on the Supabase account and on the Groq and Apple
  developer accounts.
- Set a **spend cap** in Supabase billing and a **monthly limit** in the
  Groq console, so abuse can't run up the bill.
- Run **Advisors → Security Advisor** after `db push`. The goal is zero errors.

## C. Verify after `supabase db push` (SQL Editor)

```sql
-- 1) Tables in public WITHOUT RLS  → expect 0 rows
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

-- 2) Grants to app users on public tables → expect 0 rows
select table_name, grantee, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated');

-- 3) Public functions app users can execute → expect 0 rows
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
```

Then check from a terminal. Each command should be refused.

```bash
set -a; source .env; set +a
# No user token → 401
curl -s -X POST "$SUPABASE_URL/functions/v1/coach-chat" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -d '{}' -w ' %{http_code}\n'
# App key can't read tables → empty [] or 401/403, never data
curl -s "$SUPABASE_URL/rest/v1/coach_reports?select=*" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -w ' %{http_code}\n'
# App key can't call the counter → 401/403/404
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/bump_ai_usage" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' -d '{"p_user":"00000000-0000-0000-0000-000000000000","p_kind":"coach","p_limit":1}' -w ' %{http_code}\n'
```

## D. Rules for future features

1. A new table that holds user data **must** have:
   - `user_id uuid references auth.users(id) on delete cascade`
   - RLS on
2. If the **app** must read or write it directly, add both of these in the
   same migration:
   - an explicit `grant` to `authenticated`
   - RLS policies `using (auth.uid() = user_id)` / `with check (auth.uid() = user_id)`

   Otherwise go through an edge function.
3. Never use `user_metadata` for authorisation; users can edit it.
4. Never ship the secret key in the app.
5. Update `docs/release/STORE_FORMS.md` and the privacy policy whenever new
   data is stored on the server.
