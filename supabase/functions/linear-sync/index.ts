import {
  adminClient,
  corsHeaders,
  decryptToken,
  isoDate,
  json,
  linearRequest,
  requireUser,
} from "../_shared/linear.ts";

type SyncAction = "full" | "push" | "pull";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = adminClient();
  let runId: string | null = null;
  let userId: string | null = null;
  const debugLog: string[] = [];

  try {
    const user = await requireUser(req, admin);
    userId = user.id;

    const { action = "full" } = await req.json().catch(() => ({})) as { action?: SyncAction };
    if (!["full", "push", "pull"].includes(action)) return json({ error: "Invalid sync action" }, 400);

    const { data: connection, error: connectionError } = await admin
      .from("linear_connections")
      .select("*")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (connectionError) return json({ error: connectionError.message }, 500);
    if (!connection) return json({ error: "Linear is not connected" }, 404);

    const { data: run, error: runError } = await admin
      .from("linear_sync_runs")
      .insert({ user_id: userId, connection_id: connection.id, action, status: "running" })
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

    // Get team info for fallback team ID
    const teamInfo = await linearRequest<{ teams: { nodes: Array<{ id: string }> } }>(token, `
      query {
        teams(first: 1) {
          nodes {
            id
          }
        }
      }
    `);
    const fallbackTeamId = teamInfo.teams?.nodes?.[0]?.id;
    if (!fallbackTeamId) {
      throw new Error("No Linear teams found in organization. Please create a team first.");
    }

    if (action === "full" || action === "pull") {
      counters.projects_pulled = await pullProjects(admin, token, userId, connection, debugLog);
      counters.tasks_pulled = await pullTasks(admin, token, userId, connection, debugLog);
    }
    if (action === "full" || action === "push") {
      counters.projects_pushed = await pushProjects(admin, token, userId, connection, fallbackTeamId, debugLog);
      counters.tasks_pushed = await pushTasks(admin, token, userId, connection, fallbackTeamId, debugLog);
    }

    const now = new Date().toISOString();
    await admin.from("linear_connections").update({
      last_synced_at: now,
      last_error: null,
    }).eq("id", connection.id);

    await admin.from("linear_sync_runs").update({
      ...counters,
      status: "succeeded",
      finished_at: now,
    }).eq("id", runId);

    return json({ ok: true, ...counters, last_synced_at: now }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    if (runId) {
      await admin.from("linear_sync_runs").update({
        status: "failed",
        error: message,
        finished_at: new Date().toISOString(),
      }).eq("id", runId);
    }
    if (userId) {
      const lowerMessage = message.toLowerCase();
      const isAuthError = lowerMessage.includes("401") ||
                          lowerMessage.includes("unauthorized") ||
                          lowerMessage.includes("not authenticated") ||
                          lowerMessage.includes("authentication error") ||
                          lowerMessage.includes("authentication required") ||
                          lowerMessage.includes("token is invalid");
      await admin.from("linear_connections").update({
        last_error: message,
        status: isAuthError ? "error" : "active",
      }).eq("user_id", userId);
    }
    if (error instanceof Response) return error;
    return json({ error: message }, 500);
  }
});

async function fetchAllProjects(token: string, debugLog: string[]) {
  debugLog.push("fetchAllProjects: Querying Linear projects");
  const list: any[] = [];
  let hasNextPage = true;
  let afterCursor: string | null = null;

  while (hasNextPage) {
    const query = `
      query($after: String) {
        projects(first: 100, after: $after) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            name
            description
            state
            targetDate
            updatedAt
          }
        }
      }
    `;
    const res = await linearRequest<{ projects: { nodes: any[]; pageInfo: { hasNextPage: boolean; endCursor?: string } } }>(
      token,
      query,
      afterCursor ? { after: afterCursor } : {},
    );
    const nodes = res.projects?.nodes ?? [];
    list.push(...nodes);
    hasNextPage = res.projects?.pageInfo?.hasNextPage ?? false;
    afterCursor = res.projects?.pageInfo?.endCursor ?? null;
  }
  debugLog.push(`fetchAllProjects: Retrieved ${list.length} total projects`);
  return list;
}

