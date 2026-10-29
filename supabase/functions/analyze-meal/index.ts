// HUX — analyze-meal (Supabase Edge Function, Deno)
// -------------------------------------------------
// Receives a meal photo (+ optional dish name) from a SIGNED-IN app user,
// asks a vision AI to list dishes and portions in Indian household units,
// and returns strict JSON the app understands (see
// lib/core/food/meal_analyzer.dart -> MealAnalysisParser).
//
// Security:
// - The AI API key lives ONLY here, as a Supabase secret. Never in the app.
// - Supabase verifies the caller's JWT before this runs (default
//   verify_jwt = true), AND the function checks the user itself
//   (_shared/auth.ts), so only signed-in HUX users can call it.
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

import { callerId, json, withinDailyLimit } from "../_shared/auth.ts";

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

  try {
    const uid = await callerId(req);
    if (!uid) return json({ error: "unauthorized" }, 401);
    const limit = Number(Deno.env.get("MEAL_DAILY_LIMIT") ?? "20");
    if (!(await withinDailyLimit(uid, "meal", limit))) return json({ error: "daily_limit" });

    const reply = await callModel(image, mediaType, description || undefined);
    const parsed = extractJson(reply);
    if (!parsed || typeof parsed !== "object") {
      return json({ items: [], questions: [], note: "Could not read this photo" });
    }
    return json(parsed);
  } catch (e) {
    // Never leak provider details or keys to the client.
    console.error("analyze-meal failed:", (e as Error).message);
    return json({ error: "analysis unavailable" }, 502);
  }
});
