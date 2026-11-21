import { createClient } from "npm:@supabase/supabase-js@2.95.0";

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("HUELLIK_ALLOWED_ORIGINS");
  return new Set(configured
    ? configured.split(",").map((v) => v.trim()).filter(Boolean)
    : ["https://huellik-web.vercel.app", "http://localhost:3000", "http://127.0.0.1:3000"]);
}
function response(body: Record<string, unknown>, status: number, origin: string | null): Response {
  const headers: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (origin && allowedOrigins().has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return new Response(JSON.stringify(body), { status, headers });
}
function publishableKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keys) {
    const parsed = JSON.parse(keys);
    if (typeof parsed.default === "string" && parsed.default) return parsed.default;
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (origin && !allowedOrigins().has(origin)) return response({ error: "Origin not allowed" }, 403, null);
  if (req.method === "OPTIONS") return new Response("ok", {
    status: 204,
    headers: {
      "Vary": "Origin",
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      ...(origin && allowedOrigins().has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
    },
  });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, origin);

  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return response({ error: "Authentication required" }, 401, origin);

  let body: unknown;
  try { body = await req.json(); } catch { return response({ error: "Invalid JSON body" }, 400, origin); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return response({ error: "Invalid request" }, 400, origin);
  const input = body as { query?: unknown; limit?: unknown; offset?: unknown };
  const query = input.query === undefined ? "" : input.query;
  const limit = input.limit === undefined ? 20 : input.limit;
  const offset = input.offset === undefined ? 0 : input.offset;
  if (typeof query !== "string" || query.length > 80 ||
      !Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 50 ||
      !Number.isInteger(offset) || (offset as number) < 0 || (offset as number) > 100000) {
    return response({ error: "Invalid search parameters" }, 400, origin);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = publishableKey();
  if (!url || !key) return response({ error: "Server configuration error" }, 500, origin);
  const client = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const { data: userData, error: userError } = await client.auth.getUser(token);
  if (userError || !userData.user) return response({ error: "Invalid or expired session" }, 401, origin);

  const { data, error } = await client.rpc("huellik_admin_users_v1", {
    p_query: query,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) {
    if (error.code === "42501" || /not authorized|permission denied/i.test(error.message)) {
      return response({ error: "Administrator access required" }, 403, origin);
    }
    if (error.code === "22023") return response({ error: "Invalid search parameters" }, 400, origin);
    console.error("Admin users RPC failed:", error.code ?? "unknown");
    return response({ error: "Unable to load users" }, 500, origin);
  }
  return response({ data }, 200, origin);
});
