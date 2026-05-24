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

    const { data: existingConnection } = await admin
      .from("notion_connections")
      .select("projects_database_id, tasks_database_id, notion_parent_page_id, external_tasks_database_id")
      .eq("user_id", user.id)
      .eq("workspace_id", tokenBody.workspace_id)
      .maybeSingle();

    const setup = await ensureCueInDatabases(
      accessToken,
      existingConnection?.notion_parent_page_id,
      existingConnection?.projects_database_id,
      existingConnection?.tasks_database_id
    );

    if (existingConnection) {
      if (existingConnection.projects_database_id !== setup.projectsDatabaseId) {
        await admin
          .from("notion_object_links")
          .delete()
          .eq("user_id", user.id)
          .eq("object_kind", "project");
      }
      if (existingConnection.tasks_database_id !== setup.tasksDatabaseId) {
        await admin
          .from("notion_object_links")
          .delete()
          .eq("user_id", user.id)
          .eq("object_kind", "task");
      }
    }

    const externalTaskTarget = await discoverExternalTaskDatabase(accessToken, setup.parentPageId, new Set([
      setup.projectsDatabaseId,
      setup.tasksDatabaseId,
    ].filter(Boolean) as string[]));

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
        external_tasks_database_id: externalTaskTarget?.id ?? existingConnection?.external_tasks_database_id ?? null,
        external_tasks_database_title: externalTaskTarget?.title ?? null,
        external_tasks_property_map: externalTaskTarget?.propertyMap ?? null,
        status: "active",
        last_error: null,
        disconnected_at: null,
      }, { onConflict: "user_id,workspace_id" })
      .select("id, workspace_id, workspace_name, projects_database_id, tasks_database_id, external_tasks_database_id, external_tasks_database_title, external_tasks_property_map, status, last_synced_at")
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

async function ensureCueInDatabases(
  token: string,
  existingParentPageId?: string | null,
  existingProjectsDbId?: string | null,
  existingTasksDbId?: string | null
) {
  const isProjectsValid = await isDatabaseValid(token, existingProjectsDbId);
  const isTasksValid = await isDatabaseValid(token, existingTasksDbId);

  if (isProjectsValid && isTasksValid && existingParentPageId) {
    console.log(`Reusing existing valid databases: Projects=${existingProjectsDbId}, Tasks=${existingTasksDbId}`);
    return {
      parentPageId: existingParentPageId,
      projectsDatabaseId: existingProjectsDbId!,
      tasksDatabaseId: existingTasksDbId!,
    };
  }

  const parentPageId = await findWritableParentPage(token);
  let projectsDatabaseId: string | null = null;
  let tasksDatabaseId: string | null = null;

  try {
    const children = await listBlockChildren(token, parentPageId);
    const projectsDbs: string[] = [];
    const tasksDbs: string[] = [];

    for (const block of children) {
      if (block.type === "child_database" && !block.archived) {
        const title = block.child_database?.title;
        if (title === "CueIn Projects") {
          projectsDbs.push(block.id);
        } else if (title === "CueIn Tasks") {
          tasksDbs.push(block.id);
        }
      }
    }

    if (projectsDbs.length > 0) {
      if (projectsDbs.length === 1) {
        projectsDatabaseId = projectsDbs[0];
      } else {
        let maxPages = -1;
        for (const dbId of projectsDbs) {
          const count = await getDatabasePageCount(token, dbId);
          if (count > maxPages) {
            maxPages = count;
            projectsDatabaseId = dbId;
          }
        }
      }
    }

    if (tasksDbs.length > 0) {
      if (tasksDbs.length === 1) {
        tasksDatabaseId = tasksDbs[0];
      } else {
        let maxPages = -1;
        for (const dbId of tasksDbs) {
          const count = await getDatabasePageCount(token, dbId);
          if (count > maxPages) {
            maxPages = count;
            tasksDatabaseId = dbId;
          }
        }
      }
    }
  } catch (e) {
    console.error("Error finding existing databases:", e);
  }

  if (!projectsDatabaseId) {
    const projectsDatabase = await createProjectsDatabase(token, parentPageId);
    projectsDatabaseId = projectsDatabase.id;
  }

  if (!tasksDatabaseId) {
    const tasksDatabase = await createTasksDatabase(token, parentPageId, projectsDatabaseId!);
    tasksDatabaseId = tasksDatabase.id;
  }

  return {
    parentPageId,
    projectsDatabaseId,
    tasksDatabaseId,
  };
}

async function discoverExternalTaskDatabase(
  token: string,
  parentPageId: string,
  managedDatabaseIds: Set<string>,
) {
  const candidates: Array<{ id: string; title: string; propertyMap: any; score: number }> = [];
  const children = await listBlockChildren(token, parentPageId).catch(() => []);
  for (const block of children) {
    if (block.type !== "child_database" || block.archived || !block.id || managedDatabaseIds.has(block.id)) continue;
    const title = block.child_database?.title || "Notion database";
    const database = await notionRequest<any>(token, `/databases/${block.id}`, { method: "GET" }).catch(() => null);
    if (!database?.properties) continue;
    const propertyMap = buildTaskPropertyMap(database.properties);
    const score = taskDatabaseScore(title, database.properties, propertyMap);
    if (score >= 12) {
      await ensureCueInIDProperty(token, block.id, database.properties, propertyMap).catch(() => {});
      const updated = await notionRequest<any>(token, `/databases/${block.id}`, { method: "GET" }).catch(() => database);
      candidates.push({
        id: block.id,
        title,
        propertyMap: buildTaskPropertyMap(updated.properties ?? database.properties),
        score,
      });
    }
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0] ?? null;
}

