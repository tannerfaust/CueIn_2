import {
  acquireIntegrationLock,
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
  let releaseLock: (() => Promise<void>) | null = null;
  const debugLog: string[] = [];
  try {
    const user = await requireUser(req, admin);

    // Serialize concurrent runs (rapid client retry, scheduled poll + user
    // click) so they can't double-write the same Notion page.
    const lock = await acquireIntegrationLock(admin, user.id, "notion");
    if (!lock.acquired) {
      return json({ ok: true, projects_pushed: 0, projects_pulled: 0, tasks_pushed: 0, tasks_pulled: 0, conflicts: [], skipped: "another_sync_in_progress" }, 200);
    }
    releaseLock = lock.release;

    const body = await req.json().catch(() => ({})) as {
      action?: SyncAction;
      targets?: { task_ids?: string[]; project_ids?: string[]; force_overwrite_task_ids?: string[] };
    };
    const action: SyncAction = body.action ?? "full";
    if (!["full", "push", "pull"].includes(action)) return json({ error: "Invalid sync action" }, 400);
    const dedupe = (ids?: string[]) => (ids && ids.length > 0 ? Array.from(new Set(ids)) : undefined);
    const taskTargets = dedupe(body.targets?.task_ids);
    const projectTargets = dedupe(body.targets?.project_ids);
    const forceOverwriteTaskIDs = new Set(dedupe(body.targets?.force_overwrite_task_ids) ?? []);
    const conflicts: NotionSyncConflict[] = [];

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
    await ensureExternalTaskTarget(admin, token, user.id, connection, debugLog);

    const counters = {
      projects_pushed: 0,
      projects_pulled: 0,
      tasks_pushed: 0,
      tasks_pulled: 0,
    };

    if (action === "full" || action === "pull") {
      counters.projects_pulled = await pullProjects(admin, token, user.id, connection, debugLog);
      counters.tasks_pulled = await pullTasks(admin, token, user.id, connection, debugLog);
      counters.tasks_pulled += await pullSharedPageTasks(admin, token, user.id, connection, debugLog);
    }
    if (action === "full" || action === "push") {
      counters.projects_pushed = await pushProjects(admin, token, user.id, connection, debugLog, projectTargets);
      counters.tasks_pushed = await pushTasks(admin, token, user.id, connection, debugLog, taskTargets, forceOverwriteTaskIDs, conflicts);
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
      debug_log: debugLog,
    }).eq("id", runId);

    return json({ ok: true, ...counters, conflicts, last_synced_at: now }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    if (runId) {
      await admin.from("notion_sync_runs").update({
        status: "failed",
        error: message,
        finished_at: new Date().toISOString(),
        debug_log: debugLog,
      }).eq("id", runId);
    }
    if (error instanceof Response) return error;
    return json({ error: message }, 500);
  } finally {
    if (releaseLock) {
      try { await releaseLock(); } catch (_) { /* logged inside release */ }
    }
  }
});

async function pullProjects(admin: any, token: string, userId: string, connection: any, debugLog: string[] = []) {
  if (!connection.projects_database_id) {
    debugLog.push("pullProjects: No projects database ID configured");
    return 0;
  }
  const pages = await safeQueryDatabase(admin, token, connection, "projects_database_id", debugLog);
  if (!pages) return 0;
  debugLog.push(`pullProjects: Notion database query returned ${pages.length} pages`);

  const pageIds = pages.map((p) => p.id);
  const pageIdSet = new Set(pageIds);

  const { data: allLinks, error: allLinksError } = await admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connection.id)
    .eq("object_kind", "project")
    .eq("sync_direction", "two_way");
  if (allLinksError) throw new Error(allLinksError.message);

  debugLog.push(`pullProjects: Existing project links in DB = ${allLinks.length}`);

  const projectsToSoftDelete: string[] = [];
  const projectLinksToDelete: string[] = [];

  const missingLinks = allLinks.filter((l: any) => !pageIdSet.has(l.notion_page_id));
  for (const link of missingLinks) {
    projectLinksToDelete.push(link.id);
    projectsToSoftDelete.push(link.cuein_object_id);
  }

  if (projectsToSoftDelete.length > 0) {
    const now = new Date().toISOString();
    await admin.from("projects").update({ deleted_at: now, updated_at: now }).in("id", projectsToSoftDelete);
  }
  if (projectLinksToDelete.length > 0) {
    await admin.from("notion_object_links").delete().in("id", projectLinksToDelete);
  }

  if (pages.length === 0) return 0;

  const { data: links, error: linksError } = await admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connection.id)
    .eq("object_kind", "project")
    .in("notion_page_id", pageIds);
  if (linksError) throw new Error(linksError.message);

  const linkMap = new Map<string, any>(links.map((l: any) => [l.notion_page_id, l]));
  const projectIdsToFetch: string[] = [];
  const projectInfoMap = new Map<string, { page: any; cueInID: string | null; existingLink: any }>();

  for (const page of pages) {
    const cueInID = firstRichText(page.properties?.["CueIn ID"]);
    const existingLink = linkMap.get(page.id);
    const projectId = cueInID || existingLink?.cuein_object_id;
    if (projectId) {
      projectIdsToFetch.push(projectId);
    }
    projectInfoMap.set(page.id, { page, cueInID, existingLink });
  }

  let existingMap = new Map<string, any>();
  if (projectIdsToFetch.length > 0) {
    const { data: existingProjects, error: projectsError } = await admin
      .from("projects")
      .select("*")
      .eq("user_id", userId)
      .in("id", projectIdsToFetch);
    if (projectsError) throw new Error(projectsError.message);
    existingMap = new Map(existingProjects.map((p: any) => [p.id, p]));
  }

  const projectsToUpsert: any[] = [];
  const linksToUpsert: any[] = [];
  let changed = 0;
  const fieldId = await ensureNotionField(admin, userId);

  for (const page of pages) {
    const { cueInID, existingLink } = projectInfoMap.get(page.id)!;
    const projectId = cueInID || existingLink?.cuein_object_id || crypto.randomUUID();
    const existing = existingMap.get(projectId);
    const notionEdited = new Date(page.last_edited_time);

    const isLinkMissing = !existingLink;

    if (existingLink && notionEdited.getTime() <= new Date(existingLink.notion_last_edited_time).getTime()) {
      continue;
    }
    if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
      if (isLinkMissing) {
        linksToUpsert.push({
          user_id: userId,
          connection_id: connection.id,
          object_kind: "project",
          cuein_object_id: projectId,
          notion_page_id: page.id,
          notion_last_edited_time: page.last_edited_time,
          cuein_updated_at: notionEdited.toISOString(),
          sync_direction: "two_way",
          last_synced_at: new Date().toISOString(),
        });
      }
      continue;
    }

    const status = projectStatusFromNotion(selectName(page.properties?.Status));
    const syncUpdatedAt = notionEdited.toISOString();
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

    projectsToUpsert.push(row);
    linksToUpsert.push({
      user_id: userId,
      connection_id: connection.id,
      object_kind: "project",
      cuein_object_id: projectId,
      notion_page_id: page.id,
      notion_last_edited_time: page.last_edited_time,
      cuein_updated_at: syncUpdatedAt,
      sync_direction: "two_way",
      last_synced_at: new Date().toISOString(),
    });
    changed += 1;
  }

  if (projectsToUpsert.length > 0) {
    await admin.from("projects").upsert(projectsToUpsert, { onConflict: "id" }).throwOnError();
  }
  if (linksToUpsert.length > 0) {
    await admin.from("notion_object_links").upsert(linksToUpsert, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
  }
  return changed;
}

