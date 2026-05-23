import {
  adminClient,
  corsHeaders,
  encryptToken,
  json,
  notionRequest,
  requireUser,
} from "../_shared/notion.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = adminClient();
    const user = await requireUser(req, admin);
    const { code, state } = await req.json().catch(() => ({}));
    if (!code || !state) {
      return json({ error: "Missing OAuth callback data" }, 400);
    }

    const { data: stateRow, error: stateError } = await admin
      .from("notion_oauth_states")
      .select("*")
      .eq("user_id", user.id)
      .eq("state", state)
      .is("consumed_at", null)
      .maybeSingle();
    if (stateError) return json({ error: stateError.message }, 500);
    if (!stateRow || new Date(stateRow.expires_at).getTime() < Date.now()) {
      return json({ error: "Invalid or expired OAuth state" }, 400);
    }

    const clientId = Deno.env.get("NOTION_CLIENT_ID");
    const clientSecret = Deno.env.get("NOTION_CLIENT_SECRET");
    if (!clientId || !clientSecret) {
      return json({ error: "Notion OAuth credentials are not configured" }, 500);
    }

    const tokenResponse = await fetch("https://api.notion.com/v1/oauth/token", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        grant_type: "authorization_code",
        code,
        redirect_uri: stateRow.redirect_uri,
      }),
    });
    const tokenBody = await tokenResponse.json().catch(() => ({}));
    if (!tokenResponse.ok) {
      return json({ error: tokenBody?.error_description ?? tokenBody?.message ?? "Notion OAuth failed" }, 400);
    }

    const accessToken = tokenBody.access_token as string;
    const encrypted = await encryptToken(accessToken);
    const setup = await ensureCueInDatabases(accessToken);

    const { data: connection, error: upsertError } = await admin
      .from("notion_connections")
      .upsert({
        user_id: user.id,
        workspace_id: tokenBody.workspace_id,
        workspace_name: tokenBody.workspace_name ?? null,
        bot_id: tokenBody.bot_id ?? null,
        owner_type: tokenBody.owner?.type ?? null,
        owner_user_id: tokenBody.owner?.user?.id ?? null,
        encrypted_access_token: encrypted.encryptedAccessToken,
        token_nonce: encrypted.tokenNonce,
        notion_parent_page_id: setup.parentPageId,
        projects_database_id: setup.projectsDatabaseId,
        tasks_database_id: setup.tasksDatabaseId,
        status: "active",
        last_error: null,
        disconnected_at: null,
      }, { onConflict: "user_id,workspace_id" })
      .select("id, workspace_id, workspace_name, projects_database_id, tasks_database_id, status, last_synced_at")
      .single();
    if (upsertError) return json({ error: upsertError.message }, 500);

    await admin
      .from("notion_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", stateRow.id);

    return json({ connection }, 200);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});

async function ensureCueInDatabases(token: string) {
  const parentPageId = await findWritableParentPage(token);
  const projectsDatabase = await createProjectsDatabase(token, parentPageId);
  const tasksDatabase = await createTasksDatabase(token, parentPageId, projectsDatabase.id);
  return {
    parentPageId,
    projectsDatabaseId: projectsDatabase.id,
    tasksDatabaseId: tasksDatabase.id,
  };
}

async function findWritableParentPage(token: string) {
  const search = await notionRequest<any>(token, "/search", {
    method: "POST",
    body: JSON.stringify({
      filter: { property: "object", value: "page" },
      page_size: 10,
    }),
  });
  const page = search.results?.find((result: any) => result.object === "page");
  if (!page?.id) {
    throw new Error("No Notion page was shared with CueIn. Reconnect and select a parent page during authorization.");
  }
  return page.id;
}

async function createProjectsDatabase(token: string, parentPageId: string) {
  return await notionRequest<any>(token, "/databases", {
    method: "POST",
    body: JSON.stringify({
      parent: { type: "page_id", page_id: parentPageId },
      title: [{ type: "text", text: { content: "CueIn Projects" } }],
      properties: {
        Name: { title: {} },
        Summary: { rich_text: {} },
        Status: { select: { options: ["Active", "Paused", "Done", "Archived"].map((name) => ({ name })) } },
        "Target Date": { date: {} },
        "CueIn ID": { rich_text: {} },
        "Last Synced": { date: {} },
      },
    }),
  });
}

async function createTasksDatabase(token: string, parentPageId: string, projectsDatabaseId: string) {
  return await notionRequest<any>(token, "/databases", {
    method: "POST",
    body: JSON.stringify({
      parent: { type: "page_id", page_id: parentPageId },
      title: [{ type: "text", text: { content: "CueIn Tasks" } }],
      properties: {
        Name: { title: {} },
        Notes: { rich_text: {} },
        Status: { select: { options: ["Waiting", "To-do", "In Progress", "Paused", "Done", "Archived"].map((name) => ({ name })) } },
        Priority: { select: { options: ["Normal", "High", "Urgent"].map((name) => ({ name })) } },
        Project: { relation: { database_id: projectsDatabaseId, type: "single_property", single_property: {} } },
        Tags: { multi_select: {} },
        "Scheduled Date": { date: {} },
        "Due Date": { date: {} },
        "Completed Date": { date: {} },
        "CueIn ID": { rich_text: {} },
        "Last Synced": { date: {} },
      },
    }),
  });
}
