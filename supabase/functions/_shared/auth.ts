// Shared helpers for HUX edge functions: caller identity, server keys,
// JSON responses and per-user daily AI limits. One place, so every
// function checks the caller the same way.

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** Rejects oversized bodies BEFORE they are read or parsed. */
export function tooLarge(req: Request, maxBytes: number): boolean {
  const len = Number(req.headers.get("content-length") ?? "0");
  return Number.isFinite(len) && len > maxBytes;
}

/**
 * Error codes (config / usage_N / model_N) are only returned when the
 * DEBUG_ERROR_CODES secret is "true" — never in production.
 */
export function debugCodes(): boolean {
  return Deno.env.get("DEBUG_ERROR_CODES") === "true";
}

/** AI_PAUSED=true turns every AI feature off at once (cost/abuse kill switch). */
export function aiPaused(): boolean {
  return Deno.env.get("AI_PAUSED") === "true";
}

function env(name: string): string | undefined {
  const v = Deno.env.get(name);
  return v && v.length > 0 ? v : undefined;
}

export function projectUrl(): string {
  const url = env("SUPABASE_URL");
  if (!url) throw new Error("server not configured");
  return url;
}

/** Publishable/anon key (legacy name first, then HUX_ fallback for new-key-only projects). */
export function publishableKey(): string {
  const k = env("SUPABASE_ANON_KEY") ?? env("HUX_PUBLISHABLE_KEY");
  if (!k) throw new Error("server not configured");
  return k;
}

/** Secret/service-role key — server only, bypasses RLS. Never return it. */
export function secretKey(): string {
  const k = env("SUPABASE_SERVICE_ROLE_KEY") ?? env("HUX_SECRET_KEY");
  if (!k) throw new Error("server not configured");
  return k;
}

/** Headers for server-side REST/Admin calls with the secret key. */
export function serviceHeaders(extra: Record<string, string> = {}): Record<string, string> {
  const k = secretKey();
  return { apikey: k, Authorization: `Bearer ${k}`, ...extra };
}

/**
 * The signed-in caller's user id, or null. Asks Supabase Auth to validate
 * the user's access token, so it works with legacy AND new (asymmetric)
 * JWT signing keys, and even if verify_jwt is turned off for a function.
 */
export async function callerId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) return null;
  const res = await fetch(`${projectUrl()}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: publishableKey() },
    signal: AbortSignal.timeout(8_000),
  });
  if (!res.ok) return null;
  const user = await res.json();
  return typeof user?.id === "string" ? user.id : null;
}

/**
 * Counts one AI call of [kind] for today (IST) and returns true while the
 * user is within [limit]. Backed by public.bump_ai_usage (service role only).
 */
export async function withinDailyLimit(uid: string, kind: string, limit: number): Promise<boolean> {
  return await rpcBool("bump_ai_usage", { p_user: uid, p_kind: kind, p_limit: limit });
}

/**
 * Counts one call against the GLOBAL daily ceiling for [kind] (all users
 * together; secret GLOBAL_<KIND>_DAILY_LIMIT, default [fallback]).
 */
export async function withinGlobalLimit(kind: string, fallback: number): Promise<boolean> {
  const limit = Number(Deno.env.get(`GLOBAL_${kind.toUpperCase()}_DAILY_LIMIT`) ?? String(fallback));
  return await rpcBool("bump_ai_global", { p_kind: kind, p_limit: limit });
}

/** Gives back one counted call (user + global) after an AI failure. Best effort. */
export async function refundUsage(uid: string, kind: string): Promise<void> {
  try {
    await fetch(`${projectUrl()}/rest/v1/rpc/refund_ai_usage`, {
      method: "POST",
      headers: serviceHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ p_user: uid, p_kind: kind }),
      signal: AbortSignal.timeout(5_000),
    });
  } catch {
    // Never fail the request over a refund.
  }
}

async function rpcBool(fn: string, args: Record<string, unknown>): Promise<boolean> {
  const res = await fetch(`${projectUrl()}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: serviceHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(8_000),
  });
  if (!res.ok) throw new Error(`usage error ${res.status}`);
  return (await res.json()) === true;
}
