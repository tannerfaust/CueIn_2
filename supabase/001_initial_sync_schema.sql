-- CueIn v1 backend schema for Supabase.
-- Run this in the Supabase SQL editor or as the first migration.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    avatar_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.fields (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    summary text not null default '',
    icon_name text not null default 'square.grid.2x2.fill',
    color_hex bigint not null default 9342609,
    is_archived boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.projects (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    field_id uuid references public.fields(id) on delete set null,
    name text not null,
    summary text not null default '',
    icon_name text not null default 'folder.fill',
    status text not null default 'active',
    target_date timestamptz,
    color_hex_override bigint,
    external_source text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.tasks (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    field_id uuid references public.fields(id) on delete set null,
    project_id uuid references public.projects(id) on delete set null,
    title text not null,
    notes text not null default '',
    tags jsonb not null default '[]'::jsonb,
    execution_type text,
    estimated_minutes integer,
    priority text not null default 'normal',
    scheduled_date timestamptz,
    due_date timestamptz,
    recurrence text not null default 'none',
    status text not null default 'inbox',
    completed_at timestamptz,
    subtasks jsonb not null default '[]'::jsonb,
    saves_to_archive boolean not null default true,
    external_source text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.goals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    why text not null default '',
    success_metric text not null default '',
    notes text not null default '',
    icon_name text not null default 'target',
    color_hex bigint not null default 3450713,
    status text not null default 'active',
    target_date timestamptz,
    stages jsonb not null default '[]'::jsonb,
    canvas jsonb not null default '{}'::jsonb,
    review_entries jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.schedule_records (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    kind text not null,
    record_date date,
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1
);

create table if not exists public.app_layout_settings (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    key text not null,
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    unique (user_id, key)
);

create table if not exists public.sync_mutations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    table_name text not null,
    record_id uuid not null,
    operation text not null,
    payload jsonb,
    created_at timestamptz not null default now(),
    applied_at timestamptz
);

create index if not exists fields_user_updated_idx on public.fields(user_id, updated_at);
create index if not exists projects_user_updated_idx on public.projects(user_id, updated_at);
create index if not exists tasks_user_updated_idx on public.tasks(user_id, updated_at);
create index if not exists goals_user_updated_idx on public.goals(user_id, updated_at);
create index if not exists schedule_records_user_updated_idx on public.schedule_records(user_id, updated_at);
create index if not exists app_layout_settings_user_updated_idx on public.app_layout_settings(user_id, updated_at);

alter table public.profiles enable row level security;
alter table public.fields enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.goals enable row level security;
alter table public.schedule_records enable row level security;
alter table public.app_layout_settings enable row level security;
alter table public.sync_mutations enable row level security;

drop policy if exists "Profiles are user-owned" on public.profiles;
create policy "Profiles are user-owned" on public.profiles
    for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Fields are user-owned" on public.fields;
create policy "Fields are user-owned" on public.fields
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Projects are user-owned" on public.projects;
create policy "Projects are user-owned" on public.projects
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Tasks are user-owned" on public.tasks;
create policy "Tasks are user-owned" on public.tasks
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Goals are user-owned" on public.goals;
create policy "Goals are user-owned" on public.goals
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Schedules are user-owned" on public.schedule_records;
create policy "Schedules are user-owned" on public.schedule_records
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Layout settings are user-owned" on public.app_layout_settings;
create policy "Layout settings are user-owned" on public.app_layout_settings
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Sync mutations are user-owned" on public.sync_mutations;
create policy "Sync mutations are user-owned" on public.sync_mutations
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.touch_sync_metadata()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    new.sync_version = coalesce(old.sync_version, 0) + 1;
    return new;
end;
$$;

drop trigger if exists touch_fields_sync_metadata on public.fields;
create trigger touch_fields_sync_metadata before update on public.fields
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_projects_sync_metadata on public.projects;
create trigger touch_projects_sync_metadata before update on public.projects
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_tasks_sync_metadata on public.tasks;
create trigger touch_tasks_sync_metadata before update on public.tasks
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_goals_sync_metadata on public.goals;
create trigger touch_goals_sync_metadata before update on public.goals
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_schedule_records_sync_metadata on public.schedule_records;
create trigger touch_schedule_records_sync_metadata before update on public.schedule_records
    for each row execute function public.touch_sync_metadata();

drop trigger if exists touch_app_layout_settings_sync_metadata on public.app_layout_settings;
create trigger touch_app_layout_settings_sync_metadata before update on public.app_layout_settings
    for each row execute function public.touch_sync_metadata();

grant usage on schema public to authenticated;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.fields to authenticated;
grant select, insert, update, delete on table public.projects to authenticated;
grant select, insert, update, delete on table public.tasks to authenticated;
grant select, insert, update, delete on table public.goals to authenticated;
grant select, insert, update, delete on table public.schedule_records to authenticated;
grant select, insert, update, delete on table public.app_layout_settings to authenticated;
grant select, insert, update, delete on table public.sync_mutations to authenticated;
