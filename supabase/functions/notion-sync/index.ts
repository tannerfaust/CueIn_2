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
      counters.tasks_pulled += await pullSharedPageTasks(admin, token, user.id, connection);
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
    const syncUpdatedAt = new Date().toISOString();
    const row = {
      id: projectId,
      user_id: userId,
      field_id: fieldId,
      name: firstTitle(page.properties?.Name) || "Untitled Notion project",
      summary: firstRichText(page.properties?.Summary),
      status,
      target_date: isoDate(dateStart(page.properties?.["Target Date"])),
      icon_name: "folder.fill",
      updated_at: syncUpdatedAt,
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
    const status = taskStatusFromNotion(statusOrSelectName(page.properties?.Status));
    const completedAt = status === "completed" ? isoDate(dateStart(page.properties?.["Completed Date"]) ?? page.last_edited_time) : null;
    const syncUpdatedAt = new Date().toISOString();
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
      external_source: existing?.external_source ?? null,
      updated_at: syncUpdatedAt,
    };
    await admin.from("tasks").upsert(row, { onConflict: "id" }).throwOnError();
    await upsertLink(admin, userId, connection.id, "task", taskId, page.id, page.last_edited_time, row.updated_at);
    changed += 1;
  }
  return changed;
}

async function pullSharedPageTasks(admin: any, token: string, userId: string, connection: any) {
  if (!connection.notion_parent_page_id) return 0;
  const sources = await discoverSharedTaskSources(token, connection.notion_parent_page_id, new Set([
    connection.projects_database_id,
    connection.tasks_database_id,
  ].filter(Boolean)));

  let changed = 0;
  for (const source of sources.databases) {
    const projectId = await ensureExternalNotionProject(admin, userId, source.id, source.title);
    const project = await one(admin.from("projects").select("field_id").eq("user_id", userId).eq("id", projectId));
    const pages = await queryDatabase(token, source.id);
    for (const page of pages) {
      changed += await pullExternalTaskPage(admin, userId, connection, page, {
        projectId,
        fieldId: project?.field_id ?? await ensureNotionField(admin, userId),
        sourceTitle: source.title,
      });
    }
  }

  for (const page of sources.pages) {
    changed += await pullExternalTaskPage(admin, userId, connection, page, {
      projectId: null,
      fieldId: await ensureNotionField(admin, userId),
      sourceTitle: "Shared Notion pages",
    });
  }
  return changed;
}

async function pullExternalTaskPage(
  admin: any,
  userId: string,
  connection: any,
  page: any,
  context: { projectId: string | null; fieldId: string; sourceTitle: string },
) {
  const existingLink = await linkForPage(admin, connection.id, "task", page.id);
  const taskId = existingLink?.cuein_object_id || crypto.randomUUID();
  const existing = await one(admin.from("tasks").select("*").eq("user_id", userId).eq("id", taskId));
  const notionEdited = new Date(page.last_edited_time);
  if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
    return 0;
  }

  const properties = page.properties ?? {};
  const status = taskStatusFromNotion(statusOrSelectName(firstProperty(properties, ["Status", "State", "Stage"])));
  const completedAt = status === "completed"
    ? isoDate(dateStart(firstProperty(properties, ["Completed Date", "Done Date", "Completed"])) ?? page.last_edited_time)
    : null;
  const row = {
    id: taskId,
    user_id: userId,
    field_id: context.fieldId,
    project_id: context.projectId,
    title: firstTitleProperty(properties) || pageTitle(page) || "Untitled Notion task",
    notes: firstRichText(firstProperty(properties, ["Notes", "Description", "Details"])) || "",
    tags: multiSelectNames(firstProperty(properties, ["Tags", "Labels", "Tag"])),
    priority: taskPriorityFromNotion(selectName(firstProperty(properties, ["Priority", "Urgency"]))),
    scheduled_date: isoDate(dateStart(firstProperty(properties, ["Scheduled Date", "Start", "Do Date", "When"]))),
    due_date: isoDate(dateStart(firstProperty(properties, ["Due Date", "Deadline", "Date"]))),
    status,
    completed_at: completedAt,
    recurrence: "none",
    subtasks: [],
    saves_to_archive: true,
    external_source: "notion",
    updated_at: new Date().toISOString(),
  };
  await admin.from("tasks").upsert(row, { onConflict: "id" }).throwOnError();
  await upsertLink(admin, userId, connection.id, "task", taskId, page.id, page.last_edited_time, row.updated_at, "pull_only");
  return 1;
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
    if (link?.sync_direction === "pull_only") {
      await pushExternalTaskStatus(token, task, link);
      continue;
    }
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

