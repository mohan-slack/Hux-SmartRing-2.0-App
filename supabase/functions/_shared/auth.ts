// Shared helpers for HUX edge functions: caller identity, server keys,
// JSON responses and per-user daily AI limits. One place, so every
// function checks the caller the same way.

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
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
  const res = await fetch(`${projectUrl()}/rest/v1/rpc/bump_ai_usage`, {
    method: "POST",
    headers: serviceHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify({ p_user: uid, p_kind: kind, p_limit: limit }),
  });
  if (!res.ok) throw new Error(`usage error ${res.status}`);
  return (await res.json()) === true;
}
