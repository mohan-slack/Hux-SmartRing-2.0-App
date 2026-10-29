# HUX v1 — Store forms (Google Play + App Store)

Answers to paste into Play Console and App Store Connect for **v1** (health-app
data, no HUX ring, AI coach, meal photos, air & heat alerts).

> Re-check this file whenever a feature starts sending new data off the phone.
> Keep it in step with:
> - `lib/core/legal/privacy_notice.dart` (in-app notice)
> - `docs/legal/PRIVACY_POLICY.md`
> - `ios/Runner/PrivacyInfo.xcprivacy`
> - `android/app/src/main/AndroidManifest.xml`

## 0. Facts these answers rest on (verify before submitting)

| Fact | Where it's true in code |
|---|---|
| Health readings never leave the phone, except the short coach summary when the coach is on | `HealthStore` (local SQLite), `CoachContext.toJson` |
| Coach messages and summary go to the `coach-chat` function, then to Groq. HUX doesn't store them. | `supabase/functions/coach-chat` |
| Meal photos go to `analyze-meal`, then to Groq. Not stored. | `supabase/functions/analyze-meal` |
| HUX server stores: email and sign-in (Supabase Auth), a daily coach count (7 days), reported replies (90 days) | migrations `*_coach_usage.sql`, `*_coach_reports.sql` |
| City coordinates go to Open-Meteo. No GPS. | `EnvironmentService` |
| No ads SDK, no analytics, no crash reporting, no tracking | `pubspec.yaml` |
| Everything goes over HTTPS | Supabase, Open-Meteo, Groq |
| In-app account deletion, plus a web deletion page | Privacy & account screen, `docs/legal/delete-account.html` |

**Groq retention:** Zero Data Retention is ON for HUX's Groq organisation
(Global ZDR + Inference APIs ZDR enabled; Batch and Fine-tuning off —
confirmed in console.groq.com → Settings → Data Controls, Nov 2026; keep a
dated screenshot). Groq neither stores nor logs inputs/outputs. The coach and
photo data still passes through HUX's server with the user's sign-in, so it
stays answered as **collected / linked** below (conservative).

---

## 1. Google Play Console

### 1.1 App content → Privacy policy
`https://hux.co.in/privacy`. This must be the same page Health Connect opens
(`HealthPrivacyActivity`).

### 1.2 App content → Data safety

**Overview questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data is deleted? | **Yes**: in-app, and `https://hux.co.in/delete-account` |
| Account creation | **Username/email and password**, plus **OAuth** (Google, Apple) |
| Delete-account URL | `https://hux.co.in/delete-account` |
| Independent security review | No (optional) |

**Data types.** "Collected" means it leaves the device. Sending data to service
providers that process it for HUX (Supabase, Groq, Open-Meteo) is **not**
"sharing" under Play's definition, so **Shared = No for everything**.

| Category → Type | Collected | Shared | Processed ephemerally? | Required or optional | Purposes |
|---|---|---|---|---|---|
| Personal info → **Email address** | Yes | No | No | Required | Account management, App functionality |
| Personal info → **User IDs** | Yes | No | No | Required | Account management, Fraud prevention / security (coach fair-use limit) |
| Health and fitness → **Health info** (sleep, heart rate, HRV-based charge, meal nutrition estimates) | Yes | No | No ¹ | Optional | App functionality, Personalisation |
| Health and fitness → **Fitness info** (steps, step goal, streak, activity) | Yes | No | No ¹ | Optional | App functionality, Personalisation |
| Messages → **Other in-app messages** (coach chat, reported replies) | Yes | No | No | Optional | App functionality |
| Photos and videos → **Photos** (meal photos) | Yes | No | No ¹ | Optional | App functionality |
| Location → **Approximate location** (city picked for air and heat) | Yes | No | Yes | Optional | App functionality |

¹ HUX itself is ephemeral (nothing stored), but the AI provider may keep data
for a limited time, so the safe answer is "No". Switch to "Yes" only if the
Groq terms confirm zero retention.

**Not collected:** precise location, contacts, calendar, files, audio, web
history, installed apps, crash logs, diagnostics, device/advertising IDs,
financial info. Health Connect data that stays on the phone is **not
"collected"**.

### 1.3 App content → Health apps declaration

- **Health features. Select:**
  - Activity and fitness
  - Sleep management
  - Nutrition and weight management (protein and meal logging)
- **Medical features. Select none.** HUX is not a medical device and gives no
  clinical advice.

**Health Connect permissions:** read-only, and exactly the eight in the manifest.
Paste one justification per data type.

