import {
  adminClient,
  corsHeaders,
  dateProperty,
  dateStart,
  decryptToken,
  firstRichText,
  firstTitle,
  isoDate,
  json,
  multiSelectNames,
  multiSelectProperty,
  notionRequest,
  requireUser,
  richTextProperty,
  selectName,
  selectProperty,
  titleProperty,
} from "../_shared/notion.ts";

type SyncAction = "full" | "push" | "pull";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = adminClient();
  let runId: string | null = null;
  try {
    const user = await requireUser(req, admin);
    const { action = "full" } = await req.json().catch(() => ({})) as { action?: SyncAction };
    if (!["full", "push", "pull"].includes(action)) return json({ error: "Invalid sync action" }, 400);

    const { data: connection, error: connectionError } = await admin
      .from("notion_connections")
      .select("*")
      .eq("user_id", user.id)
      .eq("status", "active")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (connectionError) return json({ error: connectionError.message }, 500);
    if (!connection) return json({ error: "Notion is not connected" }, 404);

    const { data: run, error: runError } = await admin
      .from("notion_sync_runs")
      .insert({ user_id: user.id, connection_id: connection.id, action, status: "running" })
      .select("id")
      .single();
    if (runError) return json({ error: runError.message }, 500);
    runId = run.id;

    const token = await decryptToken(connection.encrypted_access_token, connection.token_nonce);
    const counters = {
      projects_pushed: 0,
      projects_pulled: 0,
      tasks_pushed: 0,
      tasks_pulled: 0,
    };

    if (action === "full" || action === "pull") {
      counters.projects_pulled = await pullProjects(admin, token, user.id, connection);
      counters.tasks_pulled = await pullTasks(admin, token, user.id, connection);
    }
    if (action === "full" || action === "push") {
      counters.projects_pushed = await pushProjects(admin, token, user.id, connection);
      counters.tasks_pushed = await pushTasks(admin, token, user.id, connection);
    }

    const now = new Date().toISOString();
    await admin.from("notion_connections").update({
      last_synced_at: now,
      last_error: null,
    }).eq("id", connection.id);
    await admin.from("notion_sync_runs").update({
      ...counters,
      status: "succeeded",
      finished_at: now,
    }).eq("id", runId);

    return json({ ok: true, ...counters, last_synced_at: now }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    if (runId) {
      await admin.from("notion_sync_runs").update({
        status: "failed",
        error: message,
        finished_at: new Date().toISOString(),
      }).eq("id", runId);
    }
    if (error instanceof Response) return error;
    return json({ error: message }, 500);
  }
});

async function pullProjects(admin: any, token: string, userId: string, connection: any) {
  const pages = await queryDatabase(token, connection.projects_database_id);
  let changed = 0;
  for (const page of pages) {
    const cueInID = firstRichText(page.properties?.["CueIn ID"]);
    const existingLink = await linkForPage(admin, connection.id, "project", page.id);
    const projectId = cueInID || existingLink?.cuein_object_id || crypto.randomUUID();
    const existing = await one(admin.from("projects").select("*").eq("user_id", userId).eq("id", projectId));
    const notionEdited = new Date(page.last_edited_time);
    if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
      continue;
    }

    const fieldId = await ensureNotionField(admin, userId);
    const status = projectStatusFromNotion(selectName(page.properties?.Status));
    const row = {
      id: projectId,
      user_id: userId,
      field_id: fieldId,
      name: firstTitle(page.properties?.Name) || "Untitled Notion project",
      summary: firstRichText(page.properties?.Summary),
      status,
      target_date: isoDate(dateStart(page.properties?.["Target Date"])),
      icon_name: "folder.fill",
      updated_at: notionEdited.toISOString(),
    };
    await admin.from("projects").upsert(row, { onConflict: "id" }).throwOnError();
    await upsertLink(admin, userId, connection.id, "project", projectId, page.id, page.last_edited_time, row.updated_at);
    changed += 1;
  }
  return changed;
}

