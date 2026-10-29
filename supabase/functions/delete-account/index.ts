// HUX — delete-account (Supabase Edge Function, Deno)
// --------------------------------------------------
// Permanently deletes the CALLER's account. Required by Apple guideline
// 5.1.1(v), Google Play's account-deletion policy, and DPDP erasure.
//
// What is deleted:
// - The Supabase auth user (email, sign-in identities, sessions).
// - Rows linked to it via ON DELETE CASCADE (e.g. coach_usage).
//   Any NEW table holding user data must also cascade from auth.users.
// - Health data is not on HUX's servers in v1 (it lives on the phone,
//   which the app wipes after this succeeds).
// - Sign in with Apple: if the app sends a fresh authorization code and
//   the APPLE_* secrets are set, the user's Apple token is revoked
//   (Apple's requirement for apps using Sign in with Apple).
//
// Setup:
//   supabase secrets set APPLE_TEAM_ID=... APPLE_KEY_ID=... APPLE_BUNDLE_ID=...
//   supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
//   supabase functions deploy delete-account
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided
// to edge functions automatically.

import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { callerId, json, projectUrl, serviceHeaders } from "../_shared/auth.ts";

/** Best-effort Apple token revocation. Never blocks deletion. */
async function revokeApple(code: string): Promise<boolean> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const clientId = Deno.env.get("APPLE_BUNDLE_ID");
  const pem = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !pem) return false;
  try {
    // Accept the .p8 pasted either with real line breaks or as one line with \n.
    const key = await importPKCS8(pem.replace(/\\n/g, "\n").trim(), "ES256");
    const now = Math.floor(Date.now() / 1000);
    const clientSecret = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyId })
      .setIssuer(teamId)
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .setAudience("https://appleid.apple.com")
      .setSubject(clientId)
      .sign(key);

    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
      }),
    });
    if (!tokenRes.ok) return false;
    const tokens = await tokenRes.json();
    const token = tokens.refresh_token ?? tokens.access_token;
    if (!token) return false;

    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        token,
        token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    return revokeRes.ok;
  } catch (e) {
    console.error("apple revoke failed:", (e as Error).message);
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let uid: string | null;
  try {
    uid = await callerId(req);
  } catch {
    return json({ error: "server not configured" }, 500);
  }
  if (!uid) return json({ error: "unauthorized" }, 401);

  let body: { appleAuthorizationCode?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // Empty body is fine.
  }

  const appleRevoked =
    typeof body.appleAuthorizationCode === "string" && body.appleAuthorizationCode.length < 2000
      ? await revokeApple(body.appleAuthorizationCode)
      : false;

  // Deleting the auth user cascades to every table that references it.
  const res = await fetch(`${projectUrl()}/auth/v1/admin/users/${uid}`, {
    method: "DELETE",
    headers: serviceHeaders(),
  });
  if (!res.ok && res.status !== 404) {
    console.error("delete user failed:", res.status);
    return json({ error: "delete failed" }, 502);
  }

  // Log only the fact, never the user's email.
  console.log("account deleted", { appleRevoked });
  return json({ deleted: true, appleRevoked });
});
