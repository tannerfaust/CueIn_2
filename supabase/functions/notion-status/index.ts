import { adminClient, corsHeaders, json, requireUser } from "../_shared/notion.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = adminClient();
    const user = await requireUser(req, admin);
    const { data, error } = await admin
      .from("notion_connections")
      .select("id, workspace_id, workspace_name, projects_database_id, tasks_database_id, status, last_synced_at")
      .eq("user_id", user.id)
      .eq("status", "active")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    return json({ connection: data }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
