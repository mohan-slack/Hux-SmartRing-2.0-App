/**
 * air-heat: today/tomorrow hourly weather + air quality for a city, via
 * Open-Meteo, from the SERVER.
 *
 * Why a backend hop:
 * - Open-Meteo's free API is for non-commercial use only. A paid HUX
 *   needs their commercial plan, and that API key must never ship inside
 *   the app (anyone can pull it out of an APK). It lives here as the
 *   secret OPEN_METEO_API_KEY.
 * - One cached answer per city per hour serves every user in that city,
 *   so the paid plan's call count stays tiny.
 *
 * Request:  POST { "lat": 12.97, "lon": 77.59 }   (signed-in users only)
 * Response: { "weather": <forecast JSON>, "air": <air-quality JSON>, "cached": bool }
 *
 * Without OPEN_METEO_API_KEY it uses the free endpoints (development only).
 */
import { callerId, json, withinDailyLimit } from "../_shared/auth.ts";

const CACHE_MS = 60 * 60 * 1000; // forecasts update hourly
const DAILY_LIMIT = 60; // per user: plenty for a screen opened often
const cache = new Map<string, { at: number; body: unknown }>();

// India plus a margin: this service is for HUX's Indian city list.
function inIndia(lat: number, lon: number): boolean {
  return lat >= 5 && lat <= 38 && lon >= 67 && lon <= 99;
}

async function getJson(url: URL): Promise<unknown> {
  const res = await fetch(url, { signal: AbortSignal.timeout(12_000) });
  if (!res.ok) throw new Error(`open-meteo ${res.status}`);
  return await res.json();
}

function endpoint(host: string, path: string, lat: string, lon: string, hourly: string, key?: string): URL {
  const url = new URL(`https://${key ? `customer-${host}` : host}${path}`);
  url.searchParams.set("latitude", lat);
  url.searchParams.set("longitude", lon);
  url.searchParams.set("hourly", hourly);
  url.searchParams.set("timezone", "auto");
  url.searchParams.set("forecast_days", "2");
  if (key) url.searchParams.set("apikey", key);
  return url;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let uid: string | null;
  try {
    uid = await callerId(req);
  } catch {
    return json({ error: "unavailable" }, 502);
  }
  if (!uid) return json({ error: "unauthorized" }, 401);

  let body: { lat?: unknown; lon?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const lat = Number(body.lat), lon = Number(body.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || !inIndia(lat, lon)) {
    return json({ error: "bad location" }, 400);
  }
  // City-level only (≈1 km): better caching, and no precise location kept.
  const la = lat.toFixed(2), lo = lon.toFixed(2);
  const cacheKey = `${la},${lo}`;

  const hit = cache.get(cacheKey);
  if (hit && Date.now() - hit.at < CACHE_MS) return json({ ...(hit.body as object), cached: true });

  try {
    if (!(await withinDailyLimit(uid, "air", DAILY_LIMIT))) return json({ error: "daily_limit" }, 429);
  } catch {
    // Counter down: still answer (weather is low-risk), but don't cache-bust.
  }

  const key = Deno.env.get("OPEN_METEO_API_KEY")?.trim() || undefined;
  try {
    const [weather, air] = await Promise.all([
      getJson(endpoint("api.open-meteo.com", "/v1/forecast", la, lo, "temperature_2m,apparent_temperature", key)),
      getJson(endpoint("air-quality-api.open-meteo.com", "/v1/air-quality", la, lo, "pm2_5,pm10", key)),
    ]);
    const out = { weather, air };
    cache.set(cacheKey, { at: Date.now(), body: out });
    if (cache.size > 500) cache.delete(cache.keys().next().value!);
    return json({ ...out, cached: false });
  } catch (e) {
    // Serve a stale copy rather than nothing.
    if (hit) return json({ ...(hit.body as object), cached: true, stale: true });
    console.error("air-heat upstream failed", String(e));
    return json({ error: "upstream" }, 502);
  }
});
