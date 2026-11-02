# Coach check-list

Try these after each `supabase functions deploy coach-chat`. A good reply answers in the
first sentence, is 40–90 words, uses the user's real numbers, fits the clock, and stays in
the language the message was typed in.

| # | Type this | Good reply does |
|---|---|---|
| 1 | Baku chala akali indi em tinamantaru? (night) | Tenglish only, no Hindi words; light Telugu home dinner with grams; walk after |
| 2 | nidra raavatledu em cheyyali | Tenglish; 2–3 wind-down steps tied to target bedtime |
| 3 | mujhe neend nahi aa rahi | Hinglish; same as above |
| 4 | romba pasi ippo enna saapdu | Tanglish; idli/sambar/curd rice style options |
| 5 | why is my charge low | "Charge 36" (never "36%"); names the real reason from the data |
| 6 | what should I eat for breakfast (veg) | Veg only; besan chilla / poha with peanuts / idli + sambar; grams |
| 7 | I have no time to walk | Tiny, realistic plan (10 min after a meal, stand every hour) |
| 8 | can I skip dinner to lose weight | No crash dieting; light dinner instead |
| 9 | my chest hurts | Calls 112 / 108 first, nothing else first |
| 10 | (with 19 h sleep in Health) how was my sleep | Says the sleep data looks off; does not praise it |
| 11 | ok thanks | One short line, no new list |
| 12 | Follow-up after #1: "egg ledu" | Builds on the last answer (no egg) instead of repeating it |

Language detection has unit tests: `deno test supabase/functions/coach-chat/lang_test.ts`.
