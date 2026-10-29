// HUX — analyze-meal (Supabase Edge Function, Deno)
// -------------------------------------------------
// Receives a meal photo (+ optional dish name) from a SIGNED-IN app user,
// asks a vision AI to list dishes and portions in Indian household units,
// and returns strict JSON the app understands (see
// lib/core/food/meal_analyzer.dart -> MealAnalysisParser).
//
// Security:
// - The AI API key lives ONLY here, as a Supabase secret. Never in the app.
// - verify_jwt is OFF (config.toml); the function validates the caller
//   with Supabase Auth FIRST (_shared/auth.ts), before reading the photo.
// - Per-user AND global daily limits, AI_PAUSED kill switch, refunds on
//   failure, 25 s provider timeout, and the model's JSON is re-built from
//   known fields only before it reaches the app.
// - Fair use: MEAL_DAILY_LIMIT photos per user per day (default 20),
//   counted in ai_usage (no photo or result is stored).
// - The photo is forwarded to the AI provider and NOT stored by HUX.
//
// Setup:
//   supabase secrets set AI_PROVIDER=groq GROQ_API_KEY=gsk_...   (or anthropic + ANTHROPIC_API_KEY)
//   supabase secrets set MEAL_MODEL=<a VISION model id>           # check provider docs
//   supabase functions deploy analyze-meal
//
// Provider is swappable via the AI_PROVIDER secret (see _shared/llm.ts).

import {
  aiPaused,
  callerId,
  json,
  refundUsage,
  tooLarge,
  withinDailyLimit,
  withinGlobalLimit,
} from "../_shared/auth.ts";

import { chat } from "../_shared/llm.ts";

const MAX_IMAGE_BASE64 = 2_200_000; // ~1.6 MB image
const MAX_DESCRIPTION = 200;

const UNITS = ["katori", "piece", "roti", "glass", "cup", "plate", "spoon", "handful", "grams"];

const SYSTEM_PROMPT = `You identify food in a meal photo for HUX, an Indian health app.
Users are mostly in India: expect home-style and regional Indian food from every state
(North, South, East, West, North-East), plus street food, sweets, and common global dishes.

Return ONLY a JSON object, no prose, in exactly this shape:
{
  "items": [
    {
      "name": "dish name in common Indian English, e.g. 'dal tadka', 'aloo paratha', 'sambar'",
      "portion": { "qty": number, "unit": one of ${JSON.stringify(UNITS)} },
      "confidence": number 0-1,
      "estimate": { "kcal": number, "protein": number, "carbs": number, "fat": number, "fiber": number }
    }
  ],
  "questions": [
    { "itemIndex": number, "kind": "quantity" | "identity", "text": "short question", "options": ["2-5 short tap answers"] }
  ],
  "note": "one short optional caveat, or empty string"
}

Rules:
- One item per distinct dish (rice, dal, sabzi, roti, curd, pickle, salad are separate items).
- Portions in Indian household units: a katori is a ~150 ml bowl; count rotis/idlis/dosas/pieces.
- "estimate" is for the WHOLE portion (qty x unit), typical home-style cooking.
- Ask at most 2 questions, ONLY where it changes protein or calories a lot and you are unsure
  (e.g. paneer vs tofu, how many rotis, chicken vs soya). Options must be tap-able, e.g. ["1","2","3","4"].
  Never ask about things you can see clearly.
- If the user gave a description, trust it for dish names and quantities.
- If there is no food in the photo, return {"items": [], "questions": [], "note": "No food found"}.
- Wellness only: never comment on diseases or diagnoses.`;

async function callModel(imageBase64: string, mediaType: string, description?: string): Promise<string> {
  const userText = description
    ? `The user says this is: "${description}". Identify the items and portions. Reply with the JSON object only.`
    : "Identify the items and portions. Reply with the JSON object only.";
  return chat({
    model: Deno.env.get("MEAL_MODEL") ?? "",
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userText }],
    image: { base64: imageBase64, mediaType },
    maxTokens: 1500,
    temperature: 0.2,
  });
}