async function pullTasks(admin: any, token: string, userId: string, connection: any) {
  const pages = await queryDatabase(token, connection.tasks_database_id);
  let changed = 0;
  for (const page of pages) {
    const cueInID = firstRichText(page.properties?.["CueIn ID"]);
    const existingLink = await linkForPage(admin, connection.id, "task", page.id);
    const taskId = cueInID || existingLink?.cuein_object_id || crypto.randomUUID();
    const existing = await one(admin.from("tasks").select("*").eq("user_id", userId).eq("id", taskId));
    const notionEdited = new Date(page.last_edited_time);
    if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
      continue;
    }

    const projectPageId = page.properties?.Project?.relation?.[0]?.id ?? null;
    const projectLink = projectPageId ? await linkForPage(admin, connection.id, "project", projectPageId) : null;
    const projectId = projectLink?.cuein_object_id ?? null;
    const project = projectId ? await one(admin.from("projects").select("field_id").eq("user_id", userId).eq("id", projectId)) : null;
    const status = taskStatusFromNotion(selectName(page.properties?.Status));
    const completedAt = status === "completed" ? isoDate(dateStart(page.properties?.["Completed Date"]) ?? page.last_edited_time) : null;
    const row = {
      id: taskId,
      user_id: userId,
      field_id: project?.field_id ?? await ensureNotionField(admin, userId),
      project_id: projectId,
      title: firstTitle(page.properties?.Name) || "Untitled Notion task",
      notes: firstRichText(page.properties?.Notes),
      tags: multiSelectNames(page.properties?.Tags),
      priority: taskPriorityFromNotion(selectName(page.properties?.Priority)),
      scheduled_date: isoDate(dateStart(page.properties?.["Scheduled Date"])),
      due_date: isoDate(dateStart(page.properties?.["Due Date"])),
      status,
      completed_at: completedAt,
      recurrence: "none",
      subtasks: [],
      saves_to_archive: true,
      updated_at: notionEdited.toISOString(),
    };
    await admin.from("tasks").upsert(row, { onConflict: "id" }).throwOnError();
    await upsertLink(admin, userId, connection.id, "task", taskId, page.id, page.last_edited_time, row.updated_at);
    changed += 1;
  }
  return changed;
}

async function pushProjects(admin: any, token: string, userId: string, connection: any) {
  const { data: projects, error } = await admin
    .from("projects")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  let changed = 0;
  for (const project of projects ?? []) {
    const link = await linkForObject(admin, userId, "project", project.id);
    if (link?.notion_last_edited_time && new Date(link.notion_last_edited_time) > new Date(project.updated_at)) {
      continue;
    }
    const properties = projectProperties(project);
    const page = link
      ? await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "PATCH", body: JSON.stringify({ properties }) })
      : await notionRequest<any>(token, "/pages", {
        method: "POST",
        body: JSON.stringify({ parent: { database_id: connection.projects_database_id }, properties }),
      });
    await upsertLink(admin, userId, connection.id, "project", project.id, page.id, page.last_edited_time, project.updated_at);
    changed += 1;
  }
  return changed;
}

async function pushTasks(admin: any, token: string, userId: string, connection: any) {
  const { data: tasks, error } = await admin
    .from("tasks")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  let changed = 0;
  for (const task of tasks ?? []) {
    const link = await linkForObject(admin, userId, "task", task.id);
    if (link?.notion_last_edited_time && new Date(link.notion_last_edited_time) > new Date(task.updated_at)) {
      continue;
    }
    const projectLink = task.project_id ? await linkForObject(admin, userId, "project", task.project_id) : null;
    const properties = taskProperties(task, projectLink?.notion_page_id ?? null);
    const page = link
      ? await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "PATCH", body: JSON.stringify({ properties }) })
      : await notionRequest<any>(token, "/pages", {
        method: "POST",
        body: JSON.stringify({ parent: { database_id: connection.tasks_database_id }, properties }),
      });
    await upsertLink(admin, userId, connection.id, "task", task.id, page.id, page.last_edited_time, task.updated_at);
    changed += 1;
  }
  return changed;
}

async function queryDatabase(token: string, databaseId: string) {
  const results = [];
  let start_cursor: string | undefined;
  do {
    const body: Record<string, unknown> = { page_size: 100 };
    if (start_cursor) body.start_cursor = start_cursor;
    const response = await notionRequest<any>(token, `/databases/${databaseId}/query`, {
      method: "POST",
      body: JSON.stringify(body),
    });
    results.push(...(response.results ?? []));
    start_cursor = response.has_more ? response.next_cursor : undefined;
  } while (start_cursor);
  return results;
}