async function pullTasks(admin: any, token: string, userId: string, connection: any, debugLog: string[] = []) {
  if (!connection.tasks_database_id) {
    debugLog.push("pullTasks: No tasks database ID configured");
    return 0;
  }
  const pages = await safeQueryDatabase(admin, token, connection, "tasks_database_id", debugLog);
  if (!pages) return 0;
  debugLog.push(`pullTasks: Notion database query returned ${pages.length} pages`);

  const pageIds = pages.map((p) => p.id);
  const pageIdSet = new Set(pageIds);
  const { data: allLinks, error: allLinksError } = await admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .eq("sync_direction", "two_way");
  if (allLinksError) throw new Error(allLinksError.message);

  debugLog.push(`pullTasks: Existing two_way task links in DB = ${allLinks.length}`);

  const tasksToSoftDelete: string[] = [];
  const taskLinksToDelete: string[] = [];

  const missingLinks = allLinks.filter((l: any) => !pageIdSet.has(l.notion_page_id));
  for (const link of missingLinks) {
    taskLinksToDelete.push(link.id);
    tasksToSoftDelete.push(link.cuein_object_id);
  }

  if (tasksToSoftDelete.length > 0) {
    const now = new Date().toISOString();
    await admin.from("tasks").update({ deleted_at: now, updated_at: now }).in("id", tasksToSoftDelete);
  }
  if (taskLinksToDelete.length > 0) {
    await admin.from("notion_object_links").delete().in("id", taskLinksToDelete);
  }

  if (pages.length === 0) return 0;

  const { data: links, error: linksError } = await admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .in("notion_page_id", pageIds);
  if (linksError) throw new Error(linksError.message);

  const linkMap = new Map<string, any>(links.map((l: any) => [l.notion_page_id, l]));
  const taskIdsToFetch: string[] = [];
  const taskInfoMap = new Map<string, { page: any; cueInID: string | null; existingLink: any }>();

  for (const page of pages) {
    const cueInID = firstRichText(page.properties?.["CueIn ID"]);
    const existingLink = linkMap.get(page.id);
    const taskId = cueInID || existingLink?.cuein_object_id;
    if (taskId) {
      taskIdsToFetch.push(taskId);
    }
    taskInfoMap.set(page.id, { page, cueInID, existingLink });
  }

  let existingMap = new Map<string, any>();
  if (taskIdsToFetch.length > 0) {
    const { data: existingTasks, error: tasksError } = await admin
      .from("tasks")
      .select("*")
      .eq("user_id", userId)
      .in("id", taskIdsToFetch);
    if (tasksError) throw new Error(tasksError.message);
    existingMap = new Map(existingTasks.map((t: any) => [t.id, t]));
  }

  const projectPageIdsToFetch = new Set<string>();
  for (const page of pages) {
    const projectPageId = page.properties?.Project?.relation?.[0]?.id ?? null;
    if (projectPageId) {
      projectPageIdsToFetch.add(projectPageId);
    }
  }

  let projectLinkMap = new Map<string, any>();
  if (projectPageIdsToFetch.size > 0) {
    const { data: projectLinks, error: projLinksError } = await admin
      .from("notion_object_links")
      .select("*")
      .eq("connection_id", connection.id)
      .eq("object_kind", "project")
      .in("notion_page_id", Array.from(projectPageIdsToFetch));
    if (projLinksError) throw new Error(projLinksError.message);
    projectLinkMap = new Map(projectLinks.map((l: any) => [l.notion_page_id, l]));
  }

  const projectIdsToFetchForField = Array.from(projectLinkMap.values()).map((l) => l.cuein_object_id);
  let projectMap = new Map<string, any>();
  if (projectIdsToFetchForField.length > 0) {
    const { data: projects, error: projectsError } = await admin
      .from("projects")
      .select("id, field_id")
      .eq("user_id", userId)
      .in("id", projectIdsToFetchForField);
    if (projectsError) throw new Error(projectsError.message);
    projectMap = new Map(projects.map((p: any) => [p.id, p]));
  }

  const tasksToUpsert: any[] = [];
  const linksToUpsert: any[] = [];
  let changed = 0;
  const fallbackFieldId = await ensureNotionField(admin, userId);

  for (const page of pages) {
    const { cueInID, existingLink } = taskInfoMap.get(page.id)!;
    const taskId = cueInID || existingLink?.cuein_object_id || crypto.randomUUID();
    const existing = existingMap.get(taskId);
    const notionEdited = new Date(page.last_edited_time);

    const isLinkMissing = !existingLink;

    if (existingLink && notionEdited.getTime() <= new Date(existingLink.notion_last_edited_time).getTime()) {
      continue;
    }
    if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
      if (isLinkMissing) {
        linksToUpsert.push({
          user_id: userId,
          connection_id: connection.id,
          object_kind: "task",
          cuein_object_id: taskId,
          notion_page_id: page.id,
          notion_last_edited_time: page.last_edited_time,
          cuein_updated_at: notionEdited.toISOString(),
          sync_direction: "two_way",
          last_synced_at: new Date().toISOString(),
        });
      }
      continue;
    }

    const projectPageId = page.properties?.Project?.relation?.[0]?.id ?? null;
    const projectLink = projectPageId ? projectLinkMap.get(projectPageId) : null;
    const projectId = projectLink?.cuein_object_id ?? null;
    const project = projectId ? projectMap.get(projectId) : null;

    const status = taskStatusFromNotion(statusOrSelectName(page.properties?.Status));
    const completedAt = status === "completed" ? isoDate(dateStart(page.properties?.["Completed Date"]) ?? page.last_edited_time) : null;
    const syncUpdatedAt = notionEdited.toISOString();

    const row = {
      id: taskId,
      user_id: userId,
      field_id: project?.field_id ?? fallbackFieldId,
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

    tasksToUpsert.push(row);
    linksToUpsert.push({
      user_id: userId,
      connection_id: connection.id,
      object_kind: "task",
      cuein_object_id: taskId,
      notion_page_id: page.id,
      notion_last_edited_time: page.last_edited_time,
      cuein_updated_at: syncUpdatedAt,
      sync_direction: "two_way",
      last_synced_at: new Date().toISOString(),
    });
    changed += 1;
  }

  if (tasksToUpsert.length > 0) {
    await admin.from("tasks").upsert(tasksToUpsert, { onConflict: "id" }).throwOnError();
  }
  if (linksToUpsert.length > 0) {
    await admin.from("notion_object_links").upsert(linksToUpsert, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
  }
  return changed;
}

async function pullSharedPageTasks(admin: any, token: string, userId: string, connection: any, debugLog: string[] = []) {
  if (!connection.notion_parent_page_id) {
    debugLog.push("pullSharedPageTasks: No notion parent page ID configured");
    return 0;
  }
  const sources = await discoverSharedTaskSources(token, connection.notion_parent_page_id, new Set([
    connection.projects_database_id,
    connection.tasks_database_id,
  ].filter(Boolean)));
  debugLog.push(`pullSharedPageTasks: Crawler found ${sources.databases.length} databases and ${sources.pages.length} inline pages`);

  let changed = 0;
  for (const source of sources.databases) {
    const projectId = await ensureExternalNotionProject(admin, userId, source.id, source.title);
    const project = await one(admin.from("projects").select("field_id").eq("user_id", userId).eq("id", projectId));
    const pages = await queryDatabase(token, source.id);
    const activePageIds = new Set(pages.map((page: any) => page.id));
    debugLog.push(`pullSharedPageTasks: Database ${source.id} (${source.title}) query returned ${pages.length} pages`);
    changed += await pullExternalTaskPagesBatch(admin, userId, connection, pages, {
      projectId,
      fieldId: project?.field_id ?? await ensureNotionField(admin, userId),
      sourceTitle: source.title,
    });
    changed += await softDeleteMissingExternalTasksForProject(admin, userId, connection, projectId, activePageIds, debugLog);
    changed += await softDeleteMissingTwoWayTasksForDatabase(admin, token, userId, connection, source.id, activePageIds, debugLog);
  }

  changed += await pullExternalTaskPagesBatch(admin, userId, connection, sources.pages, {
    projectId: null,
    fieldId: await ensureNotionField(admin, userId),
    sourceTitle: "Shared Notion pages",
  });

  changed += await reconcileArchivedExternalTasks(admin, token, userId, connection, debugLog);
  return changed;
}

async function pullExternalTaskPagesBatch(
  admin: any,
  userId: string,
  connection: any,
  pages: any[],
  context: { projectId: string | null; fieldId: string; sourceTitle: string },
) {
  if (pages.length === 0) return 0;

  const pageIds = pages.map((p) => p.id);
  const { data: links, error: linksError } = await admin
    .from("notion_object_links")
    .select("*")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .in("notion_page_id", pageIds);
  if (linksError) throw new Error(linksError.message);

  const linkMap = new Map<string, any>(links.map((l: any) => [l.notion_page_id, l]));
  const taskIdsToFetch: string[] = [];
  const taskInfoMap = new Map<string, { page: any; existingLink: any; cueInID: string | null }>();

  for (const page of pages) {
    const existingLink = linkMap.get(page.id);
    const properties = page.properties ?? {};
    const cueInID = firstRichText(firstProperty(properties, ["CueIn ID", "CueInID", "CueIn"]));
    const taskId = cueInID || existingLink?.cuein_object_id;
    if (taskId) {
      taskIdsToFetch.push(taskId);
    }
    taskInfoMap.set(page.id, { page, existingLink, cueInID });
  }

  let existingMap = new Map<string, any>();
  if (taskIdsToFetch.length > 0) {
    const { data: existingTasks, error: tasksError } = await admin
      .from("tasks")
      .select("*")
      .eq("user_id", userId)
      .in("id", taskIdsToFetch);
    if (tasksError) throw new Error(tasksError.message);
    existingMap = new Map(existingTasks.map((t: any) => [t.id, t]));
  }

  const tasksToUpsert: any[] = [];
  const linksToUpsert: any[] = [];
  let changed = 0;

  for (const page of pages) {
    const { existingLink, cueInID } = taskInfoMap.get(page.id)!;
    const taskId = cueInID || existingLink?.cuein_object_id || await deterministicUUID(`${connection.id}:notion-page:${page.id}`);
    const existing = existingMap.get(taskId);
    const notionEdited = new Date(page.last_edited_time);
    const syncDirection = cueInID || existingLink?.sync_direction === "two_way" ? "two_way" : "pull_only";

    const isLinkMissing = !existingLink;

    if (existingLink && notionEdited.getTime() <= new Date(existingLink.notion_last_edited_time).getTime()) {
      continue;
    }
    if (existing && existing.updated_at && new Date(existing.updated_at) > notionEdited) {
      if (isLinkMissing) {
        linksToUpsert.push({
          user_id: userId,
          connection_id: connection.id,
          object_kind: "task",
          cuein_object_id: taskId,
          notion_page_id: page.id,
          notion_last_edited_time: page.last_edited_time,
          cuein_updated_at: notionEdited.toISOString(),
          sync_direction: syncDirection,
          last_synced_at: new Date().toISOString(),
        });
      }
      continue;
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
      external_source: syncDirection === "two_way" ? existing?.external_source ?? null : "notion",
      updated_at: notionEdited.toISOString(),
    };

    tasksToUpsert.push(row);
    linksToUpsert.push({
      user_id: userId,
      connection_id: connection.id,
      object_kind: "task",
      cuein_object_id: taskId,
      notion_page_id: page.id,
      notion_last_edited_time: page.last_edited_time,
      cuein_updated_at: row.updated_at,
      sync_direction: syncDirection,
      last_synced_at: new Date().toISOString(),
    });
    changed += 1;
  }

  if (tasksToUpsert.length > 0) {
    await admin.from("tasks").upsert(tasksToUpsert, { onConflict: "id" }).throwOnError();
  }
  if (linksToUpsert.length > 0) {
    await admin.from("notion_object_links").upsert(linksToUpsert, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
  }
  return changed;
}

async function reconcileArchivedExternalTasks(
  admin: any,
  token: string,
  userId: string,
  connection: any,
  debugLog: string[] = [],
) {
  const { data: links, error } = await admin
    .from("notion_object_links")
    .select("id, cuein_object_id, notion_page_id")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .eq("sync_direction", "pull_only");
  if (error) throw new Error(error.message);

  const archived: any[] = [];
  for (const link of links ?? []) {
    try {
      const page = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "GET" });
      if (page.archived || page.in_trash) {
        archived.push(link);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      if (message.includes("404") || message.includes("object_not_found") || message.includes("restricted_resource")) {
        archived.push(link);
      } else {
        debugLog.push(`pullSharedPageTasks: Could not verify page ${link.notion_page_id}: ${message}`);
      }
    }
  }

  if (archived.length === 0) return 0;

  const now = new Date().toISOString();
  const taskIds = archived.map((link: any) => link.cuein_object_id);
  const linkIds = archived.map((link: any) => link.id);
  debugLog.push(`pullSharedPageTasks: Soft-deleting ${archived.length} archived or inaccessible pull-only Notion tasks`);

  await admin
    .from("tasks")
    .update({ deleted_at: now, updated_at: now })
    .eq("user_id", userId)
    .eq("external_source", "notion")
    .in("id", taskIds)
    .throwOnError();

  await admin
    .from("notion_object_links")
    .delete()
    .in("id", linkIds)
    .throwOnError();

  return archived.length;
}

async function softDeleteMissingExternalTasksForProject(
  admin: any,
  userId: string,
  connection: any,
  projectId: string,
  activePageIds: Set<string>,
  debugLog: string[] = [],
) {
  const { data: tasks, error: tasksError } = await admin
    .from("tasks")
    .select("id")
    .eq("user_id", userId)
    .eq("external_source", "notion")
    .eq("project_id", projectId)
    .is("deleted_at", null);
  if (tasksError) throw new Error(tasksError.message);
  if (!tasks || tasks.length === 0) return 0;

  const taskIds = tasks.map((task: any) => task.id);
  const { data: links, error: linksError } = await admin
    .from("notion_object_links")
    .select("id, cuein_object_id, notion_page_id")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .eq("sync_direction", "pull_only")
    .in("cuein_object_id", taskIds);
  if (linksError) throw new Error(linksError.message);

  const missing = (links ?? []).filter((link: any) => !activePageIds.has(link.notion_page_id));
  if (missing.length === 0) return 0;

  const now = new Date().toISOString();
  const missingTaskIds = missing.map((link: any) => link.cuein_object_id);
  const missingLinkIds = missing.map((link: any) => link.id);
  debugLog.push(`pullSharedPageTasks: Soft-deleting ${missing.length} Notion tasks removed from source project ${projectId}`);

  await admin
    .from("tasks")
    .update({ deleted_at: now, updated_at: now })
    .eq("user_id", userId)
    .eq("external_source", "notion")
    .in("id", missingTaskIds)
    .throwOnError();

  await admin
    .from("notion_object_links")
    .delete()
    .in("id", missingLinkIds)
    .throwOnError();

  return missing.length;
}

async function pushProjects(admin: any, token: string, userId: string, connection: any, debugLog: string[] = [], projectTargets?: string[]) {
  if (!connection.projects_database_id) return 0;
  const notionFieldId = await notionFieldIdForUser(userId);
  const managedProjectsAvailable = await isDatabaseValid(token, connection.projects_database_id);
  if (!managedProjectsAvailable) {
    debugLog.push(`pushProjects: Managed projects database is inaccessible; clearing ${connection.projects_database_id}`);
    await clearConnectionDatabase(admin, connection, "projects_database_id");
    connection.projects_database_id = null;
    return 0;
  }
  let changed = 0;

  let deletedProjectsQuery = admin
    .from("projects")
    .select("*")
    .eq("user_id", userId)
    .not("deleted_at", "is", null);
  if (projectTargets) deletedProjectsQuery = deletedProjectsQuery.in("id", projectTargets);
  const { data: deletedProjects, error: deletedProjectsError } = await deletedProjectsQuery;
  if (deletedProjectsError) throw new Error(deletedProjectsError.message);

  for (const project of deletedProjects ?? []) {
    const link = await linkForObject(admin, userId, "project", project.id);
    if (link) {
      if (link.sync_direction === "two_way" && project.external_source !== "notion") {
        try {
          debugLog.push(`pushProjects: Archiving deleted project page ${link.notion_page_id} in Notion`);
          await notionRequest<any>(token, `/pages/${link.notion_page_id}`, {
            method: "PATCH",
            body: JSON.stringify({ archived: true }),
          });
        } catch (e: any) {
          debugLog.push(`pushProjects: Failed to archive page ${link.notion_page_id} in Notion: ${e.message}`);
        }
      }
      await admin.from("notion_object_links").delete().eq("id", link.id);
      changed += 1;
    }
  }

  let activeProjectsQuery = admin
    .from("projects")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (projectTargets) activeProjectsQuery = activeProjectsQuery.in("id", projectTargets);
  const { data: projects, error } = await activeProjectsQuery;
  if (error) throw new Error(error.message);
  for (const project of projects ?? []) {
    const link = await linkForObject(admin, userId, "project", project.id);
    const shouldPush = project.external_source !== "notion" && project.field_id === notionFieldId;
    if (!link) {
      if (project.external_source === "notion") {
        continue;
      }
      if (!shouldPush) {
        continue;
      }
      const properties = projectProperties(project);
      const page = await notionRequest<any>(token, "/pages", {
        method: "POST",
        body: JSON.stringify({ parent: { database_id: connection.projects_database_id }, properties }),
      });
      await upsertLink(admin, userId, connection.id, "project", project.id, page.id, page.last_edited_time, project.updated_at, "two_way");
      changed += 1;
    } else {
      if (project.external_source === "notion") {
        if (link.sync_direction !== "pull_only") {
          await upsertLink(admin, userId, connection.id, "project", project.id, link.notion_page_id, link.notion_last_edited_time, project.updated_at, "pull_only");
          changed += 1;
        }
        continue;
      }
      if (link.sync_direction === "two_way" && !shouldPush) {
        debugLog.push(`pushProjects: Project ${project.id} moved out of Notion scope; removing sync link without deleting Notion page`);
        await admin.from("notion_object_links").delete().eq("id", link.id);
        changed += 1;
        continue;
      }
      if (new Date(project.updated_at).getTime() > new Date(link.cuein_updated_at).getTime()) {
        try {
          const properties = projectProperties(project);
          const page = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, {
            method: "PATCH",
            body: JSON.stringify({ properties }),
          });
          await upsertLink(admin, userId, connection.id, "project", project.id, page.id, page.last_edited_time, project.updated_at, "two_way");
          changed += 1;
        } catch (e: any) {
          const errMsg = e.message || "";
          if (
            errMsg.includes("archived") ||
            errMsg.includes("404") ||
            errMsg.includes("object_not_found") ||
            errMsg.includes("validation_error")
          ) {
            console.warn(`Project page ${link.notion_page_id} is archived or deleted on Notion. Deleting local link and soft-deleting project ${project.id}.`, errMsg);
            await admin
              .from("notion_object_links")
              .delete()
              .eq("user_id", userId)
              .eq("object_kind", "project")
              .eq("cuein_object_id", project.id);
            const now = new Date().toISOString();
            await admin.from("projects").update({ deleted_at: now, updated_at: now }).eq("id", project.id);
          } else {
            throw e;
          }
        }
      }
    }
  }
  return changed;
}

