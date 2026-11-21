import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://huellik-web.vercel.app",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
];

function origins(): Set<string> {
  const configured = Deno.env.get("HUELLIK_ALLOWED_ORIGINS");
  return new Set(configured
    ? configured.split(",").map((v) => v.trim()).filter(Boolean)
    : DEFAULT_ALLOWED_ORIGINS);
}

function response(body: Record<string, unknown>, status: number, origin: string | null): Response {
  const headers: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (origin && origins().has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return new Response(JSON.stringify(body), { status, headers });
}

function publishableKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keys) {
    const parsed = JSON.parse(keys);
    if (typeof parsed.default === "string" && parsed.default) return parsed.default;
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
}

function validPayload(action: string, payload: unknown): payload is Record<string, unknown> {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return false;
  const p = payload as Record<string, unknown>;
  if (action === "list") return Object.keys(p).length === 0;
  if (action === "deactivate") return typeof p.id === "string" && /^[0-9a-f-]{36}$/i.test(p.id);
  if (action !== "create" && action !== "update") return false;
  if (action === "update" && !(typeof p.id === "string" && /^[0-9a-f-]{36}$/i.test(p.id))) return false;
  if (typeof p.code !== "string" || p.code.trim().length < 3 || p.code.trim().length > 40) return false;
  if (p.discount_type !== "percent" && p.discount_type !== "fixed") return false;
  if (typeof p.discount_value !== "number" || !Number.isFinite(p.discount_value) || p.discount_value <= 0) return false;
  if (p.discount_type === "percent" && p.discount_value > 100) return false;
  if (p.currency !== undefined && p.currency !== "EUR") return false;
  if (p.description !== undefined && p.description !== null && typeof p.description !== "string") return false;
  if (p.applies_to !== undefined && (!Array.isArray(p.applies_to) || p.applies_to.length < 1 || p.applies_to.some((v) => !["all","plus_monthly","plus_annual","tag_metal","tag_flex"].includes(v)))) return false;
  if (p.starts_at !== undefined && p.starts_at !== null && (typeof p.starts_at !== "string" || Number.isNaN(Date.parse(p.starts_at)))) return false;
  if (p.expires_at !== undefined && p.expires_at !== null && p.expires_at !== "" && (typeof p.expires_at !== "string" || Number.isNaN(Date.parse(p.expires_at)))) return false;
  for (const k of ["max_redemptions","max_redemptions_per_user"]) {
    if (p[k] !== undefined && p[k] !== null && (!Number.isInteger(p[k]) || (p[k] as number) < 1)) return false;
  }
  if (p.first_time_only !== undefined && typeof p.first_time_only !== "boolean") return false;
  if (p.active !== undefined && typeof p.active !== "boolean") return false;
  return true;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (origin && !origins().has(origin)) return response({ error: "Origin not allowed" }, 403, null);
  if (req.method === "OPTIONS") return new Response("ok", { status: 204, headers: {
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    ...(origin && origins().has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
  }});
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, origin);

  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return response({ error: "Authentication required" }, 401, origin);

  let body: unknown;
  try { body = await req.json(); } catch { return response({ error: "Invalid JSON body" }, 400, origin); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return response({ error: "Invalid request" }, 400, origin);
  const { action, payload = {} } = body as { action?: unknown; payload?: unknown };
  if (typeof action !== "string" || !validPayload(action, payload)) return response({ error: "Invalid request data" }, 400, origin);

  const url = Deno.env.get("SUPABASE_URL");
  const key = publishableKey();
  if (!url || !key) return response({ error: "Server configuration error" }, 500, origin);

  const client = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const { data: userData, error: userError } = await client.auth.getUser(token);
  if (userError || !userData.user) return response({ error: "Invalid or expired session" }, 401, origin);

  const { data, error } = await client.rpc("huellik_admin_promotions_v1", {
    p_action: action,
    p_payload: payload,
  });
  if (error) {
    if (error.code === "42501" || /not authorized|permission denied/i.test(error.message)) {
      return response({ error: "Administrator access required" }, 403, origin);
    }
    if (error.code === "23505") return response({ error: "Ese código promocional ya existe." }, 409, origin);
    if (error.code === "P0002") return response({ error: "No se encontró la promoción." }, 404, origin);
    if (error.code === "22023" || error.code === "23514") return response({ error: "Los datos de la promoción no son válidos." }, 400, origin);
    console.error("Admin promotions RPC failed:", error.code ?? "unknown");
    return response({ error: "No se pudo completar la operación." }, 500, origin);
  }
  return response({ data }, 200, origin);
});
