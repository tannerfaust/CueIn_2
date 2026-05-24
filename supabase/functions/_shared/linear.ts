import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// See _shared/notion.ts for the rationale; same allow-list is reused here so
// the two providers can't drift out of sync security-wise.
const allowedOriginsList = (Deno.env.get("INTEGRATION_ALLOWED_ORIGINS") ?? "https://cuein.app,https://www.cuein.app,https://app.cuein.app")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

export function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowOrigin = allowedOriginsList.includes(origin) ? origin : (allowedOriginsList[0] ?? "");
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": allowedOriginsList[0] ?? "",
  "Vary": "Origin",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export async function acquireIntegrationLock(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  provider: "notion" | "linear",
): Promise<{ acquired: boolean; release: () => Promise<void> }> {
  const { data, error } = await admin.rpc("try_acquire_integration_sync_lock", {
    p_user_id: userId,
    p_provider: provider,
  });
  if (error) {
    console.warn(`acquireIntegrationLock(${provider}) RPC failed: ${error.message}`);
    return { acquired: true, release: async () => {} };
  }
  if (data !== true) {
    return { acquired: false, release: async () => {} };
  }
  return {
    acquired: true,
    release: async () => {
      const { error: releaseError } = await admin.rpc("release_integration_sync_lock", {
        p_user_id: userId,
        p_provider: provider,
      });
      if (releaseError) {
        console.warn(`releaseIntegrationLock(${provider}) RPC failed: ${releaseError.message}`);
      }
    },
  };
}

export function adminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Server is not configured");
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function requireUser(req: Request, admin: ReturnType<typeof adminClient>) {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Response(JSON.stringify({ error: "Missing bearer token" }), { status: 401 });
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    throw new Response(JSON.stringify({ error: "Invalid session" }), { status: 401 });
  }
  return data.user;
}

export async function linearRequest<T>(
  token: string,
  query: string,
  variables?: Record<string, unknown>,
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetch("https://api.linear.app/graphql", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, variables }),
    });
    const bodyText = await response.text();
    if (!response.ok) {
      throw new Error(`Linear API returned status ${response.status}: ${bodyText}`);
    }
    let body;
    try {
      body = JSON.parse(bodyText);
    } catch {
      throw new Error(`Linear API returned invalid JSON: ${bodyText}`);
    }
    if (body.errors && body.errors.length > 0) {
      throw new Error(`Linear GraphQL error: ${body.errors[0].message}`);
    }
    return body.data as T;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("Linear request timed out");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export async function encryptToken(token: string) {
  const key = await tokenKey();
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(token);
  const cipher = await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, encoded);
  return {
    encryptedAccessToken: encodeBase64(new Uint8Array(cipher)),
    tokenNonce: encodeBase64(nonce),
  };
}

export async function decryptToken(encryptedAccessToken: string, tokenNonce: string) {
  const key = await tokenKey();
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: decodeBase64(tokenNonce) },
    key,
    decodeBase64(encryptedAccessToken),
  );
  return new TextDecoder().decode(plain);
}

async function tokenKey() {
  const secret = Deno.env.get("LINEAR_TOKEN_ENCRYPTION_KEY") || Deno.env.get("NOTION_TOKEN_ENCRYPTION_KEY");
  if (!secret || secret.trim().length < 16) {
    throw new Error("LINEAR_TOKEN_ENCRYPTION_KEY must be configured (fallback to NOTION_TOKEN_ENCRYPTION_KEY failed)");
  }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret));
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export function encodeBase64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes));
}

export function decodeBase64(value: string) {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

export function isoDate(value?: string | null) {
  return value ? new Date(value).toISOString() : null;
}