type NotionSyncConflict = {
  kind: "task" | "project";
  cuein_id: string;
  source: "notion";
  remote_updated_at: string;
  local_updated_at: string;
  link_remote_updated_at: string | null;
  remote_snapshot?: Record<string, unknown>;
};

async function pushTasks(
  admin: any,
  token: string,
  userId: string,
  connection: any,
  debugLog: string[] = [],
  taskTargets?: string[],
  forceOverwriteTaskIDs: Set<string> = new Set(),
  conflicts: NotionSyncConflict[] = [],
) {
  const writeTarget = taskWriteTarget(connection);
  if (!writeTarget?.databaseId) return 0;
  let changed = 0;
  const notionFieldId = await notionFieldIdForUser(userId);

  let deletedTasksQuery = admin
    .from("tasks")
    .select("*")
    .eq("user_id", userId)
    .not("deleted_at", "is", null);
  if (taskTargets) deletedTasksQuery = deletedTasksQuery.in("id", taskTargets);
  const { data: deletedTasks, error: deletedTasksError } = await deletedTasksQuery;
  if (deletedTasksError) throw new Error(deletedTasksError.message);

  for (const task of deletedTasks ?? []) {
    const link = await linkForObject(admin, userId, "task", task.id);
    if (link) {
      const eligibility = await taskNotionEligibility(admin, userId, task, notionFieldId);
      if (link.sync_direction === "two_way" && task.external_source !== "notion" && eligibility.shouldPush) {
        try {
          debugLog.push(`pushTasks: Archiving deleted task page ${link.notion_page_id} in Notion`);
          await notionRequest<any>(token, `/pages/${link.notion_page_id}`, {
            method: "PATCH",
            body: JSON.stringify({ archived: true }),
          });
        } catch (e: any) {
          debugLog.push(`pushTasks: Failed to archive page ${link.notion_page_id} in Notion: ${e.message}`);
        }
      } else if (link.sync_direction === "two_way" && task.external_source !== "notion") {
        debugLog.push(`pushTasks: Deleted task ${task.id} is outside Notion scope; removing sync link without archiving Notion page`);
      }
      await admin.from("notion_object_links").delete().eq("id", link.id);
      changed += 1;
    }
  }

  let activeTasksQuery = admin
    .from("tasks")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (taskTargets) activeTasksQuery = activeTasksQuery.in("id", taskTargets);
  const { data: tasks, error } = await activeTasksQuery;
  if (error) throw new Error(error.message);
  for (const task of tasks ?? []) {
    const link = await linkForObject(admin, userId, "task", task.id);
    const eligibility = await taskNotionEligibility(admin, userId, task, notionFieldId);
    if (!link) {
      if (task.external_source === "notion") {
        continue;
      }
      if (!eligibility.shouldPush) {
        continue;
      }
      const projectLink = task.project_id ? await linkForObject(admin, userId, "project", task.project_id) : null;
      const properties = await taskPropertiesForTarget(token, task, projectLink?.notion_page_id ?? null, writeTarget);
      const page = await notionRequest<any>(token, "/pages", {
        method: "POST",
        body: JSON.stringify({ parent: { database_id: writeTarget.databaseId }, properties }),
      });
      await upsertLink(admin, userId, connection.id, "task", task.id, page.id, page.last_edited_time, task.updated_at, "two_way");
      changed += 1;
    } else {
      if (task.external_source === "notion" && link.sync_direction !== "pull_only") {
        await upsertLink(admin, userId, connection.id, "task", task.id, link.notion_page_id, link.notion_last_edited_time, task.updated_at, "pull_only");
        changed += 1;
        continue;
      }
      if (link.sync_direction === "two_way" && task.external_source !== "notion" && !eligibility.shouldPush) {
        debugLog.push(`pushTasks: Task ${task.id} moved out of Notion scope; removing sync link without deleting Notion page`);
        await admin.from("notion_object_links").delete().eq("id", link.id);
        changed += 1;
        continue;
      }
      if (new Date(task.updated_at).getTime() > new Date(link.cuein_updated_at).getTime()) {
        if (link.sync_direction === "pull_only") {
          try {
            const statusUpdated = await pushExternalTaskStatus(token, task, link);
            if (statusUpdated) {
              await upsertLink(
                admin,
                userId,
                connection.id,
                "task",
                task.id,
                link.notion_page_id,
                link.notion_last_edited_time,
                task.updated_at,
                "pull_only",
              );
              changed += 1;
            }
          } catch (e: any) {
            const errMsg = e.message || "";
            if (
              errMsg.includes("archived") ||
              errMsg.includes("404") ||
              errMsg.includes("object_not_found") ||
              errMsg.includes("validation_error")
            ) {
              console.warn(`Task page ${link.notion_page_id} is archived or deleted on Notion (pull_only). Deleting local link and soft-deleting task ${task.id}.`, errMsg);
              await admin
                .from("notion_object_links")
                .delete()
                .eq("user_id", userId)
                .eq("object_kind", "task")
                .eq("cuein_object_id", task.id);
              const now = new Date().toISOString();
              await admin.from("tasks").update({ deleted_at: now, updated_at: now }).eq("id", task.id);
            } else {
              throw e;
            }
          }
        } else {
          try {
            // 3-way conflict check: peek the page first; if Notion's
            // last_edited_time advanced past the link's recorded value, both
            // sides changed since last sync. Skip the PATCH and surface the
            // conflict to the client unless force-overwrite was requested.
            let conflictDetected = false;
            if (!forceOverwriteTaskIDs.has(task.id)) {
              try {
                const remotePage = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "GET" });
                const remoteEditedAt = remotePage?.last_edited_time
                  ? new Date(remotePage.last_edited_time).getTime()
                  : 0;
                const linkRemoteAt = link.notion_last_edited_time
                  ? new Date(link.notion_last_edited_time).getTime()
                  : 0;
                if (remoteEditedAt > linkRemoteAt) {
                  conflicts.push({
                    kind: "task",
                    cuein_id: task.id,
                    source: "notion",
                    remote_updated_at: remotePage.last_edited_time,
                    local_updated_at: task.updated_at,
                    link_remote_updated_at: link.notion_last_edited_time ?? null,
                    remote_snapshot: {
                      title: firstTitleProperty(remotePage.properties ?? {}),
                      properties: remotePage.properties ?? {},
                    },
                  });
                  conflictDetected = true;
                }
              } catch {
                // If the peek fails (e.g. transient 5xx), fall through to the
                // PATCH; failures there have their own archived/404 handling.
              }
            }
            if (conflictDetected) continue;

            const projectLink = task.project_id ? await linkForObject(admin, userId, "project", task.project_id) : null;
            const linkedTarget = await taskWriteTargetForLinkedPage(token, connection, link.notion_page_id);
            const properties = await taskPropertiesForTarget(token, task, projectLink?.notion_page_id ?? null, linkedTarget);
            const page = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, {
              method: "PATCH",
              body: JSON.stringify({ properties }),
            });
            await upsertLink(admin, userId, connection.id, "task", task.id, page.id, page.last_edited_time, task.updated_at, "two_way");
            changed += 1;
          } catch (e: any) {
            const errMsg = e.message || "";
            if (
              errMsg.includes("archived") ||
              errMsg.includes("404") ||
              errMsg.includes("object_not_found") ||
              errMsg.includes("validation_error")
            ) {
              console.warn(`Task page ${link.notion_page_id} is archived or deleted on Notion. Deleting local link and soft-deleting task ${task.id}.`, errMsg);
              await admin
                .from("notion_object_links")
                .delete()
                .eq("user_id", userId)
                .eq("object_kind", "task")
                .eq("cuein_object_id", task.id);
              const now = new Date().toISOString();
              await admin.from("tasks").update({ deleted_at: now, updated_at: now }).eq("id", task.id);
            } else {
              throw e;
            }
          }
        }
      }
    }
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
  const results: any[] = [];
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

