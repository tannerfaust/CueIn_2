import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const notionVersion = "2022-06-28";

export function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

export async function notionRequest<T>(
  token: string,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(`https://api.notion.com/v1${path}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      "Notion-Version": notionVersion,
      ...(init.headers ?? {}),
    },
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Notion ${response.status}: ${body}`);
  }
  return body ? JSON.parse(body) as T : {} as T;
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
  const secret = Deno.env.get("NOTION_TOKEN_ENCRYPTION_KEY");
  if (!secret || secret.trim().length < 16) {
    throw new Error("NOTION_TOKEN_ENCRYPTION_KEY must be configured");
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

export function titleProperty(title: string) {
  return { title: [{ type: "text", text: { content: title } }] };
}

export function richTextProperty(value?: string | null) {
  const content = (value ?? "").slice(0, 1900);
  return { rich_text: content ? [{ type: "text", text: { content } }] : [] };
}

export function selectProperty(value?: string | null) {
  return value ? { select: { name: value } } : { select: null };
}

export function dateProperty(value?: string | null) {
  return value ? { date: { start: value } } : { date: null };
}

export function multiSelectProperty(values?: string[] | null) {
  return { multi_select: (values ?? []).map((name) => ({ name: String(name).slice(0, 100) })) };
}

export function firstTitle(property: any) {
  return property?.title?.map((part: any) => part?.plain_text ?? "").join("") ?? "";
}

export function firstRichText(property: any) {
  return property?.rich_text?.map((part: any) => part?.plain_text ?? "").join("") ?? "";
}

export function selectName(property: any) {
  return property?.select?.name ?? null;
}

export function dateStart(property: any) {
  return property?.date?.start ?? null;
}

export function multiSelectNames(property: any) {
  return Array.isArray(property?.multi_select)
    ? property.multi_select.map((item: any) => item?.name).filter(Boolean)
    : [];
}
