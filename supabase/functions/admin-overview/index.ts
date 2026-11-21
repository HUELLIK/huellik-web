import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://huellik-web.vercel.app",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
];

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("HUELLIK_ALLOWED_ORIGINS");
  const values = configured
    ? configured.split(",").map((value) => value.trim()).filter(Boolean)
    : DEFAULT_ALLOWED_ORIGINS;
  return new Set(values);
}

function corsHeaders(origin: string | null): HeadersInit {
  const headers: Record<string, string> = {
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
  };

  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(origin),
  });
}

function getPublishableKey(): string {
  // Current Supabase runtimes may expose the default publishable key as a JSON map.
  const publishableKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (publishableKeys) {
    try {
      const parsed = JSON.parse(publishableKeys);
      if (typeof parsed.default === "string" && parsed.default.length > 0) {
        return parsed.default;
      }
    } catch {
      throw new Error("Invalid publishable-key runtime configuration");
    }
  }

  // Compatibility fallback for projects that still expose the legacy anon key.
  return Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    "";
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (origin && !allowedOrigins().has(origin)) {
    return jsonResponse({ error: "Origin not allowed" }, 403, null);
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      status: 204,
      headers: corsHeaders(origin),
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405, origin);
  }

  const authorization = req.headers.get("authorization") ?? "";
  const bearerMatch = authorization.match(/^Bearer\s+(.+)$/i);
  if (!bearerMatch) {
    return jsonResponse({ error: "Authentication required" }, 401, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = getPublishableKey();
  if (!supabaseUrl || !publishableKey) {
    console.error("Missing Supabase URL or publishable key runtime configuration");
    return jsonResponse({ error: "Server configuration error" }, 500, origin);
  }

  // This client carries the caller's JWT. It deliberately does not use service_role.
  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser(
    bearerMatch[1],
  );

  if (userError || !userData.user) {
    return jsonResponse({ error: "Invalid or expired session" }, 401, origin);
  }

  // The database RPC re-checks auth.uid() against petlink.admin_users.
  // No user_metadata, email, browser state, or caller-supplied role is trusted.
  const { data, error } = await userClient.rpc("huellik_admin_overview_v1");

  if (error) {
    if (
      error.code === "42501" ||
      /not authorized|permission denied/i.test(error.message)
    ) {
      return jsonResponse({ error: "Administrator access required" }, 403, origin);
    }

    console.error("Admin overview RPC failed:", error.code ?? "unknown");
    return jsonResponse({ error: "Unable to load administration overview" }, 500, origin);
  }

  return jsonResponse({ data }, 200, origin);
});