async function safeQueryDatabase(
  admin: any,
  token: string,
  connection: any,
  column: "projects_database_id" | "tasks_database_id" | "external_tasks_database_id",
  debugLog: string[] = [],
) {
  const databaseId = connection[column];
  if (!databaseId) return null;
  try {
    return await queryDatabase(token, databaseId);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (isNotionInaccessibleError(message)) {
      debugLog.push(`safeQueryDatabase: ${column} ${databaseId} is inaccessible; clearing stale ID`);
      await clearConnectionDatabase(admin, connection, column);
      connection[column] = null;
      return null;
    }
    throw error;
  }
}

async function clearConnectionDatabase(
  admin: any,
  connection: any,
  column: "projects_database_id" | "tasks_database_id" | "external_tasks_database_id",
) {
  const payload: Record<string, any> = { [column]: null };
  if (column === "external_tasks_database_id") {
    payload.external_tasks_database_title = null;
    payload.external_tasks_property_map = null;
  }
  await admin
    .from("notion_connections")
    .update(payload)
    .eq("id", connection.id)
    .throwOnError();
}

function isNotionInaccessibleError(message: string) {
  return message.includes("Notion 404") ||
    message.includes("object_not_found") ||
    message.includes("restricted_resource") ||
    message.includes("Could not find database");
}

