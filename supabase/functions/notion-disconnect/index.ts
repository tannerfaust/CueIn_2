import { adminClient, corsHeaders, json, requireUser } from "../_shared/notion.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = adminClient();
    const user = await requireUser(req, admin);
    const now = new Date().toISOString();
    const { error } = await admin
      .from("notion_connections")
      .update({ status: "disconnected", disconnected_at: now })
      .eq("user_id", user.id)
      .eq("status", "active");
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