function buildTaskPropertyMap(properties: Record<string, any>) {
  const title = firstPropertyNameByType(properties, "title");
  const notes = firstNamedPropertyName(properties, ["Notes", "Description", "Details", "Summary"], ["rich_text"]);
  const status = firstPropertyName(properties, ["Status", "State", "Stage"], ["status", "select"]);
  const dueDate = firstNamedPropertyName(properties, ["Due Date", "Due", "Deadline", "Date"], ["date"]);
  const scheduledDate = firstNamedPropertyName(properties, ["Scheduled Date", "Scheduled", "Start", "Do Date", "When"], ["date"]);
  const completedDate = firstNamedPropertyName(properties, ["Completed Date", "Done Date", "Completed", "Completed on"], ["date"]);
  const priority = firstPropertyName(properties, ["Priority", "Urgency"], ["select", "status"]);
  const tags = firstNamedPropertyName(properties, ["Tags", "Labels", "Tag"], ["multi_select"]);
  const cueInID = firstNamedPropertyName(properties, ["CueIn ID", "CueInID", "CueIn"], ["rich_text"]);
  return {
    title,
    notes,
    status,
    statusType: status ? properties[status]?.type : null,
    dueDate,
    scheduledDate,
    completedDate,
    priority,
    priorityType: priority ? properties[priority]?.type : null,
    tags,
    cueInID,
  };
}

function taskDatabaseScore(title: string, properties: Record<string, any>, map: any) {
  let score = 0;
  const normalizedTitle = title.toLowerCase();
  if (/\btasks?\b|\btodo\b|\bto dos?\b/.test(normalizedTitle)) score += 14;
  if (map.title) score += 4;
  if (map.status) score += 4;
  if (map.dueDate || map.scheduledDate) score += 2;
  if (map.notes) score += 2;
  if (map.priority) score += 1;
  if (Object.keys(properties ?? {}).length >= 3) score += 1;
  return score;
}

async function ensureCueInIDProperty(token: string, databaseId: string, properties: Record<string, any>, map: any) {
  if (map.cueInID) return;
  await notionRequest<any>(token, `/databases/${databaseId}`, {
    method: "PATCH",
    body: JSON.stringify({ properties: { "CueIn ID": { rich_text: {} } } }),
  });
}

function firstPropertyNameByType(properties: Record<string, any>, type: string) {
  return Object.entries(properties ?? {}).find(([, property]) => property?.type === type)?.[0] ?? null;
}

function firstPropertyName(properties: Record<string, any>, names: string[], types: string[]) {
  for (const name of names) {
    const match = Object.keys(properties ?? {}).find((key) => key.toLowerCase() === name.toLowerCase());
    if (match && types.includes(properties[match]?.type)) return match;
  }
  return Object.entries(properties ?? {}).find(([, property]) => types.includes(property?.type))?.[0] ?? null;
}

function firstNamedPropertyName(properties: Record<string, any>, names: string[], types: string[]) {
  for (const name of names) {
    const match = Object.keys(properties ?? {}).find((key) => key.toLowerCase() === name.toLowerCase());
    if (match && types.includes(properties[match]?.type)) return match;
  }
  return null;
}

async function isDatabaseValid(token: string, databaseId: string | null | undefined): Promise<boolean> {
  if (!databaseId) return false;
  try {
    const db = await notionRequest<any>(token, `/databases/${databaseId}`, { method: "GET" });
    return db && !db.archived;
  } catch (e) {
    return false;
  }
}

async function getDatabasePageCount(token: string, databaseId: string): Promise<number> {
  try {
    const res = await notionRequest<any>(token, `/databases/${databaseId}/query`, {
      method: "POST",
      body: JSON.stringify({ page_size: 100 })
    });
    return res.results?.length ?? 0;
  } catch (e) {
    return 0;
  }
}

async function listBlockChildren(token: string, blockId: string) {
  const results: any[] = [];
  let start_cursor: string | undefined;
  do {
    const query = new URLSearchParams({ page_size: "100" });
    if (start_cursor) query.set("start_cursor", start_cursor);
    const response = await notionRequest<any>(token, `/blocks/${blockId}/children?${query.toString()}`, { method: "GET" });
    results.push(...(response.results ?? []));
    start_cursor = response.has_more ? response.next_cursor : undefined;
  } while (start_cursor);
  return results;
}

async function findWritableParentPage(token: string) {
  const search = await notionRequest<any>(token, "/search", {
    method: "POST",
    body: JSON.stringify({
      filter: { property: "object", value: "page" },
      page_size: 100,
    }),
  });
  // Exclude pages that are children of databases (i.e. tasks)
  const page = search.results?.find((result: any) => 
    result.object === "page" && 
    result.parent?.type !== "database_id"
  );
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
