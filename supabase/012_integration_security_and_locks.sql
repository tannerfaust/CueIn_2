-- 012_integration_security_and_locks.sql
--
-- Production reliability + security hardening for the integration layer.
--
-- 1. The iOS client never reads `notion_connections` or `linear_connections`
--    directly — it goes through `notion-status` / `linear-status` edge
--    functions. The previous grants exposed `encrypted_access_token` and
--    `token_nonce` to anyone holding the user's JWT (token theft escalates
--    to full Notion/Linear workspace takeover). Revoke direct authenticated
--    access; edge functions use the service role and are unaffected.
--
-- 2. Per-user advisory lock table for the sync edge functions. When two
--    invocations race (rapid client retry, scheduled poll + user click),
--    they used to read the same `cuein_updated_at` and double-push, leading
--    to duplicated Notion pages and noisy Linear updates. The lock table
--    serializes per-(user, provider) at the database level, with TTL-based
--    cleanup so a crashed function doesn't permanently hold the lock.
--
-- 3. Index Notion link tables on `notion_last_edited_time` to support the
--    upcoming delta-only pull (filter pages whose
--    `last_edited_time > max(notion_last_edited_time)`).
--
-- Idempotent: safe to re-run.

-- 1. Lock secrets behind edge functions. -------------------------------------

revoke all on table public.notion_connections from authenticated;
revoke all on table public.linear_connections from authenticated;

-- Edge functions still need these (they run with the service role).
grant select, insert, update, delete on table public.notion_connections to service_role;
grant select, insert, update, delete on table public.linear_connections to service_role;

-- 2. Per-user, per-provider sync lock. ---------------------------------------

create table if not exists public.integration_sync_locks (
    user_id uuid not null references auth.users(id) on delete cascade,
    provider text not null check (provider in ('notion', 'linear')),
    acquired_at timestamptz not null default now(),
    primary key (user_id, provider)
);

alter table public.integration_sync_locks enable row level security;

-- Only the service role touches this table; the client never sees it.
revoke all on table public.integration_sync_locks from authenticated;
grant select, insert, update, delete on table public.integration_sync_locks to service_role;

-- Atomic try-acquire. Returns true if the caller now holds the lock for
-- (user_id, provider). Stale locks older than `ttl` are stolen automatically
-- so a crashed run can't deadlock subsequent attempts.
create or replace function public.try_acquire_integration_sync_lock(
    p_user_id uuid,
    p_provider text,
    p_ttl interval default interval '4 minutes'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_acquired boolean := false;
begin
    -- Steal stale locks before attempting acquire.
    delete from public.integration_sync_locks
    where user_id = p_user_id
      and provider = p_provider
      and acquired_at < now() - p_ttl;

    insert into public.integration_sync_locks (user_id, provider)
    values (p_user_id, p_provider)
    on conflict do nothing
    returning true into v_acquired;

    return coalesce(v_acquired, false);
end;
$$;

create or replace function public.release_integration_sync_lock(
    p_user_id uuid,
    p_provider text
) returns void
language sql
security definer
set search_path = public
as $$
    delete from public.integration_sync_locks
    where user_id = p_user_id and provider = p_provider;
$$;

revoke all on function public.try_acquire_integration_sync_lock(uuid, text, interval) from public;
revoke all on function public.release_integration_sync_lock(uuid, text) from public;
grant execute on function public.try_acquire_integration_sync_lock(uuid, text, interval) to service_role;
grant execute on function public.release_integration_sync_lock(uuid, text) to service_role;

-- 3. Indexes for delta-only pulls. -------------------------------------------

create index if not exists notion_object_links_user_kind_edited_idx
    on public.notion_object_links (user_id, object_kind, notion_last_edited_time desc);

create index if not exists linear_object_links_user_kind_edited_idx
    on public.linear_object_links (user_id, object_kind, linear_last_edited_time desc);