async function fetchAllIssues(token: string, debugLog: string[]) {
  debugLog.push("fetchAllIssues: Querying Linear issues");
  const list: any[] = [];
  let hasNextPage = true;
  let afterCursor: string | null = null;

  while (hasNextPage) {
    const query = `
      query($after: String) {
        issues(first: 100, after: $after) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            title
            description
            priority
            dueDate
            completedAt
            updatedAt
            state {
              id
              name
              type
            }
            project {
              id
            }
            labels {
              nodes {
                name
              }
            }
          }
        }
      }
    `;
    const res = await linearRequest<{ issues: { nodes: any[]; pageInfo: { hasNextPage: boolean; endCursor?: string } } }>(
      token,
      query,
      afterCursor ? { after: afterCursor } : {},
    );
    const nodes = res.issues?.nodes ?? [];
    list.push(...nodes);
    hasNextPage = res.issues?.pageInfo?.hasNextPage ?? false;
    afterCursor = res.issues?.pageInfo?.endCursor ?? null;
  }
  debugLog.push(`fetchAllIssues: Retrieved ${list.length} total issues`);
  return list;
}

async function pullProjects(admin: any, token: string, userId: string, connection: any, debugLog: string[]) {
  const projects = await fetchAllProjects(token, debugLog);
  const fieldId = await ensureLinearField(admin, userId);
  let changed = 0;

  for (const proj of projects) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("connection_id", connection.id)
      .eq("object_kind", "project")
      .eq("linear_id", proj.id)
      .maybeSingle();

    const localId = link?.cuein_object_id ?? crypto.randomUUID();
    const linearEdited = new Date(proj.updatedAt);

    if (link && linearEdited.getTime() <= new Date(link.linear_last_edited_time).getTime()) {
      continue;
    }

    const { data: existingLocal } = await admin
      .from("projects")
      .select("updated_at")
      .eq("id", localId)
      .maybeSingle();

    if (existingLocal && new Date(existingLocal.updated_at) > linearEdited) {
      continue;
    }

    const status = projectStatusFromLinear(proj.state);

    // Save project and retrieve database-generated updated_at to ensure link synchronization is precise
    const { data: savedProj } = await admin.from("projects").upsert({
      id: localId,
      user_id: userId,
      field_id: fieldId,
      name: proj.name || "Untitled Linear Project",
      summary: proj.description || "",
      status,
      target_date: isoDate(proj.targetDate),
      external_source: "linear",
      updated_at: proj.updatedAt,
    }, { onConflict: "id" }).select("updated_at").single();

    const storedUpdatedAt = savedProj?.updated_at || proj.updatedAt;

    await admin.from("linear_object_links").upsert({
      user_id: userId,
      connection_id: connection.id,
      object_kind: "project",
      cuein_object_id: localId,
      linear_id: proj.id,
      linear_last_edited_time: proj.updatedAt,
      cuein_updated_at: storedUpdatedAt,
      sync_direction: "two_way",
      last_synced_at: new Date().toISOString(),
    }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();

    changed++;
  }

  return changed;
}

async function pullTasks(admin: any, token: string, userId: string, connection: any, debugLog: string[]) {
  const issues = await fetchAllIssues(token, debugLog);
  const fieldId = await ensureLinearField(admin, userId);
  let changed = 0;

  for (const issue of issues) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("connection_id", connection.id)
      .eq("object_kind", "task")
      .eq("linear_id", issue.id)
      .maybeSingle();

    const localId = link?.cuein_object_id ?? crypto.randomUUID();
    const linearEdited = new Date(issue.updatedAt);

    if (link && linearEdited.getTime() <= new Date(link.linear_last_edited_time).getTime()) {
      continue;
    }

    const { data: existingLocal } = await admin
      .from("tasks")
      .select("updated_at, subtasks")
      .eq("id", localId)
      .maybeSingle();

    if (existingLocal && new Date(existingLocal.updated_at) > linearEdited) {
      continue;
    }

    const existingLocalSubtasks = existingLocal?.subtasks;

    let projectId: string | null = null;
    if (issue.project?.id) {
      const { data: projLink } = await admin
        .from("linear_object_links")
        .select("cuein_object_id")
        .eq("connection_id", connection.id)
        .eq("object_kind", "project")
        .eq("linear_id", issue.project.id)
        .maybeSingle();
      if (projLink) {
        projectId = projLink.cuein_object_id;
      }
    }

    const priority = priorityFromLinear(issue.priority);
    const status = statusFromLinear(issue.state?.type, issue.state?.name);
    const completedAt = status === "completed" ? isoDate(issue.completedAt || issue.updatedAt) : null;
    const tags = (issue.labels?.nodes ?? []).map((l: any) => l.name);

    // Save task and retrieve database-generated updated_at to ensure link synchronization is precise
    const { data: savedTask } = await admin.from("tasks").upsert({
      id: localId,
      user_id: userId,
      field_id: fieldId,
      project_id: projectId,
      title: issue.title || "Untitled Linear Task",
      notes: issue.description || "",
      tags,
      priority,
      status,
      completed_at: completedAt,
      due_date: isoDate(issue.dueDate),
      // Linear has no concept of subtasks the way CueIn does. Preserve any
      // existing local subtasks rather than blind-overwriting with [].
      ...(existingLocalSubtasks !== undefined ? { subtasks: existingLocalSubtasks } : {}),
      saves_to_archive: true,
      external_source: "linear",
      updated_at: issue.updatedAt,
    }, { onConflict: "id" }).select("updated_at").single();

    const storedUpdatedAt = savedTask?.updated_at || issue.updatedAt;

    await admin.from("linear_object_links").upsert({
      user_id: userId,
      connection_id: connection.id,
      object_kind: "task",
      cuein_object_id: localId,
      linear_id: issue.id,
      linear_last_edited_time: issue.updatedAt,
      cuein_updated_at: storedUpdatedAt,
      sync_direction: "two_way",
      last_synced_at: new Date().toISOString(),
    }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();

    changed++;
  }

  return changed;
}

