# Connect HUX to a (new) Supabase project

Three local files hold every value. All are git-ignored; the `.example`
copies are committed.

| File | Holds | Used by |
|---|---|---|
| `.env` | URL, publishable key, Google web client ID, Open-Meteo key | The **app** (compiled in) |
| `supabase/functions/.env` | Groq key and models, Apple keys | **Edge functions** (`supabase secrets set`) |
| `supabase/.env.cli` | Project ref, access token, DB password | **Supabase CLI** on your Mac |

> **Never** put a secret key, service-role key, DB password, Groq key or
> `.p8` in `.env`. Everything in `.env` ends up inside the app.

## 1. Dashboard (new project)

1. **Create the project.** Choose region **Mumbai (ap-south-1)** for India
   users, and save the DB password in `supabase/.env.cli`.
2. **Get the app keys.** Go to Project Settings → **Data API** for the URL and
   → **API Keys** for the publishable key. Put both in `.env`.
3. **Email sign-in.** Authentication → Providers → **Email**: on.
   - "Confirm email" on is recommended.
   - Password reset uses a 6-digit code, so edit Authentication → Email
     Templates → "Reset password" to include `{{ .Token }}`.
4. **Google sign-in.** Authentication → Providers → **Google**: on.
   - Paste the Google **Web** client ID and secret.
   - Add the iOS client ID to "Authorized Client IDs".
   - Put the same web client ID in `.env` as `GOOGLE_WEB_CLIENT_ID`.
5. **Apple sign-in.** Authentication → Providers → **Apple**: on.
   - Add `in.co.hux.huxApp` under Client IDs. That is enough for native iOS
     sign-in.
6. **Old "legacy" keys.** If the project has no legacy anon/service_role keys
   (new-style keys only), fill `HUX_PUBLISHABLE_KEY` and `HUX_SECRET_KEY` in
   `supabase/functions/.env`. The functions fall back to those.

## 2. CLI (on your Mac)

```bash
brew install supabase/tap/supabase
set -a; source supabase/.env.cli; set +a
supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD"
supabase db push                                    # coach_usage, coach_reports
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy analyze-meal coach-chat coach-report delete-account
```

Then in Database → Cron, schedule the 90-day purge. The SQL is at the bottom of
`supabase/migrations/20261029000000_coach_reports.sql`.

## 3. Run and build the app

```bash
flutter run --dart-define-from-file=.env
flutter build appbundle --release --dart-define-from-file=.env
flutter build ipa --release --dart-define-from-file=.env
```

If you build without the `.env` file, the app shows a "HUX isn't configured"
screen instead of crashing.

## 4. Not in `.env` (platform files)

| Item | Where it goes |
|---|---|
| **iOS Google sign-in** | Add the reversed iOS client ID (`com.googleusercontent.apps.XXXX`) as a URL scheme in `ios/Runner/Info.plist` → `CFBundleURLTypes` |
| **Android Google sign-in** | Add the debug and release SHA-1 fingerprints to the Android OAuth client in Google Cloud |
| **Old project** | `supabase/.temp/` still holds the old project ref. Run `git rm -r --cached supabase/.temp` once; it's ignored from now on |
