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
One opt-in program at a time (e.g. "Sleep Reset 21", "Fit in 30",
"Protein on a Budget 14"), combining:
- Sleep: fixed wake time → bedtime = wake − sleep need − 15 min wind-down;
  shift 15 min every 3 days toward the target (reuses DayPlanner bedtime).
- Food: daily meal ideas from the Indian food table, filtered by diet and
  budget tier (₹ / ₹₹ / ₹₹₹), per-meal protein/kcal/carbs/fat, totals hit
  the user's goal (reuses FoodItem nutrients, ProteinGap, weight goal).
- Workouts: warm-up → main → cool-down, progressive days, each move with
  illustration/animation, form cues, easier/harder version, safety notes
  (reuses session player + voice cues).
- Reminders: user picks which (wake, move, meal, wind-down) and a quiet
  style (max 3/day, never in quiet hours) — reuses NudgeService.
- Home: ONE "Day 5 of 21" card; nothing else changes; pause any time.
- Needs before shipping: nutritionist review (meal plans, food table),
  physiotherapist review (moves, cues), own/licensed exercise visuals,
  regional price ranges for budget tiers.