async function discoverSharedTaskSources(token: string, parentPageId: string, managedDatabaseIds: Set<string>) {
  const databases: Array<{ id: string; title: string }> = [];
  const pages: any[] = [];
  const databaseIds = new Set<string>();
  const pageIds = new Set<string>();

  const addDatabase = (id: string | null | undefined, title: string | null | undefined) => {
    if (!id || managedDatabaseIds.has(id) || databaseIds.has(id)) return;
    const cleanTitle = (title || "").trim();
    if (cleanTitle === "CueIn Tasks" || cleanTitle === "CueIn Projects") {
      console.log(`discoverSharedTaskSources: Ignoring CueIn managed database: ${cleanTitle} (${id})`);
      return;
    }
    databaseIds.add(id);
    databases.push({ id, title: title || "Notion database" });
  };

  const addPage = (page: any) => {
    if (!page?.id || pageIds.has(page.id) || page.id === parentPageId) return;
    pageIds.add(page.id);
    pages.push(page);
  };

  // Crawl depth 2 under parentPageId
  const queue: Array<{ id: string; depth: number }> = [{ id: parentPageId, depth: 0 }];
  const visited = new Set<string>();

  while (queue.length) {
    const current = queue.shift()!;
    if (visited.has(current.id) || current.depth > 1) continue;
    visited.add(current.id);

    try {
      const children = await listBlockChildren(token, current.id);
      for (const block of children) {
        if (block.archived) continue;
        if (block.type === "child_database" && block.id && !managedDatabaseIds.has(block.id)) {
          addDatabase(block.id, block.child_database?.title);
        } else if (block.type === "child_page" && block.id) {
          addPage({
            id: block.id,
            object: "page",
            last_edited_time: block.last_edited_time,
            parent: { type: "page_id", page_id: current.id },
            properties: {
              title: { title: [{ type: "text", text: { content: block.child_page?.title || "" }, plain_text: block.child_page?.title || "" }] },
            },
          });
          if (current.depth < 1) {
            queue.push({ id: block.id, depth: current.depth + 1 });
          }
        }
      }
    } catch (e) {
      console.error(`Failed to list block children for ${current.id}:`, e);
    }
  }

  try {
    for (const database of await searchNotionObjects(token, "database")) {
      addDatabase(database.id, notionTitleText(database.title));
    }
  } catch (error) {
    console.error("Failed to search Notion databases:", error);
  }

  try {
    for (const page of await searchNotionObjects(token, "page")) {
      const parentDatabaseId = page.parent?.type === "database_id" ? page.parent.database_id : null;
      if (!parentDatabaseId) addPage(page);
    }
  } catch (error) {
    console.error("Failed to search Notion pages:", error);
  }

  return { databases, pages };
}

