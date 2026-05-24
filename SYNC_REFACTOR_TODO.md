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

- [ ] Linear webhook receiver edge function (`linear-webhook`). Linear has
  first-class webhooks. Subscribe on connect; tear down on disconnect. Webhook
  upserts the affected issue rows into Supabase, normal client pull picks them
  up.
- [ ] Linear team scope: stop pulling the entire org. Add a team picker in
  settings; persist `linear_connections.scope_team_ids text[]`. Filter
  `fetchAllIssues` / `fetchAllProjects` to those teams.
- [ ] Notion: collapse the three pull functions into a single delta query using
  `last_edited_time` filter against the configured DBs only. Workspace search
  is too lossy (300-result cap) to be the source of truth.
- [ ] Push-response pulls: when an integration push returns the freshly-written
  remote object, apply it locally directly (don't trigger a full
  `CueInSyncEngine.syncNow()` immediately afterward).

## Phase 6 — Engine + persistence cleanup

- [ ] Move `CueInSyncEngine` and `LocalSyncRepository` off `@MainActor` to a
  dedicated background actor; only the final `replaceFromSync` hop touches the
  main actor.
- [ ] Pull pagination on `SupabaseClient.fetch`: page through `updated_at >=`
  in chunks of 500 instead of unbounded.
- [ ] Replace remaining `try?` swallows in `CueInSyncEngine.applyCachedScheduleRecords`,
  `applyCachedLayoutSettings`, and `LocalSyncRepository.records`'s
  `compactMap { try? decode }` with logged-error variants.
- [ ] Server-side advisory lock per user in `notion-sync` and `linear-sync`
  bodies (Postgres `pg_try_advisory_xact_lock`) to prevent concurrent runs from
  the same user racing.
- [ ] Delete (real-delete) on Notion-imported task should mirror Linear:
  archive locally + push deletion/archive back to Notion. Today they're
  asymmetric (Notion archives locally only, Linear actually deletes).
- [ ] Tighten RLS so authenticated client cannot `SELECT
  encrypted_access_token` / `token_nonce` from `notion_connections` and
  `linear_connections`. Move secrets behind a view or strip them in policies.
- [ ] Lock CORS to known origins (`Access-Control-Allow-Origin: *` is currently
  used by `_shared/notion.ts` and `_shared/linear.ts`).
- [ ] Sync `taskListOrder` (currently local-only — preserved across pulls but
  not propagated cross-device).
- [ ] Wire client `syncVersion` properly: track server-returned `sync_version`
  and send it on update; let the server reject stale writes via
  `if-version-match` semantics.

## Notes on what was NOT changed in the first wave

- Server still scans full task tables on push; phase 3 fixes that.
- `TaskDetailSheet` still locks UI based only on `externalSource == "notion"`.
  A task in the Notion field without `externalSource` is editable in CueIn but
  pushed to Notion. Phase 3 should expose a unified `task.integrationOwner`
  computed from `external_source` + active `*_object_links` row, and use it
  for both UI lock and push gate.
- 5-minute polling stays. Webhooks land in phase 5.
