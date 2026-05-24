# Sync & Integrations Refactor — Roadmap

This file tracks the remaining work for the sync / Linear / Notion overhaul.
The first wave of fixes (per-record outbox, post-push loop, subtask preservation,
debug-log noise removal, missing `debug_log` migration, duplicate supabase tree
cleanup, `Field`/`Project.updatedAt` correctness, `taskListOrder` preservation)
landed in commit "sync: kill full-list pushes, post-push loops, and silent
correctness bugs". The phases below are not yet done.

## Phase 3 — Per-task integration push

Today, a single task edit kicks off a `linear-sync` / `notion-sync` edge function
that **scans the user's entire `tasks` table** server-side. The first wave only
debounced repeat invocations on the client; it did not change the server.

- [ ] Add an optional `targets: { task_ids?: string[]; project_ids?: string[] }`
  payload to both `linear-sync` and `notion-sync`. When present, the push pass
  iterates only those rows.
- [ ] When `targets` is provided and a task is no longer in scope (no Linear/
  Notion field, no integration project, no `external_source` of that integration,
  no existing link), unlink it (delete the `*_object_links` row) and skip — never
  push.
- [ ] Have `CueInSyncRuntimeBridge.triggerImmediatePush(forTask:)` collect the
  changed task IDs into a small per-integration set, debounce 600ms, then call
  the edge function with that set as `targets`.
- [ ] Keep the existing `action: "full"` behavior for the manual "Sync all" UI.

## Phase 4 — Conflict detection + resolution UI

Decision: **3-way diff with field-level merge**, surfaced as a sheet. (Same
pattern Things, Linear's own merge UI, and most modern sync apps use; familiar
and avoids data loss.)

- [ ] In `*_object_links`, add `last_seen_remote_version` (or store the last
  observed `notion_last_edited_time` / Linear `updatedAt`). Already partially
  present.
- [ ] Server detects conflict during push: if `link.cuein_updated_at` advanced
  *and* the remote `notion_last_edited_time` / Linear `updatedAt` advanced since
  `link.last_synced_at`, do **not** push. Return a `conflict` descriptor in the
  response: `{ task_id, local, remote, base }`.
- [ ] Client persists conflict on `TaskItem.conflictState` (new field), shows a
  banner in the row, and blocks further pushes for that task until resolved.
- [ ] Merge sheet: 3 columns (Yours / Theirs / Last synced) per field. Sensible
  defaults pre-selected: status & dates → newer timestamp wins; tags → union;
  title/notes → user picks.

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