| Permission | Justification (paste) |
|---|---|
| `READ_STEPS` | HUX shows the user's daily steps against a personal step goal set from their own last 7 days, keeps their activity streak, and builds their monthly report. Read-only. Data stays on the device. |
| `READ_ACTIVE_CALORIES_BURNED` | Active energy is part of the user's daily "HUX Charge" energy score (energy used through the day) and their activity summary. Read-only, on device. |
| `READ_HEART_RATE` | Resting and current heart rate are compared with the user's own baseline to show how recovered they are each morning ("HUX Charge") and today's suggested effort level. Read-only, on device. |
| `READ_HEART_RATE_VARIABILITY` | HRV against the user's personal baseline is the main recovery signal in the daily HUX Charge and the suggested effort for the day. Read-only, on device. |
| `READ_SLEEP` | Sleep duration and stages power the sleep trends screen, "sleep vs your normal", the target bedtime suggestion, and journal insights (e.g. how late dinners affect the user's own sleep). Read-only, on device. |
| `READ_OXYGEN_SATURATION` | Night-time blood oxygen is shown in the sleep summary and trends as a wellness indicator, compared only with the user's own usual range. Read-only, on device. Not used for diagnosis. |
| `READ_RESPIRATORY_RATE` | Night-time breathing rate is shown in sleep trends and compared with the user's own baseline as part of the recovery readout. Read-only, on device. |
| `READ_BODY_TEMPERATURE` | A night temperature far outside the user's own usual range lowers that morning's recovery readout and shows a gentle "take it easy" note. Read-only, on device. Not used for diagnosis. |

**Add to every justification:** "Health Connect data is never used for
advertising, never sold, and only leaves the device as a short summary
(e.g. 'steps 4,200 of 6,000') when the user turns on the AI coach and asks a
question."

- **Before submitting:** every one of these must be visibly used in a release
  screen.
  - If SpO₂, breathing rate or temperature is not shown anywhere a user can
    see, remove that permission from both `AndroidManifest.xml` and
    `HealthStoreRingAdapter._readTypes`, and don't declare it.
  - Google rejects permissions that aren't visibly used.
- **Privacy policy link from Health Connect** opens `HealthPrivacyActivity`,
  which opens `https://hux.co.in/privacy`.

### 1.4 Other App content items

| Item | Answer |
|---|---|
| Ads | **No ads** |
| Target audience | **18+ only** |
| Content rating (IARC) | See the table below. Expected rating: 3+/Everyone, which is fine. Play's target-audience setting keeps it 18+. |
| News app | No |
| COVID-19 contact tracing | No |
| Government app | No |
| Financial features | None |
| Data safety | As in 1.2 |
| Health apps declaration | As in 1.3 |
| Permissions declarations | None needed: no SMS, call log, background location, exact alarm, all-files access or accessibility |
| Foreground service | None |

**IARC content-rating answers:**

| Question | Answer |
|---|---|
| Violence, sexuality, language, controlled substances, gambling | **No** |
| Users interact with other users | **No** |
| Shares user location with other users | **No** |
| Digital purchases | **No** |
| Unrestricted internet or web browsing | **No** |
| Generative AI | **Yes**: AI coach chat (wellness), with in-app reporting |

### 1.5 Generative AI policy (Play "AI-Generated Content")

- **In-app reporting.** Every coach reply has a ⚑ **Report** button: four
  reasons, stored in the `coach_reports` table. **Done in code.**
- **Unsafe content.**
  - The system prompt blocks diagnosis, medication changes, crash diets and
    unsafe advice.
  - Emergency and self-harm messages show help numbers on the phone itself.
- **Disclaimer.** "AI coach — it can make mistakes. Wellness tips, not medical
  advice" is always visible on the chat screen.
- **Review reports.** Check `coach_reports` weekly (Supabase dashboard) and fix
  the system prompt when needed.

### 1.6 App access (for Google's reviewers)

| Item | What to provide |
|---|---|
| Login | Test account: `review@hux.co.in` / [password]. Make it a real Supabase user. |
| Instructions | "Sign in → agree to the privacy notice (18+) → answer or skip 6 questions → allow Health Connect read access. On a device without health data, HUX shows the 'learning' state; add sample Steps and Sleep in Health Connect to see HUX Charge and trends. AI coach: Explore → HUX coach → Agree. Account deletion: shield icon → Delete account." |
| Demo video | Optional but recommended: a 1–2 minute screen recording with real data, linked in the notes. |

### 1.7 Store listing — health wording rules

| Allowed | Not allowed |
|---|---|
| Wellness and fitness wording: "track your sleep", "personal step goals", "AI wellness coach" | "Diagnose", "detect disease", "treat", "medical-grade", "monitors heart conditions", "lowers blood sugar" |

Always add this line: **"HUX is not a medical device. For medical concerns,
consult a doctor."**

---

## 2. App Store Connect

### 2.1 App Privacy ("nutrition label")

**Tracking:** No (`NSPrivacyTracking` = false). No data is used to track users
across apps or websites.

**Data collected:**

| Data type | Linked to the user? | Used for tracking? | Purpose |
|---|---|---|---|
| Contact Info → **Email Address** | **Linked** | No | App Functionality |
| Identifiers → **User ID** | **Linked** | No | App Functionality |
| Health & Fitness → **Health** (coach summary: sleep, charge; meal nutrition) | **Linked** (sent with your sign-in) | No | App Functionality |
| Health & Fitness → **Fitness** (steps, streak) | **Linked** (sent with your sign-in) | No | App Functionality |
| User Content → **Photos or Videos** (meal photos) | **Linked** (sent with your sign-in) | No | App Functionality |
| User Content → **Other User Content** (coach messages, reported replies) | **Linked** (sent with your sign-in) | No | App Functionality |
| Location → **Coarse Location** (city for air and heat) | Not linked | No | App Functionality |

² The AI provider never receives the user's identity. Reported replies are
stored with a user ID. If you want the strictest reading, mark **Other User
Content = Linked**. Keep `ios/Runner/PrivacyInfo.xcprivacy` matching whatever
you choose here.

**Not collected:** Financial Info, Contacts, Browsing/Search History,
Purchases, Diagnostics, Usage Data, Sensitive Info, Precise Location, Audio,
Other Data.

### 2.2 App Review Information → Notes (paste and edit)

> HUX is a wellness app (not a medical device) for users in India, 18+.
>
> **Sign-in:** demo account review@hux.co.in / [password]. Sign in with Apple
> and Google are also offered.
>
> **HealthKit:** HUX only READS steps, heart rate, HRV, sleep, blood oxygen,
> respiratory rate, body temperature and active energy. It shows them on Today
> (HUX Charge, effort, step goal, target bedtime), Trends, Weekly story, Streaks
> and the Monthly report. It never writes to Health. Health data stays on the
> device and is never used for advertising. With the user's explicit opt-in,
> the AI coach sends a short summary (e.g. "steps 4,200 of 6,000, slept 6h 40m")
> to our server to answer their question; this is shown to the user before they
> agree, and can be turned off in Privacy & account.
>
> **Testing without Health data:** add a few Steps and Sleep samples in the
> Health app, then pull to refresh on Today.
>
> **Account deletion (5.1.1(v)):** shield icon (top-left) → Privacy & account →
> Delete account. It deletes immediately and revokes Sign in with Apple.
>
> **AI coach:** wellness tips only. Emergency and self-harm phrases show India
> emergency numbers (112, Tele-MANAS 14416) on the device. Users can report any
> reply in-app.
>
> **Camera and photos:** only when the user chooses to photograph or pick a meal.
>
> **Bluetooth:** used only to pair a HUX ring (coming in a later version). v1
> does not request Bluetooth.

### 2.3 Guideline checklist

| Guideline | Status |
|---|---|
| 5.1.1(i) Privacy policy link in the app and in App Store Connect | Done in the app; add the URL in App Store Connect |
| 5.1.1(v) In-app account deletion, including Sign in with Apple revocation | Done (`delete-account` + Apple revoke) |
| 5.1.2 No tracking; no data used for ads | Done |
| 5.1.3 Health data not used for ads or data mining, not stored in iCloud (DB in Application Support, excluded from backup), clear disclosure | Done |
| 4.8 Sign in with Apple offered next to Google | Done |
| 1.4.1 No medical claims; accuracy disclaimer | In-app copy done. **Check store screenshots and description.** |
| 2.1 Reviewer can use the app (demo account, notes) | **To do: create the review account** |
| 2.5.1 HealthKit used for visible features; usage strings match | Strings updated in `Info.plist` |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | Added to the Runner target |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` (HTTPS only) |

### 2.4 Age rating (App Store Connect questionnaire)

| Item | Answer |
|---|---|
| Medical or treatment information | **Infrequent/Mild** (wellness tips; no treatment advice) |
| Everything else | None |
| Unrestricted web access | No |
| User-generated content shared with others | No |
| AI chatbot / generated content | **Yes**: answer the AI-related questions honestly (wellness coach, filtered) |

The resulting rating is likely 13+ or 16+ under Apple's newer age tiers. HUX's
own terms are still 18+; that's allowed.

---

## 3. Code changes made for these forms

**Android**
- Removed the `ACTIVITY_RECOGNITION` permission (unused). Health Connect
  permissions are documented as the v1 data source.
- Added `HealthPrivacyActivity`: Health Connect's privacy-policy link now opens
  `https://hux.co.in/privacy`.
- App label changed to "HUX".

**iOS**
- HealthKit, Bluetooth and Health-update usage strings rewritten for review.
  They no longer say "during development".
- Display name changed to "HUX".
- Added `PrivacyInfo.xcprivacy` to the Runner target.
- Added `ITSAppUsesNonExemptEncryption = false`.

**Release default**
- Release builds now use **health-app data** by default (debug keeps the demo).
- The banner says "From your health app".

**Generative AI**
- ⚑ Report on every coach reply.
- New `coach-report` function and `coach_reports` table with 90-day retention.
- Privacy notice and policy updated to match.

## 4. Still to do (owner: Mohan)

1. Publish the privacy, terms and delete-account pages. Create
   `privacy@hux.co.in` and the review account.
2. Confirm Groq's API retention, then finalise the "ephemeral" and
   "linked" answers above.
3. Run `supabase db push`, deploy `coach-report`, and schedule the 90-day purge
   cron.
4. Check that every declared Health Connect / HealthKit type is visible on a
   screen. Drop any that aren't.
5. Make the store screenshots and description free of medical claims.