async function searchNotionObjects(token: string, objectType: "database" | "page") {
  const results: any[] = [];
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
    start_cursor = response.has_more && results.length < 300 ? response.next_cursor : undefined;
  } while (start_cursor);
  return results;
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

async function ensureExternalTaskTarget(
  admin: any,
  token: string,
  userId: string,
  connection: any,
  debugLog: string[] = [],
) {
  if (connection.external_tasks_database_id && connection.external_tasks_property_map) {
    const database = await notionRequest<any>(token, `/databases/${connection.external_tasks_database_id}`, { method: "GET" }).catch(() => null);
    if (database?.properties) {
      const propertyMap = buildTaskPropertyMap(database.properties);
      await ensureCueInIDProperty(token, connection.external_tasks_database_id, database.properties, propertyMap).catch((error) => {
        debugLog.push(`ensureExternalTaskTarget: Could not add CueIn ID to ${connection.external_tasks_database_title ?? connection.external_tasks_database_id}: ${error instanceof Error ? error.message : String(error)}`);
      });
      const updated = await notionRequest<any>(token, `/databases/${connection.external_tasks_database_id}`, { method: "GET" }).catch(() => database);
      const refreshedMap = buildTaskPropertyMap(updated.properties ?? database.properties);
      await admin
        .from("notion_connections")
        .update({ external_tasks_property_map: refreshedMap })
        .eq("id", connection.id)
        .eq("user_id", userId)
        .throwOnError();
      connection.external_tasks_property_map = refreshedMap;
      return;
    }
    debugLog.push(`ensureExternalTaskTarget: External task database is inaccessible; clearing ${connection.external_tasks_database_id}`);
    await clearConnectionDatabase(admin, connection, "external_tasks_database_id");
    connection.external_tasks_database_id = null;
    connection.external_tasks_database_title = null;
    connection.external_tasks_property_map = null;
  }
  if (!connection.notion_parent_page_id) return;

  const sources = await discoverSharedTaskSources(token, connection.notion_parent_page_id, new Set([
    connection.projects_database_id,
    connection.tasks_database_id,
  ].filter(Boolean)));

  const candidates: Array<{ id: string; title: string; propertyMap: any; score: number }> = [];
  for (const source of sources.databases) {
    const database = await notionRequest<any>(token, `/databases/${source.id}`, { method: "GET" }).catch(() => null);
    if (!database?.properties) continue;
    const propertyMap = buildTaskPropertyMap(database.properties);
    const score = taskDatabaseScore(source.title, database.properties, propertyMap);
    if (score < 12) continue;

    await ensureCueInIDProperty(token, source.id, database.properties, propertyMap).catch((error) => {
      debugLog.push(`ensureExternalTaskTarget: Could not add CueIn ID to ${source.title}: ${error instanceof Error ? error.message : String(error)}`);
    });
    const updated = await notionRequest<any>(token, `/databases/${source.id}`, { method: "GET" }).catch(() => database);
    candidates.push({
      id: source.id,
      title: source.title,
      propertyMap: buildTaskPropertyMap(updated.properties ?? database.properties),
      score,
    });
  }

  candidates.sort((a, b) => b.score - a.score);
  const target = candidates[0] ?? null;
  if (!target) return;

  await admin
    .from("notion_connections")
    .update({
      external_tasks_database_id: target.id,
      external_tasks_database_title: target.title,
      external_tasks_property_map: target.propertyMap,
    })
    .eq("id", connection.id)
    .eq("user_id", userId)
    .throwOnError();

  connection.external_tasks_database_id = target.id;
  connection.external_tasks_database_title = target.title;
  connection.external_tasks_property_map = target.propertyMap;
  debugLog.push(`ensureExternalTaskTarget: Using external task database ${target.title} (${target.id})`);
}

