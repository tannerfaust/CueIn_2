-- CueIn Notion integration backend schema.
-- Tokens are encrypted by Edge Functions before they are stored here.

create table if not exists public.notion_oauth_states (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    state text not null unique,
    redirect_uri text not null,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '10 minutes'),
    consumed_at timestamptz
);

create table if not exists public.notion_connections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    workspace_id text not null,
    workspace_name text,
    bot_id text,
    owner_type text,
    owner_user_id text,
    encrypted_access_token text not null,
    token_nonce text not null,
    notion_parent_page_id text,
    projects_database_id text,
    tasks_database_id text,
    status text not null default 'active' check (status in ('active', 'disconnected', 'error')),
    last_error text,
    last_synced_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    disconnected_at timestamptz,
    sync_version bigint not null default 1,
    unique (user_id, workspace_id)
);

create table if not exists public.notion_object_links (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    connection_id uuid not null references public.notion_connections(id) on delete cascade,
    object_kind text not null check (object_kind in ('project', 'task')),
    cuein_object_id uuid not null,
    notion_page_id text not null,
    notion_last_edited_time timestamptz,
    cuein_updated_at timestamptz,
    last_synced_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    sync_version bigint not null default 1,
    unique (user_id, object_kind, cuein_object_id),
    unique (connection_id, object_kind, notion_page_id)
);

create table if not exists public.notion_sync_runs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    connection_id uuid references public.notion_connections(id) on delete set null,
    action text not null,
    status text not null check (status in ('running', 'succeeded', 'failed')),
    projects_pushed integer not null default 0,
    projects_pulled integer not null default 0,
    tasks_pushed integer not null default 0,
    tasks_pulled integer not null default 0,
    error text,
    created_at timestamptz not null default now(),
    finished_at timestamptz
);

create index if not exists notion_connections_user_status_idx
    on public.notion_connections(user_id, status);
create index if not exists notion_oauth_states_user_state_idx
    on public.notion_oauth_states(user_id, state);
create index if not exists notion_object_links_user_kind_idx
    on public.notion_object_links(user_id, object_kind);
create index if not exists notion_sync_runs_user_created_idx
    on public.notion_sync_runs(user_id, created_at desc);

alter table public.notion_oauth_states enable row level security;
alter table public.notion_connections enable row level security;
alter table public.notion_object_links enable row level security;
alter table public.notion_sync_runs enable row level security;

drop policy if exists "Notion OAuth states are user-owned" on public.notion_oauth_states;
create policy "Notion OAuth states are user-owned" on public.notion_oauth_states
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Notion connections are user-owned" on public.notion_connections;
create policy "Notion connections are user-owned" on public.notion_connections
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Notion object links are user-owned" on public.notion_object_links;
create policy "Notion object links are user-owned" on public.notion_object_links
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Notion sync runs are user-owned" on public.notion_sync_runs;
create policy "Notion sync runs are user-owned" on public.notion_sync_runs
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop trigger if exists touch_notion_connections_sync_metadata on public.notion_connections;
create trigger touch_notion_connections_sync_metadata before update on public.notion_connections
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_notion_object_links_sync_metadata on public.notion_object_links;
create trigger touch_notion_object_links_sync_metadata before update on public.notion_object_links
    for each row execute function public.touch_sync_metadata();

grant select, insert, update, delete on table public.notion_oauth_states to authenticated;
grant select, insert, update, delete on table public.notion_connections to authenticated;
grant select, insert, update, delete on table public.notion_object_links to authenticated;
grant select, insert on table public.notion_sync_runs to authenticated;