async function pushProjects(admin: any, token: string, userId: string, connection: any, fallbackTeamId: string, debugLog: string[]) {
  const linearFieldId = await ensureLinearField(admin, userId);
  let changed = 0;

  // Handle deleted projects
  const { data: deletedProjects } = await admin
    .from("projects")
    .select("*")
    .eq("user_id", userId)
    .not("deleted_at", "is", null);

  for (const project of deletedProjects ?? []) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("user_id", userId)
      .eq("object_kind", "project")
      .eq("cuein_object_id", project.id)
      .maybeSingle();

    if (link) {
      try {
        debugLog.push(`pushProjects: Archiving/Cancelling project ${link.linear_id} in Linear`);
        const mutation = `
          mutation($id: String!, $input: ProjectUpdateInput!) {
            projectUpdate(id: $id, input: $input) {
              success
            }
          }
        `;
        await linearRequest(token, mutation, {
          id: link.linear_id,
          input: { state: "canceled" },
        });
      } catch (e: any) {
        debugLog.push(`pushProjects: Failed to cancel project ${link.linear_id} in Linear: ${e.message}`);
      }
      await admin.from("linear_object_links").delete().eq("id", link.id);
      changed++;
    }
  }

  // Handle active projects
  const { data: projects } = await admin
    .from("projects")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);

  for (const project of projects ?? []) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("user_id", userId)
      .eq("object_kind", "project")
      .eq("cuein_object_id", project.id)
      .maybeSingle();

    const isLinearScope = project.external_source === "linear" || project.field_id === linearFieldId;
    if (!isLinearScope) {
      if (link) {
        await admin.from("linear_object_links").delete().eq("id", link.id);
      }
      continue;
    }

    if (link) {
      const localUpdated = new Date(project.updated_at).getTime();
      const linkUpdated = link.cuein_updated_at ? new Date(link.cuein_updated_at).getTime() : 0;
      if (localUpdated <= linkUpdated) {
        continue;
      }
    }

    let state = projectStatusToLinear(project.status);
    if (link) {
      // Fetch current project state from Linear to avoid overriding backlog/planned statuses
      const current = await getLinearProjectState(token, link.linear_id);
      if (current) {
        const currentMappedStatus = projectStatusFromLinear(current.state);
        if (project.status === currentMappedStatus) {
          state = current.state;
        }
      }
    }

    if (!link) {
      // Create project in Linear
      const mutation = `
        mutation($input: ProjectCreateInput!) {
          projectCreate(input: $input) {
            success
            project {
              id
              updatedAt
            }
          }
        }
      `;
      const input = {
        name: project.name,
        description: project.summary,
        state,
        targetDate: project.target_date,
        teamIds: [fallbackTeamId],
      };
      const res = await linearRequest<{ projectCreate: { success: boolean; project: { id: string; updatedAt: string } } }>(token, mutation, { input });
      if (res.projectCreate?.success) {
        const linearProject = res.projectCreate.project;
        await admin.from("linear_object_links").upsert({
          user_id: userId,
          connection_id: connection.id,
          object_kind: "project",
          cuein_object_id: project.id,
          linear_id: linearProject.id,
          linear_last_edited_time: linearProject.updatedAt,
          cuein_updated_at: project.updated_at,
          sync_direction: "two_way",
          last_synced_at: new Date().toISOString(),
        }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();
        
        await admin.from("projects").update({
          external_source: "linear",
          updated_at: new Date().toISOString(),
        }).eq("id", project.id);

        changed++;
      }
    } else {
      // Update project in Linear
      const mutation = `
        mutation($id: String!, $input: ProjectUpdateInput!) {
          projectUpdate(id: $id, input: $input) {
            success
            project {
              id
              updatedAt
            }
          }
        }
      `;
      const input = {
        name: project.name,
        description: project.summary,
        state,
        targetDate: project.target_date,
      };
      const res = await linearRequest<{ projectUpdate: { success: boolean; project: { id: string; updatedAt: string } } }>(token, mutation, { id: link.linear_id, input });
      if (res.projectUpdate?.success) {
        const linearProject = res.projectUpdate.project;
        await admin.from("linear_object_links").update({
          linear_last_edited_time: linearProject.updatedAt,
          cuein_updated_at: project.updated_at,
          last_synced_at: new Date().toISOString(),
        }).eq("id", link.id).throwOnError();
        
        await admin.from("projects").update({
          external_source: "linear",
          updated_at: new Date().toISOString(),
        }).eq("id", project.id);

        changed++;
      }
    }
  }

  return changed;
}