function projectProperties(project: any) {
  return {
    Name: titleProperty(project.name),
    Summary: richTextProperty(project.summary),
    Status: selectProperty(projectStatusToNotion(project.status)),
    "Target Date": dateProperty(project.target_date),
    "CueIn ID": richTextProperty(project.id),
    "Last Synced": dateProperty(new Date().toISOString()),
  };
}

function taskProperties(task: any, projectPageId: string | null) {
  return {
    Name: titleProperty(task.title),
    Notes: richTextProperty(task.notes),
    Status: selectProperty(taskStatusToNotion(task.status)),
    Priority: selectProperty(taskPriorityToNotion(task.priority)),
    Project: { relation: projectPageId ? [{ id: projectPageId }] : [] },
    Tags: multiSelectProperty(task.tags),
    "Scheduled Date": dateProperty(task.scheduled_date),
    "Due Date": dateProperty(task.due_date),
    "Completed Date": dateProperty(task.completed_at),
    "CueIn ID": richTextProperty(task.id),
    "Last Synced": dateProperty(new Date().toISOString()),
  };
}

async function ensureNotionField(admin: any, userId: string) {
  const deterministicId = await deterministicUUID(`${userId}:field:notion`);
  const existing = await one(admin.from("fields").select("id").eq("user_id", userId).eq("id", deterministicId));
  if (existing) return existing.id;
  await admin.from("fields").upsert({
    id: deterministicId,
    user_id: userId,
    name: "Notion",
    summary: "Imported from Notion",
    icon_name: "square.grid.2x2.fill",
    color_hex: 9342609,
  }, { onConflict: "id" }).throwOnError();
  return deterministicId;
}

async function deterministicUUID(input: string) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input)));
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = [...hash.slice(0, 16)].map((byte) => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10, 16).join("")}`;
}

async function one(query: any) {
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

async function linkForObject(admin: any, userId: string, kind: string, cueInObjectId: string) {
  return await one(admin
    .from("notion_object_links")
    .select("*")
    .eq("user_id", userId)
    .eq("object_kind", kind)
    .eq("cuein_object_id", cueInObjectId));
}

async function linkForPage(admin: any, connectionId: string, kind: string, notionPageId: string) {
  return await one(admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connectionId)
    .eq("object_kind", kind)
    .eq("notion_page_id", notionPageId));
}

async function upsertLink(
  admin: any,
  userId: string,
  connectionId: string,
  kind: string,
  cueInObjectId: string,
  notionPageId: string,
  notionLastEditedTime: string,
  cueInUpdatedAt: string,
) {
  await admin.from("notion_object_links").upsert({
    user_id: userId,
    connection_id: connectionId,
    object_kind: kind,
    cuein_object_id: cueInObjectId,
    notion_page_id: notionPageId,
    notion_last_edited_time: notionLastEditedTime,
    cuein_updated_at: cueInUpdatedAt,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
}

function projectStatusToNotion(value: string) {
  switch (value) {
    case "paused": return "Paused";
    case "done": return "Done";
    case "archived": return "Archived";
    default: return "Active";
  }
}

function projectStatusFromNotion(value: string | null) {
  switch (value) {
    case "Paused": return "paused";
    case "Done": return "done";
    case "Archived": return "archived";
    default: return "active";
  }
}

function taskStatusToNotion(value: string) {
  switch (value) {
    case "scheduled": return "To-do";
    case "active": return "In Progress";
    case "paused": return "Paused";
    case "completed": return "Done";
    case "archived": return "Archived";
    default: return "Waiting";
  }
}

function taskStatusFromNotion(value: string | null) {
  switch (value) {
    case "To-do": return "scheduled";
    case "In Progress": return "active";
    case "Paused": return "paused";
    case "Done": return "completed";
    case "Archived": return "archived";
    default: return "inbox";
  }
}

function taskPriorityToNotion(value: string) {
  switch (value) {
    case "high": return "High";
    case "urgent": return "Urgent";
    default: return "Normal";
  }
}

function taskPriorityFromNotion(value: string | null) {
  switch (value) {
    case "High": return "high";
    case "Urgent": return "urgent";
    default: return "normal";
  }
}