async function isDatabaseValid(token: string, databaseId: string | null | undefined) {
  if (!databaseId) return false;
  try {
    const database = await notionRequest<any>(token, `/databases/${databaseId}`, { method: "GET" });
    return Boolean(database && !database.archived);
  } catch {
    return false;
  }
}

function taskWriteTarget(connection: any) {
  if (connection.external_tasks_database_id && connection.external_tasks_property_map) {
    return {
      databaseId: connection.external_tasks_database_id,
      propertyMap: connection.external_tasks_property_map,
      isManaged: false,
    };
  }
  return connection.tasks_database_id
    ? { databaseId: connection.tasks_database_id, propertyMap: null, isManaged: true }
    : null;
}

async function taskWriteTargetForLinkedPage(token: string, connection: any, notionPageId: string) {
  const page = await notionRequest<any>(token, `/pages/${notionPageId}`, { method: "GET" });
  const parentDatabaseId = page.parent?.type === "database_id" ? page.parent.database_id : null;
  if (
    parentDatabaseId &&
    parentDatabaseId === connection.external_tasks_database_id &&
    connection.external_tasks_property_map
  ) {
    return {
      databaseId: connection.external_tasks_database_id,
      propertyMap: connection.external_tasks_property_map,
      isManaged: false,
    };
  }
  return { databaseId: connection.tasks_database_id, propertyMap: null, isManaged: true };
}

async function taskPropertiesForTarget(token: string, task: any, projectPageId: string | null, target: any) {
  if (!target || target.isManaged || !target.propertyMap) {
    return taskProperties(task, projectPageId);
  }

  const database = await notionRequest<any>(token, `/databases/${target.databaseId}`, { method: "GET" });
  const map = buildTaskPropertyMap(database.properties ?? {});
  const properties: Record<string, any> = {};

  setMappedProperty(properties, map.title, titleProperty(task.title));
  setMappedProperty(properties, map.notes, richTextProperty(task.notes));
  setMappedProperty(properties, map.status, await mappedStatusProperty(token, target.databaseId, map, task.status));
  setMappedProperty(properties, map.priority, await mappedPriorityProperty(token, target.databaseId, map, task.priority));
  setMappedProperty(properties, map.tags, multiSelectProperty(task.tags));
  setMappedProperty(properties, map.scheduledDate, dateProperty(task.scheduled_date));
  setMappedProperty(properties, map.dueDate, dateProperty(task.due_date));
  setMappedProperty(properties, map.completedDate, dateProperty(task.completed_at));
  setMappedProperty(properties, map.cueInID, richTextProperty(task.id));
  return properties;
}