async function pushTasks(admin: any, token: string, userId: string, connection: any, fallbackTeamId: string, debugLog: string[]) {
  const linearFieldId = await ensureLinearField(admin, userId);
  let changed = 0;
  const teamStatesCache = new Map<string, Array<{ id: string; name: string; type: string }>>();

  // Handle deleted tasks
  const { data: deletedTasks } = await admin
    .from("tasks")
    .select("*")
    .eq("user_id", userId)
    .not("deleted_at", "is", null);

  for (const task of deletedTasks ?? []) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("user_id", userId)
      .eq("object_kind", "task")
      .eq("cuein_object_id", task.id)
      .maybeSingle();

    if (link) {
      try {
        debugLog.push(`pushTasks: Cancelling issue ${link.linear_id} in Linear`);
        const details = await getIssueDetails(token, link.linear_id);
        const teamId = details?.teamId;
        const states = await getCachedWorkflowStates(token, teamId || fallbackTeamId, teamStatesCache);
        const cancelledState = states.find(s => s.type === "canceled");

        if (cancelledState) {
          const mutation = `
            mutation($id: String!, $input: IssueUpdateInput!) {
              issueUpdate(id: $id, input: $input) {
                success
              }
            }
          `;
          await linearRequest(token, mutation, {
            id: link.linear_id,
            input: { stateId: cancelledState.id },
          });
        }
      } catch (e: any) {
        debugLog.push(`pushTasks: Failed to cancel issue ${link.linear_id} in Linear: ${e.message}`);
      }
      await admin.from("linear_object_links").delete().eq("id", link.id);
      changed++;
    }
  }

  // Handle active tasks
  const { data: tasks } = await admin
    .from("tasks")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);

  for (const task of tasks ?? []) {
    const { data: link } = await admin
      .from("linear_object_links")
      .select("*")
      .eq("user_id", userId)
      .eq("object_kind", "task")
      .eq("cuein_object_id", task.id)
      .maybeSingle();

    let isLinearScope = task.field_id === linearFieldId;
    if (!isLinearScope && task.project_id) {
      const { data: project } = await admin
        .from("projects")
        .select("id, field_id, external_source")
        .eq("user_id", userId)
        .eq("id", task.project_id)
        .maybeSingle();
      if (project && (project.external_source === "linear" || project.field_id === linearFieldId)) {
        isLinearScope = true;
      }
    }
    if (task.external_source === "linear") {
      isLinearScope = true;
    }

    if (!isLinearScope) {
      if (link) {
        await admin.from("linear_object_links").delete().eq("id", link.id);
      }
      continue;
    }

    if (link) {
      const localUpdated = new Date(task.updated_at).getTime();
      const linkUpdated = link.cuein_updated_at ? new Date(link.cuein_updated_at).getTime() : 0;
      if (localUpdated <= linkUpdated) {
        continue;
      }
    }

    // Resolve project ID link
    let linearProjectId: string | null = null;
    let projectTeamId: string | null = null;
    if (task.project_id) {
      const { data: projLink } = await admin
        .from("linear_object_links")
        .select("linear_id")
        .eq("connection_id", connection.id)
        .eq("object_kind", "project")
        .eq("cuein_object_id", task.project_id)
        .maybeSingle();
      if (projLink) {
        linearProjectId = projLink.linear_id;
        try {
          projectTeamId = await getProjectTeamId(token, linearProjectId);
        } catch (e: any) {
          debugLog.push(`pushTasks: Failed to fetch team ID for project ${linearProjectId}: ${e.message}`);
        }
      }
    }

    // Fetch details of the issue if it already exists
    const issueDetails = link ? await getIssueDetails(token, link.linear_id) : null;

    // Determine the correct team ID for this issue:
    let targetTeamId = fallbackTeamId;
    if (projectTeamId) {
      targetTeamId = projectTeamId;
    } else if (issueDetails?.teamId) {
      targetTeamId = issueDetails.teamId;
    }

    // Fetch states and map status safely
    const priority = priorityToLinear(task.priority);
    const taskStates = await getCachedWorkflowStates(token, targetTeamId, teamStatesCache);
    
    let targetStateId = mapStatusToWorkflowState(task.status, taskStates)?.id;

    // If updating, preserve the exact state ID in Linear if the CueIn status category did not change
    if (task.status && issueDetails?.stateId && issueDetails?.stateType) {
      const currentMappedStatus = statusFromLinear(issueDetails.stateType);
      if (task.status === currentMappedStatus) {
        targetStateId = issueDetails.stateId;
      }
    }

    if (!link) {
      // Create issue in Linear
      const mutation = `
        mutation($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue {
              id
              updatedAt
            }
          }
        }
      `;
      const input: any = {
        title: task.title,
        description: task.notes,
        priority,
        teamId: targetTeamId,
        projectId: linearProjectId,
      };
      if (targetStateId) input.stateId = targetStateId;
      if (task.due_date) input.dueDate = task.due_date;

      const res = await linearRequest<{ issueCreate: { success: boolean; issue: { id: string; updatedAt: string } } }>(token, mutation, { input });
      if (res.issueCreate?.success) {
        const linearIssue = res.issueCreate.issue;
        // Mark the task as Linear-owned. The touch_sync_metadata() trigger will
        // bump updated_at; we capture the result so link.cuein_updated_at matches
        // exactly. Otherwise the next push sees task.updated_at > link.cuein_updated_at
        // and re-pushes a no-op forever (the spurious-loop bug).
        const { data: bumped } = await admin
          .from("tasks")
          .update({ external_source: "linear" })
          .eq("id", task.id)
          .select("updated_at")
          .single();
        const cueInUpdatedAt = bumped?.updated_at ?? task.updated_at;

        await admin.from("linear_object_links").upsert({
          user_id: userId,
          connection_id: connection.id,
          object_kind: "task",
          cuein_object_id: task.id,
          linear_id: linearIssue.id,
          linear_last_edited_time: linearIssue.updatedAt,
          cuein_updated_at: cueInUpdatedAt,
          sync_direction: "two_way",
          last_synced_at: new Date().toISOString(),
        }, { onConflict: "user_id,object_kind,cuein_object_id" }).throwOnError();

        changed++;
      }
    } else {
      // Update issue in Linear
      const mutation = `
        mutation($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) {
            success
            issue {
              id
              updatedAt
            }
          }
        }
      `;
      const input: any = {
        title: task.title,
        description: task.notes,
        priority,
        projectId: linearProjectId,
      };
      if (targetStateId) input.stateId = targetStateId;
      input.dueDate = task.due_date; // Clear or update

      const res = await linearRequest<{ issueUpdate: { success: boolean; issue: { id: string; updatedAt: string } } }>(token, mutation, { id: link.linear_id, input });
      if (res.issueUpdate?.success) {
        const linearIssue = res.issueUpdate.issue;
        // Existing-link update: do NOT touch the tasks row at all. external_source
        // is already "linear" from the original create, and any extra UPDATE here
        // would fire touch_sync_metadata() and create a re-push loop on next sync.
        await admin.from("linear_object_links").update({
          linear_last_edited_time: linearIssue.updatedAt,
          cuein_updated_at: task.updated_at,
          last_synced_at: new Date().toISOString(),
        }).eq("id", link.id).throwOnError();

        changed++;
      }
    }
  }

  return changed;
}

