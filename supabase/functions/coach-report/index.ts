// HUX — coach-report (Supabase Edge Function, Deno)
// ------------------------------------------------
// Stores a user's report of an AI coach reply, so HUX can review it and
// improve the coach. Required by Google Play's AI-Generated Content
// policy (users must be able to flag offensive/harmful AI output in-app).
//
// Stored: reason, the reply, the question before it, the user's id.
// NOT stored: the health summary. Rows cascade-delete with the account
// and should be purged after 90 days (see the migration).
//
//   supabase functions deploy coach-report

import { callerId, json, projectUrl, serviceHeaders, tooLarge, withinDailyLimit } from "../_shared/auth.ts";

const MAX_TEXT = 2000;
/** Reports per user per day (secret REPORT_DAILY_LIMIT) — stops flooding. */
const DEFAULT_REPORT_LIMIT = 10;
const REASONS = ["harmful", "wrong", "offensive", "other"];

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (tooLarge(req, 16_000)) return json({ error: "too large" }, 413);
  let uid: string | null;
  try {
    uid = await callerId(req);
  } catch {
    return json({ error: "server not configured" }, 500);
  }
  if (!uid) return json({ error: "unauthorized" }, 401);

  let body: { reason?: unknown; reply?: unknown; question?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const reason = typeof body.reason === "string" && REASONS.includes(body.reason) ? body.reason : null;
  const reply = typeof body.reply === "string" ? body.reply.slice(0, MAX_TEXT) : "";
  const question = typeof body.question === "string" ? body.question.slice(0, MAX_TEXT) : null;
  if (!reason || !reply) return json({ error: "bad request" }, 400);

  try {
    const limit = Number(Deno.env.get("REPORT_DAILY_LIMIT") ?? String(DEFAULT_REPORT_LIMIT));
    if (!(await withinDailyLimit(uid, "report", limit))) return json({ error: "daily_limit" });
  } catch {
    return json({ error: "report failed" }, 502);
  }

  const res = await fetch(`${projectUrl()}/rest/v1/coach_reports`, {
    method: "POST",
    headers: serviceHeaders({ "Content-Type": "application/json", Prefer: "return=minimal" }),
    body: JSON.stringify({ user_id: uid, reason, reply, question }),
  });
  if (!res.ok) {
    console.error("coach-report insert failed:", res.status);
    return json({ error: "report failed" }, 502);
  }
  return json({ ok: true });
});
