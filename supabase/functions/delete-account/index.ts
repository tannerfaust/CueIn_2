import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server is not configured" }, 500);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error: userError } = await admin.auth.getUser(token);
  if (userError || !data.user) {
    return json({ error: "Invalid session" }, 401);
  }

  const userId = data.user.id;
  const cleanupSteps: Array<[string, PromiseLike<{ error: { message: string } | null }>]> = [
    ["notion_sync_runs", admin.from("notion_sync_runs").delete().eq("user_id", userId)],
    ["notion_object_links", admin.from("notion_object_links").delete().eq("user_id", userId)],
    ["notion_connections", admin.from("notion_connections").delete().eq("user_id", userId)],
    ["notion_oauth_states", admin.from("notion_oauth_states").delete().eq("user_id", userId)],
    ["sync_mutations", admin.from("sync_mutations").delete().eq("user_id", userId)],
    ["tasks", admin.from("tasks").delete().eq("user_id", userId)],
    ["projects", admin.from("projects").delete().eq("user_id", userId)],
    ["fields", admin.from("fields").delete().eq("user_id", userId)],
    ["goals", admin.from("goals").delete().eq("user_id", userId)],
    ["schedule_records", admin.from("schedule_records").delete().eq("user_id", userId)],
    ["app_layout_settings", admin.from("app_layout_settings").delete().eq("user_id", userId)],
    ["profiles", admin.from("profiles").delete().eq("id", userId)],
  ];

  for (const [table, deletion] of cleanupSteps) {
    const { error } = await deletion;
    if (error) {
      return json({ error: `Failed to delete ${table}: ${error.message}` }, 500);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId, false);
  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  return json({ ok: true }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