async function pushExternalTaskStatus(token: string, task: any, link: any) {
  if (!link?.notion_page_id) return false;
  if (task.status === "archived") return false;
  const page = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "GET" });
  const statusEntry = statusPropertyEntry(page.properties ?? {});
  if (!statusEntry) return false;

  const [propertyName, property] = statusEntry;
  const parentDatabaseId = page.parent?.type === "database_id" ? page.parent.database_id : null;
  const targetStatus = parentDatabaseId
    ? await externalStatusValue(token, parentDatabaseId, propertyName, task.status)
    : fallbackExternalStatusValue(task.status);
  if (!targetStatus) return false;

  const nextProperty = property.type === "status"
    ? { status: { name: targetStatus } }
    : { select: { name: targetStatus } };

  await notionRequest<any>(token, `/pages/${link.notion_page_id}`, {
    method: "PATCH",
    body: JSON.stringify({ properties: { [propertyName]: nextProperty } }),
  });
  return true;
}

async function externalStatusValue(token: string, databaseId: string, propertyName: string, cueInStatus: string) {
  const database = await notionRequest<any>(token, `/databases/${databaseId}`, { method: "GET" });
  const property = database.properties?.[propertyName];
  const options = property?.status?.options ?? property?.select?.options ?? [];
  const optionNames = options.map((option: any) => option?.name).filter(Boolean);
  return bestStatusOption(cueInStatus, optionNames);
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

async function discoverSharedTaskSources(token: string, parentPageId: string, managedDatabaseIds: Set<string>) {
  const databases: Array<{ id: string; title: string }> = [];
  const pages: any[] = [];
  const databaseIds = new Set<string>();
  const pageIds = new Set<string>();

  const addDatabase = (id: string | null | undefined, title: string | null | undefined) => {
    if (!id || managedDatabaseIds.has(id) || databaseIds.has(id)) return;
    databaseIds.add(id);
    databases.push({ id, title: title || "Notion database" });
  };

  const addPage = (page: any) => {
    if (!page?.id || pageIds.has(page.id) || page.id === parentPageId) return;
    const parentDatabaseId = page.parent?.type === "database_id" ? page.parent.database_id : null;
    if (parentDatabaseId && managedDatabaseIds.has(parentDatabaseId)) return;
    pageIds.add(page.id);
    pages.push(page);
  };

  const queue: Array<{ id: string; depth: number }> = [{ id: parentPageId, depth: 0 }];
  const visited = new Set<string>();

  while (queue.length) {
    const current = queue.shift()!;
    if (visited.has(current.id) || current.depth > 3) continue;
    visited.add(current.id);

    const children = await listBlockChildren(token, current.id);
    for (const block of children) {
      if (block.type === "child_database" && block.id && !managedDatabaseIds.has(block.id)) {
        addDatabase(block.id, block.child_database?.title);
      } else if (block.type === "child_page" && block.id) {
        if (current.depth > 0) {
          addPage({
            id: block.id,
            object: "page",
            last_edited_time: block.last_edited_time,
            properties: {
              title: { title: [{ type: "text", text: { content: block.child_page?.title || "" }, plain_text: block.child_page?.title || "" }] },
            },
          });
        }
        queue.push({ id: block.id, depth: current.depth + 1 });
      }
    }
  }

  for (const database of await searchNotionObjects(token, "database")) {
    addDatabase(database.id, notionTitleText(database.title));
  }

  for (const page of await searchNotionObjects(token, "page")) {
    addPage(page);
  }

  return { databases, pages };
}

async function searchNotionObjects(token: string, objectType: "database" | "page") {
  const results = [];
  let start_cursor: string | undefined;
  do {
    const body: Record<string, unknown> = {
      page_size: 100,
      filter: { property: "object", value: objectType },
    };
    if (start_cursor) body.start_cursor = start_cursor;
    const response = await notionRequest<any>(token, "/search", {
      method: "POST",
      body: JSON.stringify(body),
    });
    results.push(...(response.results ?? []));
    start_cursor = response.has_more ? response.next_cursor : undefined;
  } while (start_cursor);
  return results;
}

async function listBlockChildren(token: string, blockId: string) {
  const results = [];
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

async function ensureExternalNotionProject(admin: any, userId: string, sourceId: string, sourceTitle: string) {
  const fieldId = await ensureNotionField(admin, userId);
  const deterministicId = await deterministicUUID(`${userId}:notion-source:${sourceId}`);
  const existing = await one(admin.from("projects").select("id").eq("user_id", userId).eq("id", deterministicId));
  if (existing) return existing.id;
  await admin.from("projects").upsert({
    id: deterministicId,
    user_id: userId,
    field_id: fieldId,
    name: sourceTitle || "Notion import",
    summary: "Imported from a shared Notion database",
    icon_name: "tray.full.fill",
    status: "active",
    external_source: "notion",
    updated_at: new Date().toISOString(),
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
  syncDirection = "two_way",
) {
  await admin.from("notion_object_links").upsert({
    user_id: userId,
    connection_id: connectionId,
    object_kind: kind,
    cuein_object_id: cueInObjectId,
    notion_page_id: notionPageId,
    notion_last_edited_time: notionLastEditedTime,
    cuein_updated_at: cueInUpdatedAt,
    sync_direction: syncDirection,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
}

function firstTitleProperty(properties: Record<string, any>) {
  for (const property of Object.values(properties ?? {})) {
    const value = firstTitle(property);
    if (value) return value;
  }
  return "";
}

function firstProperty(properties: Record<string, any>, names: string[]) {
  for (const name of names) {
    if (properties?.[name]) return properties[name];
  }
  const lowerNames = names.map((name) => name.toLowerCase());
  return Object.entries(properties ?? {}).find(([key]) => lowerNames.includes(key.toLowerCase()))?.[1] ?? null;
}

function pageTitle(page: any) {
  return firstTitleProperty(page.properties ?? {});
}

function notionTitleText(parts: any[] | null | undefined) {
  return (parts ?? []).map((part) => part?.plain_text ?? part?.text?.content ?? "").join("").trim();
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

function statusOrSelectName(property: any) {
  return property?.status?.name ?? property?.select?.name ?? null;
}

function statusPropertyEntry(properties: Record<string, any>): [string, any] | null {
  const direct = Object.entries(properties ?? {}).find(([name, property]) =>
    ["status", "state", "stage"].includes(name.toLowerCase()) &&
    (property?.type === "status" || property?.type === "select")
  );
  if (direct) return direct as [string, any];
  const typed = Object.entries(properties ?? {}).find(([, property]) =>
    property?.type === "status" || property?.type === "select"
  );
  return typed ? typed as [string, any] : null;
}

function fallbackExternalStatusValue(cueInStatus: string) {
  switch (cueInStatus) {
    case "scheduled": return "To-do";
    case "active": return "In Progress";
    case "paused": return "Paused";
    case "completed": return "Done";
    case "archived": return "Archived";
    default: return "Waiting";
  }
}

function bestStatusOption(cueInStatus: string, optionNames: string[]) {
  const normalized = new Map(optionNames.map((name) => [normalizeStatusName(name), name]));
  const candidates = statusCandidates(cueInStatus);
  for (const candidate of candidates) {
    const match = normalized.get(normalizeStatusName(candidate));
    if (match) return match;
  }
  return null;
}

function statusCandidates(cueInStatus: string) {
  switch (cueInStatus) {
    case "scheduled":
      return ["To-do", "Todo", "To Do", "Not started", "Backlog", "Next", "Planned"];
    case "active":
      return ["In Progress", "Doing", "Active", "Started", "Working"];
    case "paused":
      return ["Paused", "Blocked", "On Hold", "Waiting"];
    case "completed":
      return ["Done", "Complete", "Completed", "Finished"];
    case "archived":
      return ["Archived", "Archive", "Canceled", "Cancelled"];
    default:
      return ["Waiting", "Inbox", "Backlog", "To-do", "Todo", "To Do"];
  }
}

function normalizeStatusName(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "");
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
