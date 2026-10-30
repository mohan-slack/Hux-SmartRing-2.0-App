# HUX v1 — Launch checklist

Tick items as they're done. Each section links to the doc with the details.

**Owners:** M = Mohan · L = lawyer · N = nutritionist · D = designer/marketing

**Status today:** all v1 features are built, and 465/465 tests pass. Supabase is
deployed. Everything below is about running on real phones, accounts, legal and
the stores.

## A. Code & build (M)

- [ ] Re-run `flutter analyze && flutter test` after the latest changes (Today, Trends, Story footers).
- [ ] Run `dart run flutter_native_splash:create` and commit what it generates (app icons are already committed — see BRANDING.md).
- [ ] `flutter run --dart-define-from-file=.env` on a **real iPhone** and a **real Android phone** (Health data, notifications and voice cues behave differently on simulators). Walk through:
  - [ ] Privacy notice (18+), onboarding, featured cards
  - [ ] Health permissions are granted, and Today / Trends / Story fill in
  - [ ] Coach: reply, safety card (type "chest pain"), Report, daily limit message
  - [ ] Meal photo and typed meal, protein gap
  - [ ] Walk and sit nudges arrive with the pink H icon; air & heat alert for your city
  - [ ] A guided plan with voice in English and Hindi, with the phone locked mid-session
  - [ ] Streaks and monthly report
  - [ ] Privacy & account: download my data, delete data on this phone, delete account (on a test account)
  - [ ] Sign in with Google and Apple, and password reset by code
- [ ] Delete `.preview_tmp/`, run `git rm -r --cached supabase/.temp`, then commit on `fix/review-high-priority`, open a PR and merge.
- [ ] Tag the release: `git tag v1.0.0+1`.

## B. Accounts & keys (M)

- [ ] Apple Developer Program, enrolled **as the organisation** (needs the D-U-N-S number).
- [ ] Google Play Console, registered **as the organisation**. This avoids the 12-tester, 14-day rule for personal accounts.
- [ ] Android upload key made (`docs/release/SIGNING.md`). The `.jks` file and passwords are backed up in 2 places.
- [ ] App ID `in.co.hux.huxApp` registered with HealthKit and Sign in with Apple. Apple key added to `supabase/functions/.env`, then run `supabase secrets set`.
- [ ] Google Cloud OAuth:
  - [ ] iOS client ID added to `Info.plist` URL schemes
  - [ ] Android SHA-1 fingerprints added (debug, upload, and Play app-signing)
- [ ] 2FA turned on for Supabase, Groq, Apple, Google and GitHub.
- [ ] Spend caps set in Supabase billing and in the Groq console.
- [ ] Inboxes made and monitored: privacy@, support@ and review@ (demo account) at hux.co.in.

## C. Legal & policy (L + M)

- [ ] Lawyer reviews `docs/legal/PRIVACY_POLICY.md` and `TERMS_OF_USE.md`. Fill in every [bracket]: address, grievance officer, dates, liability cap, backup retention.
- [ ] Publish https://hux.co.in/privacy, /terms, /delete-account (`docs/legal/delete-account.html`) and /support.
- [x] Confirm **Groq API data retention** for your organisation (Zero Data Retention ON, Nov 2026). Then finalise the "ephemeral" and "linked" answers in `STORE_FORMS.md` and in `ios/Runner/PrivacyInfo.xcprivacy`.
- [ ] Data-processing terms in place with Supabase and Groq. Write down where each one stores data (overseas transfer).
- [ ] Use the "HUX" name without ® until trade-mark application 6922267 is registered.

## D. Content accuracy (N + M)

- [ ] A nutritionist checks the 33 dishes in `lib/core/food/indian_food_db.dart` (portions, protein, kcal), then removes the "approx." caveat where the values are verified.
- [ ] Check the air & heat thresholds against the official CPCB AQI and IMD heat-wave criteria (`lib/core/environment/`).
- [ ] Re-confirm the helpline numbers in `lib/core/coach/safety.dart` and the coach system prompt: 112, 108, Tele-MANAS 14416 / 1-800-891-4416.
- [ ] Read the Hindi voice cues (`voice_cues.dart`) and test the coach in Telugu, Tamil and Kannada. A native speaker should check them.
- [ ] Decide what to do with Health permissions that barely show in the UI (body temperature). Keep with a justification, or remove from both the manifest and `_readTypes`.

## E. Third-party plans (M)

- [ ] **Open-Meteo:** the free tier is non-commercial only. Buy an API plan before public launch and put the key in `.env` as `OPEN_METEO_API_KEY`.
- [ ] Supabase: Pro plan, for leaked-password protection, daily backups and network restrictions.
- [ ] Your own email sender (SMTP) set up in Supabase Auth (e.g. no-reply@hux.co.in).

## F. Store submission (M + D)

- [ ] Screenshots from a real device with real data (`docs/release/BRANDING.md`), using the captions in `STORE_LISTING.md`.
- [ ] Play Console:
  - [ ] Store listing (`STORE_LISTING.md`)
  - [ ] Data safety, Health apps declaration, content rating, target audience 18+, ads = no (`STORE_FORMS.md`)
  - [ ] App access: the review account and instructions
  - [ ] Internal testing, then closed testing, then production
- [ ] App Store Connect:
  - [ ] App Privacy answers
  - [ ] Age rating
  - [ ] Review notes (`STORE_FORMS.md` §2.2)
  - [ ] Review account
  - [ ] TestFlight internal test
  - [ ] Submit for review
- [ ] Build number bumped for every upload (`pubspec.yaml` `version:`).

## G. After launch (first 2 weeks)

- [ ] Each week, review `coach_reports` and update the coach prompt where needed.
- [ ] Watch Groq usage and AI costs. Lower the limits or move the coach to Haiku if needed (just `supabase secrets set`, no app update).
- [ ] Read store reviews daily. Answer privacy@ within 24 hours.
- [ ] Update the Confluence pages (product plan, architecture) with what shipped in v1.
- [ ] Plan v1.1: crash reporting with consent, Apple Watch/Android Wear data check, HUX ring adapter (eIoT SDK).
