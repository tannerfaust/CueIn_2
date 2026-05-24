-- 011_sync_hardening.sql
--
-- Backfills schema gaps that were silently being written by edge functions:
--   * notion-sync and linear-sync write debug_log on the *_sync_runs rows
--     for forensic reasons, but the column was never declared. Without it
--     the UPDATE silently drops the field on some Postgres configurations
--     and errors on others. This migration adds the column.
--
-- Idempotent: safe to re-run.

alter table if exists public.notion_sync_runs
    add column if not exists debug_log jsonb;

alter table if exists public.linear_sync_runs
    add column if not exists debug_log jsonb;

-- Index on user_id + finished_at for the runs tables so support tooling can
-- pull recent failures fast without table scans.
create index if not exists notion_sync_runs_user_finished_idx
    on public.notion_sync_runs (user_id, finished_at desc);

create index if not exists linear_sync_runs_user_finished_idx
    on public.linear_sync_runs (user_id, finished_at desc);
