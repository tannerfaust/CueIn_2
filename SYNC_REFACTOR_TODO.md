# Sync & Integrations Refactor — Roadmap

This file tracks the remaining work for the sync / Linear / Notion overhaul.
The first wave of fixes (per-record outbox, post-push loop, subtask preservation,
debug-log noise removal, missing `debug_log` migration, duplicate supabase tree
cleanup, `Field`/`Project.updatedAt` correctness, `taskListOrder` preservation)
landed in commit "sync: kill full-list pushes, post-push loops, and silent
correctness bugs". The phases below are not yet done.

## Phase 3 — Per-task integration push  ✅ DONE

`linear-sync` and `notion-sync` now accept
`targets: { task_ids, project_ids, force_overwrite_task_ids }`. The client
collects affected ids per integration on every CRUD mutation and sends a
targeted push instead of a full-table scan. Manual "Sync all" still scans
(omit `targets`). Out-of-scope tasks are unlinked rather than pushed.

## Phase 4 — Conflict detection + resolution UI  ✅ MVP DONE

3-way conflict detection landed for Linear + Notion task push paths:
- Linear `pushTasks` (existing-link update path) reads the issue's current
  `updatedAt` from Linear and, if it advanced past `link.linear_last_edited_time`
  while the local task also advanced past `link.cuein_updated_at`, emits a
  `SyncConflict` and skips the push.
- Notion `pushTasks` (two-way path) does the same with a `GET /pages/{id}`
  peek before the `PATCH`.
- The client (`TasksStore.taskConflicts`) ingests the server's `conflicts`
  array, shows a banner pinned at the top of `TasksView`, and presents a
  resolution sheet with two actions: **Keep mine** (force-overwrites, server
  bypasses the conflict check via `force_overwrite_task_ids`) or **Use Linear /
  Use Notion** (pulls remote, drops local edit).

Follow-ups (not in MVP):
- [ ] Project conflict detection (currently tasks only).
- [ ] Field-level merge sheet (3 columns: Yours / Theirs / Last synced) for
  power users who want to keep Linear's title but their own notes. The current
  Keep-Mine / Use-Theirs UX matches what most sync apps ship and was the
  decision rationale; revisit if telemetry shows users want more granularity.
- [ ] Surface conflict marker on the individual `TaskItemRow` (currently only
  the global banner indicates conflicts).
- [ ] Persist `taskConflicts` across app launches if it isn't already implicit
  via the next sync re-emitting them.

## Phase 5 — Live sync without polling spam

- [x] **Push-response no-op skip.** Both `NotionIntegrationStore` and
  `LinearIntegrationStore` now skip the trailing `CueInSyncEngine.syncNow()`
  when the edge function reports zero `tasks_pushed` / `projects_pushed` /
  `tasks_pulled` / `projects_pulled` and no conflicts — i.e. the common
  debounced-push case where the server saw nothing to do. Cuts the chatter
  on rapid CRUD bursts roughly in half.
- [ ] Linear webhook receiver edge function (`linear-webhook`). Deferred —
  needs production webhook secret + deployed URL configured before it can
  ship. Subscribe on connect; tear down on disconnect. Webhook upserts the
  affected issue rows into Supabase, normal client pull picks them up.
- [ ] Linear team scope: stop pulling the entire org. Add a team picker in
  settings; persist `linear_connections.scope_team_ids text[]`. Filter
  `fetchAllIssues` / `fetchAllProjects` to those teams. Deferred (UI work).
- [ ] Notion: collapse the three pull functions into a single delta query
  using `last_edited_time` filter against the configured DBs only. Deferred
  because the existing soft-delete reconciliation depends on seeing the
  full result set; needs to be split into "delta pull" + "periodic full
  reconciliation" before the filter can be enabled.
- [x] Inline push-response apply (partial): the no-op skip above eliminates
  most of the value of full inline-apply. Full inline-apply (server returns
  the written rows so client can `replaceFromSync` directly) deferred until
  it shows up as a real perf complaint.

## Phase 6 — Engine + persistence cleanup

- [x] **Server advisory lock per user.** `integration_sync_locks` table +
  `try_acquire_integration_sync_lock(user_id, provider, ttl)` /
  `release_integration_sync_lock(...)` stored procs. Both `notion-sync` and
  `linear-sync` acquire the lock at the top of their handler and release in
  a `finally`. Stale locks older than 4 minutes are stolen automatically so
  a crashed run can't permanently wedge subsequent attempts.
- [x] **Pull pagination on `SupabaseClient.fetch`.** 500-row pages ordered
  by `(updated_at, id)`, drained until a short page is returned. Defensive
  50k-row cap with a logged warning. Pre-fix users with large workspaces
  silently lost rows past Supabase's default 1000-row response cap.
- [x] **Replaced `try?` swallows** in `CueInSyncEngine.applyCachedScheduleRecords`,
  `applyCachedLayoutSettings`, and `LocalSyncRepository.records` with
  logged-error variants. Schema drift across an upgrade no longer takes the
  whole sync down silently — the bad row is logged and skipped, the next
  remote pull overwrites it.
- [x] **Tightened RLS / table grants on connections tables.** Migration 012
  revokes all authenticated grants on `notion_connections` and
  `linear_connections`. The iOS client never touched those tables directly
  (it goes through `notion-status` / `linear-status`), so this just closes
  the previous data leak: a stolen JWT could `SELECT encrypted_access_token,
  token_nonce` from those tables and decrypt offline.
- [x] **CORS locked to known origins.** `_shared/notion.ts` and
  `_shared/linear.ts` now reflect `INTEGRATION_ALLOWED_ORIGINS`
  (comma-separated env override) or fall back to the production marketing
  origins. Native iOS callers don't send `Origin` and are unaffected.
- [x] **Symmetric Notion delete.** Already wired in `notion-sync`
  `pushTasks`: a soft-deleted CueIn task with a `two_way` link archives
  the underlying Notion page (PATCH `archived: true`) before deleting the
  link row. Linear's parallel path cancels the issue.
- [ ] Move `CueInSyncEngine` and `LocalSyncRepository` off `@MainActor`.
  Deferred: profiling didn't show this as a current bottleneck; refactor is
  invasive and risk-heavy without a real perf complaint.
- [ ] Sync `taskListOrder` cross-device. Deferred (local-only is fine for
  single-device users; multi-device sync wants a per-list version vector).
- [ ] Wire client `syncVersion` properly. Deferred (current LWW + 3-way
  conflict detection covers the data-loss cases).

## Phase 4 follow-ups

- [x] **Persist `taskConflicts` across app launches.** `TasksStore.taskConflicts`
  is now backed by `UserDefaults` (`cuein.tasksstore.taskConflicts.v1`) via a
  `didSet` writer + `loadPersistedConflicts()` initializer. A user who closes
  the app before resolving still sees the banner on relaunch.
- [ ] Surface conflict marker on the individual `TaskItemRow` (currently only
  the global banner indicates conflicts). Deferred (UI work, low blast radius).
- [ ] Project conflict detection (currently tasks only).
- [ ] Field-level merge sheet (3 columns: Yours / Theirs / Last synced).

## Notes on what was NOT changed in the first wave

- Server still scans full task tables on push; phase 3 fixes that.
- `TaskDetailSheet` still locks UI based only on `externalSource == "notion"`.
  A task in the Notion field without `externalSource` is editable in CueIn but
  pushed to Notion. Phase 3 should expose a unified `task.integrationOwner`
  computed from `external_source` + active `*_object_links` row, and use it
  for both UI lock and push gate.
- 5-minute polling stays. Webhooks land in phase 5.
