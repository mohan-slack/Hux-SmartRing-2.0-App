# HUX Privacy Policy

> **DRAFT — needs review by a qualified Indian lawyer before publishing.**
> Publish at https://hux.co.in/privacy. Keep it in step with
> `lib/core/legal/privacy_notice.dart` (the in-app notice). When the meaning
> changes, bump `PrivacyNotice.noticeVersion` so users agree again.

**Last updated:** 29-10-2026

**Who we are:** HUX is an app by **Viveon Gizit Private Limited** ("HUX", "we"),
[REGISTERED ADDRESS], India. Contact: **support@hux.co.in**.

HUX is a wellness app. It is **not a medical device** and does not diagnose,
treat or prevent any disease.

## 1. Summary

- Your health readings stay **on your phone**. HUX's servers do not store them.
- Optional features (AI coach, meal-photo analysis, air & heat alerts) send only
  what they need, and only after you turn them on.
- No ads. We never sell your data, and we never use health data for advertising
  or for credit, insurance or employment decisions.
- You can download your data, turn features off, or delete your account inside the app.

## 2. What we use, why, and where it goes

| Data | Why | Where it goes | Required? |
|---|---|---|---|
| Email address and sign-in details (email/password, Google or Apple sign-in) | Create and secure your account | HUX account service, hosted on Supabase | Yes |
| Health readings you allow: steps, heart rate, heart-rate variability, sleep and sleep stages, blood oxygen, active calories, breathing rate | HUX Charge, sleep, trends, streaks, plans | Read from Apple Health (HealthKit) or Android Health Connect; stored **only on your phone** | Yes, for the core features |
| Your onboarding answers, journal tags, meals, plan progress, settings | Personalise the app | **Only on your phone** | No |
| AI coach: your messages plus a short summary (goals, diet, HUX Charge, steps vs goal, sleep duration, streak, protein, time of day) | Answer your questions | Sent to HUX's server and to our AI provider (Groq) to write a reply. **Not stored by HUX.** Your chat history stays on your phone. | No — only after you agree in the coach |
| Meal photos you choose to analyse, plus an optional description | Estimate calories and protein | Location and other hidden photo details (EXIF) are removed on your phone first. Sent to HUX's server and to our AI provider (Groq Inc., USA). **Not stored by HUX.** | No — only after you agree |
| The city you pick (not GPS) | Air-quality and heat alerts | Its coordinates go to Open-Meteo (weather service) | No |
| A daily count of coach messages, linked to your account ID | Fair-use limit | HUX server; deleted after 7 days | Only if you use the coach |
| A coach reply you report, the question before it, and the reason | Review and improve the coach | HUX server, linked to your account ID; deleted after 90 days | Only if you report a reply |

We do **not** collect GPS location, contacts, microphone audio, or advertising IDs.

Health readings, meals and your journal are stored **on your phone only**, in app storage that is excluded from iCloud and Google backups.

## 3. Apple Health and Health Connect

HUX only reads the data types you allow, and you can change this at any time
in Apple Health or Health Connect settings. Data from Apple Health and Health
Connect is used **only** to provide HUX's features to you. It is never used for
advertising, never sold, and never shared with third parties except as described
in section 2 for features you turn on. HUX's use of data received from Health
Connect follows the Health Connect Permissions policy, including its Limited Use
requirements.

## 4. Service providers (processors)

| Provider | What for | Data |
|---|---|---|
| Supabase | Account sign-in and HUX's server functions | Email, sign-in identifiers, coach message count, reported replies |
| Groq | AI coach replies and meal-photo estimates | Coach messages and summary; meal photos |
| Open-Meteo | Weather and air quality | City coordinates |
| Google / Apple | Sign in with Google / Apple (if you choose it) | As set by your Google/Apple account |

[CONFIRM WITH LAWYER: data-processing terms, where each provider stores and
processes data (cross-border transfer), and each provider's retention period.]

## 5. How long we keep data

- **On your phone:** until you delete it in the app or uninstall HUX.
- **Your account:** until you delete it. Deletion is immediate. Backups held by
  our hosting provider expire within [X] days.
- **Coach message counts:** 7 days.
- **Reported coach replies:** 90 days.
- **Coach messages and meal photos:** HUX does not store them. Our AI provider,
  Groq Inc. (USA), processes them only to produce the reply and does not keep
  them: we have turned on Groq's Zero Data Retention setting for HUX, so
  inputs and outputs are not stored or logged by Groq.

## 6. Your rights (DPDP Act 2023)

You can:

- **Get a copy** of your data: Privacy & account → *Download my data*.
- **Correct** your answers and settings in the app at any time.
- **Withdraw consent:** turn off the coach, meal photos or alerts. Turning off the
  coach also deletes your chat. Withdrawing consent stops future processing but
  does not affect processing already done.
- **Erase:** Privacy & account → *Delete data on this phone* or *Delete account*.
  You can also request deletion at https://hux.co.in/delete-account.
- **Nominate** someone to exercise these rights if you die or become unable to.
  Email us.
- **Complain:** email **support@hux.co.in**. We reply within [X] days. If we don't
  resolve it, you may complain to the **Data Protection Board of India**.

## 7. Age

HUX is for people aged **18 and over**. We do not knowingly process children's
data. If you think a child has used HUX, email us and we will delete the data.

## 8. Security

- Connections to our servers use encryption (HTTPS).
- API keys for AI services are kept on our server, never in the app.
- Each account can only reach its own server data.
- Data on your phone is protected by your phone's own lock and encryption.

If a personal data breach affects you, we will tell you and the Data Protection
Board as the law requires.

## 9. Changes

If we change how we use your data, we will update this page and ask you to agree
again in the app.

## 10. Contact and grievance officer

Mohan Reddy, Grievance Officer, Viveon Gizit Private Limited — **support@hux.co.in**,
Electronic City, Bengaluru, Karnataka 560100.