function setMappedProperty(properties: Record<string, any>, name: string | null | undefined, value: any) {
  if (name && value !== null && value !== undefined) properties[name] = value;
}

async function mappedStatusProperty(token: string, databaseId: string, map: any, cueInStatus: string) {
  if (!map.status) return null;
  const status = await externalStatusValue(token, databaseId, map.status, cueInStatus);
  if (!status) return null;
  return map.statusType === "status" ? { status: { name: status } } : selectProperty(status);
}

async function mappedPriorityProperty(token: string, databaseId: string, map: any, cueInPriority: string) {
  if (!map.priority) return null;
  const database = await notionRequest<any>(token, `/databases/${databaseId}`, { method: "GET" });
  const property = database.properties?.[map.priority];
  const options = property?.status?.options ?? property?.select?.options ?? [];
  const optionNames = options.map((option: any) => option?.name).filter(Boolean);
  const priority = bestPriorityOption(cueInPriority, optionNames);
  if (!priority) return null;
  return map.priorityType === "status" ? { status: { name: priority } } : selectProperty(priority);
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

async function softDeleteMissingTwoWayTasksForDatabase(
  admin: any,
  token: string,
  userId: string,
  connection: any,
  databaseId: string,
  activePageIds: Set<string>,
  debugLog: string[] = [],
) {
  const { data: links, error } = await admin
    .from("notion_object_links")
    .select("id, cuein_object_id, notion_page_id")
    .eq("connection_id", connection.id)
    .eq("object_kind", "task")
    .eq("sync_direction", "two_way");
  if (error) throw new Error(error.message);

  const missing: any[] = [];
  for (const link of links ?? []) {
    if (activePageIds.has(link.notion_page_id)) continue;
    try {
      const page = await notionRequest<any>(token, `/pages/${link.notion_page_id}`, { method: "GET" });
      const parentDatabaseId = page.parent?.type === "database_id" ? page.parent.database_id : null;
      if (page.archived || page.in_trash || parentDatabaseId === databaseId) {
        missing.push(link);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      if (message.includes("404") || message.includes("object_not_found") || message.includes("restricted_resource")) {
        missing.push(link);
      }
    }
  }

  if (missing.length === 0) return 0;

  const now = new Date().toISOString();
  debugLog.push(`pullSharedPageTasks: Soft-deleting ${missing.length} two-way tasks removed from external database ${databaseId}`);
  await admin
    .from("tasks")
    .update({ deleted_at: now, updated_at: now })
    .eq("user_id", userId)
    .in("id", missing.map((link: any) => link.cuein_object_id))
    .throwOnError();
  await admin
    .from("notion_object_links")
    .delete()
    .in("id", missing.map((link: any) => link.id))
    .throwOnError();

  return missing.length;
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
  const deterministicId = await notionFieldIdForUser(userId);
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

async function notionFieldIdForUser(userId: string) {
  return await deterministicUUID(`${userId}:field:notion`);
}

async function taskNotionEligibility(admin: any, userId: string, task: any, notionFieldId: string) {
  if (task.external_source === "notion") {
    return { shouldPush: false, reason: "notion-import" };
  }
  if (task.field_id === notionFieldId) {
    return { shouldPush: true, reason: "notion-field" };
  }
  if (!task.project_id) {
    return { shouldPush: false, reason: "inbox" };
  }

  const project = await one(admin
    .from("projects")
    .select("id, field_id, external_source, deleted_at")
    .eq("user_id", userId)
    .eq("id", task.project_id));
  if (!project || project.deleted_at) {
    return { shouldPush: false, reason: "missing-project" };
  }
  if (project.external_source === "notion") {
    return { shouldPush: true, reason: "notion-project" };
  }
  if (project.field_id === notionFieldId) {
    return { shouldPush: true, reason: "project-in-notion-field" };
  }
  return { shouldPush: false, reason: "non-notion-project" };
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
  // Mark the row as Notion-owned IF needed, capturing the bumped updated_at so
  // link.cuein_updated_at matches exactly. The previous implementation set
  // tasks.updated_at = now() *after* upserting the link with cuein_updated_at =
  // cueInUpdatedAt (the pre-bump value), causing a re-push loop on every sync.
  let resolvedCueInUpdatedAt = cueInUpdatedAt;
  if (kind === "task") {
    const { data: row } = await admin
      .from("tasks")
      .select("external_source, updated_at")
      .eq("id", cueInObjectId)
      .maybeSingle();
    if (row && row.external_source !== "notion") {
      const { data: bumped } = await admin
        .from("tasks")
        .update({ external_source: "notion" })
        .eq("id", cueInObjectId)
        .select("updated_at")
        .single();
      if (bumped?.updated_at) resolvedCueInUpdatedAt = bumped.updated_at;
    } else if (row?.updated_at) {
      resolvedCueInUpdatedAt = row.updated_at;
    }
  } else if (kind === "project") {
    const { data: row } = await admin
      .from("projects")
      .select("external_source, updated_at")
      .eq("id", cueInObjectId)
      .maybeSingle();
    if (row && row.external_source !== "notion") {
      const { data: bumped } = await admin
        .from("projects")
        .update({ external_source: "notion" })
        .eq("id", cueInObjectId)
        .select("updated_at")
        .single();
      if (bumped?.updated_at) resolvedCueInUpdatedAt = bumped.updated_at;
    } else if (row?.updated_at) {
      resolvedCueInUpdatedAt = row.updated_at;
    }
  }

  await admin.from("notion_object_links").upsert({
    user_id: userId,
    connection_id: connectionId,
    object_kind: kind,
    cuein_object_id: cueInObjectId,
    notion_page_id: notionPageId,
    notion_last_edited_time: notionLastEditedTime,
    cuein_updated_at: resolvedCueInUpdatedAt,
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

function bestPriorityOption(cueInPriority: string, optionNames: string[]) {
  const normalized = new Map(optionNames.map((name) => [normalizeStatusName(name), name]));
  const candidates = priorityCandidates(cueInPriority);
  for (const candidate of candidates) {
    const match = normalized.get(normalizeStatusName(candidate));
    if (match) return match;
  }
  return null;
}

function priorityCandidates(cueInPriority: string) {
  switch (cueInPriority) {
    case "urgent":
      return ["Urgent", "Critical", "P0", "Highest", "High"];
    case "high":
      return ["High", "Important", "P1", "Medium"];
    default:
      return ["Normal", "Medium", "Low", "None"];
  }
}