function str(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

function n(v: unknown, min: number, max: number): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : undefined;
}

/**
 * Keeps ONLY the fields the app reads, with sane ranges. Text inside a
 * photo ("ignore your rules…") can change what the model writes, but it
 * can never add fields or ship oversized strings to the app.
 */
function sanitize(raw: unknown): Record<string, unknown> {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const items = (Array.isArray(r.items) ? r.items : []).slice(0, 12).map((it) => {
    const i = (it && typeof it === "object" ? it : {}) as Record<string, unknown>;
    const p = (i.portion && typeof i.portion === "object" ? i.portion : {}) as Record<string, unknown>;
    const e = (i.estimate && typeof i.estimate === "object" ? i.estimate : {}) as Record<string, unknown>;
    return {
      name: str(i.name, 60),
      portion: { qty: n(p.qty, 0, 50) ?? 1, unit: UNITS.includes(String(p.unit)) ? p.unit : "piece" },
      confidence: n(i.confidence, 0, 1) ?? 0.5,
      estimate: {
        kcal: n(e.kcal, 0, 5000) ?? 0,
        protein: n(e.protein, 0, 300) ?? 0,
        carbs: n(e.carbs, 0, 800) ?? 0,
        fat: n(e.fat, 0, 400) ?? 0,
        fiber: n(e.fiber, 0, 200) ?? 0,
      },
    };
  }).filter((i) => i.name.length > 0);
  const questions = (Array.isArray(r.questions) ? r.questions : []).slice(0, 2).map((q) => {
    const o = (q && typeof q === "object" ? q : {}) as Record<string, unknown>;
    return {
      itemIndex: n(o.itemIndex, 0, 11) ?? 0,
      kind: o.kind === "identity" ? "identity" : "quantity",
      text: str(o.text, 120),
      options: (Array.isArray(o.options) ? o.options : []).slice(0, 5).map((x) => str(x, 30)).filter((x) => x),
    };
  }).filter((q) => q.text && q.options.length >= 2 && q.itemIndex < items.length);
  return { items, questions, note: str(r.note, 160) };
}

/** Pull the first {...} JSON object out of the model's reply. */
function extractJson(text: string): unknown {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (tooLarge(req, MAX_IMAGE_BASE64 + 10_000)) return json({ error: "image too large" }, 413);

  // Who is calling — BEFORE parsing a ~2 MB body.
  let uid: string | null;
  try {
    uid = await callerId(req);
  } catch {
    return json({ error: "analysis unavailable" }, 502);
  }
  if (!uid) return json({ error: "unauthorized" }, 401);
  if (aiPaused()) return json({ error: "paused" }, 503);

  let body: { image?: unknown; mediaType?: unknown; description?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }

  const image = typeof body.image === "string" ? body.image : "";
  const mediaType = body.mediaType === "image/png" ? "image/png" : "image/jpeg";
  const description =
    typeof body.description === "string" ? body.description.slice(0, MAX_DESCRIPTION).trim() : undefined;

  if (!image) return json({ error: "no image" }, 400);
  if (image.length > MAX_IMAGE_BASE64) return json({ error: "image too large" }, 413);

  let counted = false;
  try {
    const limit = Number(Deno.env.get("MEAL_DAILY_LIMIT") ?? "20");
    if (!(await withinDailyLimit(uid, "meal", limit))) return json({ error: "daily_limit" });
    counted = true;
    if (!(await withinGlobalLimit("meal", 2000))) {
      await refundUsage(uid, "meal");
      return json({ error: "busy" }, 503);
    }

    const reply = await callModel(image, mediaType, description || undefined);
    const parsed = extractJson(reply);
    if (!parsed || typeof parsed !== "object") {
      await refundUsage(uid, "meal");
      return json({ items: [], questions: [], note: "Could not read this photo" });
    }
    return json(sanitize(parsed));
  } catch (e) {
    if (counted) await refundUsage(uid, "meal");
    // Never leak provider details or keys to the client.
    console.error("analyze-meal failed:", (e as Error).message);
    return json({ error: "analysis unavailable" }, 502);
  }
});
