import { adminClient, corsHeaders, json, requireUser } from "../_shared/notion.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = adminClient();
    const user = await requireUser(req, admin);
    const { redirect_uri } = await req.json().catch(() => ({}));
    if (!redirect_uri || typeof redirect_uri !== "string") {
      return json({ error: "Missing redirect_uri" }, 400);
    }

    const clientId = Deno.env.get("NOTION_CLIENT_ID");
    if (!clientId) return json({ error: "NOTION_CLIENT_ID is not configured" }, 500);

    const state = crypto.randomUUID();
    const { error } = await admin.from("notion_oauth_states").insert({
      user_id: user.id,
      state,
      redirect_uri,
    });
    if (error) return json({ error: error.message }, 500);

    const url = new URL("https://api.notion.com/v1/oauth/authorize");
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("owner", "user");
    url.searchParams.set("redirect_uri", redirect_uri);
    url.searchParams.set("state", state);

    return json({ authorization_url: url.toString(), state }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