// Helpers

async function ensureLinearField(admin: any, userId: string) {
  const deterministicId = await linearFieldIdForUser(userId);
  const existing = await one(admin.from("fields").select("id").eq("user_id", userId).eq("id", deterministicId));
  if (existing) return existing.id;
  await admin.from("fields").upsert({
    id: deterministicId,
    user_id: userId,
    name: "Linear",
    summary: "Imported from Linear",
    icon_name: "app.fill",
    color_hex: 6178972, // Custom slate color hex
  }, { onConflict: "id" }).throwOnError();
  return deterministicId;
}

async function linearFieldIdForUser(userId: string) {
  return await deterministicUUID(`${userId}:field:linear`);
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

async function getWorkflowStates(token: string, teamId: string): Promise<Array<{ id: string; name: string; type: string }>> {
  const query = `
    query($teamId: String!) {
      team(id: $teamId) {
        states {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  `;
  const res = await linearRequest<{ team: { states: { nodes: any[] } } }>(token, query, { teamId });
  return res.team?.states?.nodes ?? [];
}

async function getCachedWorkflowStates(token: string, teamId: string, cache: Map<string, any[]>) {
  if (cache.has(teamId)) return cache.get(teamId)!;
  const states = await getWorkflowStates(token, teamId);
  cache.set(teamId, states);
  return states;
}

async function getIssueDetails(token: string, issueId: string): Promise<{ teamId: string; stateId: string; stateType: string } | null> {
  const query = `
    query($id: String!) {
      issue(id: $id) {
        team {
          id
        }
        state {
          id
          type
        }
      }
    }
  `;
  try {
    const res = await linearRequest<{ issue: { team: { id: string }; state: { id: string; type: string } } }>(token, query, { id: issueId });
    return {
      teamId: res.issue?.team?.id,
      stateId: res.issue?.state?.id,
      stateType: res.issue?.state?.type,
    };
  } catch {
    return null;
  }
}

async function getProjectTeamId(token: string, projectId: string): Promise<string | null> {
  const query = `
    query($id: String!) {
      project(id: $id) {
        teams {
          nodes {
            id
          }
        }
      }
    }
  `;
  const res = await linearRequest<{ project: { teams: { nodes: Array<{ id: string }> } } }>(token, query, { id: projectId });
  return res.project?.teams?.nodes?.[0]?.id ?? null;
}

async function getLinearProjectState(token: string, projectId: string): Promise<{ state: string; targetDate: string | null } | null> {
  const query = `
    query($id: String!) {
      project(id: $id) {
        state
        targetDate
      }
    }
  `;
  try {
    const res = await linearRequest<{ project: { state: string; targetDate: string | null } }>(token, query, { id: projectId });
    return res.project;
  } catch {
    return null;
  }
}

function projectStatusFromLinear(state: string) {
  if (!state) return "active";
  switch (state.toLowerCase()) {
    case "started":
      return "active";
    case "backlog":
    case "planned":
      return "active";
    case "completed":
      return "done";
    case "paused":
      return "paused";
    case "canceled":
    default:
      return "archived";
  }
}

function projectStatusToLinear(status: string) {
  if (!status) return "started";
  switch (status.toLowerCase()) {
    case "active":
      return "started";
    case "done":
      return "completed";
    case "paused":
      return "paused";
    case "archived":
    default:
      return "canceled";
  }
}

function priorityFromLinear(priority: number): string {
  if (priority === 1) return "urgent";
  if (priority === 2) return "high";
  return "normal";
}

function priorityToLinear(priority: string): number {
  if (priority === "urgent") return 1;
  if (priority === "high") return 2;
  return 3; // Medium/Normal
}

function statusFromLinear(type: string, name?: string): string {
  switch (type) {
    case "completed":
      return "completed";
    case "started":
      return "active";
    case "unstarted":
      return "scheduled";
    case "backlog":
      return "inbox";
    case "canceled":
      return "archived";
    default:
      return "inbox";
  }
}

function mapStatusToWorkflowState(status: string, states: Array<{ id: string; name: string; type: string }>) {
  let typeTarget = "unstarted";
  if (status === "completed") typeTarget = "completed";
  else if (status === "active") typeTarget = "started";
  else if (status === "paused") typeTarget = "started";
  else if (status === "inbox") typeTarget = "backlog";
  else if (status === "archived") typeTarget = "canceled";

  // First try exact match on type
  const matched = states.find(s => s.type === typeTarget);
  if (matched) return matched;

  // Fallback to name match
  if (status === "completed") {
    return states.find(s => s.name.toLowerCase() === "done" || s.type === "completed");
  }
  return states[0];
}
