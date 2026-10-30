# HUX roadmap (after v1 launch)

Ideas agreed but NOT in v1. Keep this list short and ordered.

## v1.1 — Private / offline coach
- `CoachEngine` interface: cloud (Groq) default, on-device fallback.
- On-device: Apple Foundation Models (iOS, Apple Intelligence phones),
  Gemini Nano via Android AICore (supported phones); everyone else gets
  rule-based tips. "Private mode" toggle = never leaves the phone.
- Later: optional downloadable small model (Gemma 3 1B / Qwen ~1.5B,
  ~0.5–1 GB) and a small on-device Indian food photo classifier.
- Check device + Indian-language support before building.

## v1.2 — Journeys (guided programs)
One opt-in program at a time. Start lean: **2 programs only** —
"Sleep Reset 21" and "Fit in 30" (home, no equipment).

### What a day has
- Sleep: fixed wake time; bedtime = wake − sleep need − 15 min wind-down;
  shift 15 min / 3 days (reuses DayPlanner).
- Food: 2 options per meal (diet + budget ₹/₹₹/₹₹₹), protein/kcal/carbs/fat,
  day totals meet the goal; "Swap" (reuses food table, ProteinGap, weight goal).
- Workout: warm-up → main → cool-down, 10–20 min, progressive, one
  challenge day a week (reuses session player + voice cues).
- Reminders: user picks (wake / move / wind-down); max 3/day; quiet hours.

### New work needed
- [ ] Exercise library: ~20 moves (not 40) — own/licensed illustrations,
      2–3 form cues, easier/harder version, stop-if note each.
- [ ] Program plans: 21 + 30 day schedules as data (JSON), not code.
- [ ] Meal library: ~30 meals (veg/egg/non-veg × budget), from the
      reviewed food table; regional price RANGES, not exact ₹.
- [ ] Journey engine: day index, pause/skip, rest pass, completion.
- [ ] Screens: picker, setup, today's day, move detail, finish.
- [ ] Reminder presets + one Home card.
- [ ] Reviews: nutritionist (meals, food table), physiotherapist (moves).

### UX (keep it quiet)
1. Discover: Plans tab → "Journeys" row. Home suggests ONE journey only
   after 3 days of use (never on day 1).
2. Start in 4 taps: pick → 3 questions (wake time, diet + budget, level)
   → reminders (default: wake + wind-down only) → Start.
3. Daily: Home card "Day 5 of 21 · Bed by 10:45 · [Start 12-min workout]".
   Tap → Today = 3 checklist items (sleep, food, move), each ≤ 1 screen.
   Tick = done, streak updates.
4. Off days: "Not today" uses a rest pass, no guilt. 2 missed days →
   offer "Continue from day X", never "you failed".
5. Finish: shareable summary card + "Next journey?" — never auto-start.
6. Always: pause/stop in one tap; reminders off from the journey screen.

### Pre-mortem (why it could fail → prevention)
| Risk | Prevent |
|---|---|
| Too much daily → drop-off by day 4 | 3 items max/day; workouts 10–20 min; food = suggestions, logging optional |
| Notification fatigue → uninstall | 2 reminders by default, max 3; auto-quiet after 2 ignored days |
| Injury / unsafe moves | physio review; readiness questions; easier option for every move; stop-if notes; always warm-up first |
| Wrong or unaffordable food advice | nutritionist review; price ranges; respects diet/Jain/fasting; no supplements or crash diets |
| Medical-claim rejection (App Store 1.4.1) | "wellness program" wording; no weight-loss promises, no disease terms |
| Too much content to maintain | 2 programs, 20 moves, 30 meals, all data files; add more only from usage data |
| Clash with fasting / night shift | journey follows active fasting (no daytime meals) and night shift (wake shifts) |
| Bedtime target unrealistic | max 15-min shifts; wake time editable any day |
| Feels generic | uses own data: Charge picks easy/normal day; step goal; protein goal |
| Phone-only users (no sleep data) | sleep item becomes a self-check ("in bed by 10:45?") |

## v1.3 — Cycle (cycle-aware HUX)

**Status: built (Oct 2026), unreviewed.** Code: `lib/core/cycle/`, `lib/screens/cycle/`,
`test/cycle_test.dart`. Not yet: write-back to Health, gynaecologist review.

Idea: not a separate pink tracker. The cycle phase quietly explains the rest of the app.
Scores, Journeys, food and coach all know the phase, so a luteal-week dip reads as
"your body is working harder", not "you failed".

### What it does
- Opt-in only (onboarding question + Me → Cycle). Never assumed from gender.
- Imports past periods from Apple Health / Health Connect (read-only; spotting
  ignored), so predictions work from day one. Write-back to Health: later.
- Log in 2 taps: "Period started / ended" button shows only near the predicted window;
  flow + up to 5 symptom chips (cramps, mood, bloating, headache, cravings, energy).
- Prediction as a range with confidence ("likely 12–15 Nov"), improving with each cycle.
  Irregular mode widens ranges instead of guessing a single day.
- Home: one quiet chip on the scores card — "Day 18 · Luteal". Tap for phase card.
- Charge/readiness: compares against the user's own same-phase baseline
  (RHR up, HRV down in luteal is expected), with a one-line explanation.
- Journeys: lighter-move option in late luteal/period days; food swaps
  (iron: ragi, rajma, chana + jaggery, greens; magnesium: seeds, nuts, dark leafy).
- Coach: gets phase only if the user turns "Use cycle in coach" on (off by default).
- Gentle pattern notes (cycle > 35 or < 21 days 3 times, very long bleeding):
  "worth mentioning to a doctor". Information, never diagnosis.
- Life modes: Regular · Irregular/PCOS · On hormonal birth control (log bleeding only,
  no phases) · Pregnant (pause predictions) · Perimenopause.

### Privacy (most important)
- Stays on the phone. Not synced to Supabase, never in share cards, analytics or AI
  by default. One-tap "Delete all cycle data".
- Optional app lock for the Cycle screen.
- Discreet notifications: "Heads-up from HUX" — never the word period on the lock screen.
- Not for contraception or fertility planning (no medical-device claims).

### New work needed
- Health types: MENSTRUATION_FLOW (+ spotting/BBT/ovulation where supported), read + write.
- `CycleStore` (local table) + `CyclePredictor` (weighted average of last 6 cycles, range).
- Phase-aware baseline in `baseline.dart` / meaning engine.
- Cycle screen, log sheet, Home chip, settings (modes, lock, delete, coach toggle).
- Journey hooks (move swap, food swap). Discreet reminder id 1401.
- Privacy policy + store labels: "reproductive health" data type, local-only.
- Review by a gynaecologist before launch.

### Pre-mortem (why it could fail → prevention)
| Risk | Prevention |
|---|---|
| Fear of data leak | Local-only, app lock, no AI by default, clear one-line promise |
| Wrong prediction breaks trust | Range + confidence, never a single "day 1" |
| Irregular / PCOS users feel broken | Irregular mode, no red warnings, kind wording |
| Feels clinical or pink-cute | Same HUX design, plain words, no gamified streaks |
| Logging fatigue | 2-tap log, button only shown near window, Health import |
| Lock-screen embarrassment | Discreet wording, user picks reminder or none |
| Store rejection | Health labels, no contraception claims, policy updated |
| Men see it / irrelevant | Opt-in; hidden completely when off |
