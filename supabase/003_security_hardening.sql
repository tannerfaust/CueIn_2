-- Security hardening after the initial CueIn dev schema.
-- RLS still controls row ownership; these changes tighten role access,
-- relationship integrity, and profile creation.

revoke all on table public.profiles from anon;
revoke all on table public.fields from anon;
revoke all on table public.projects from anon;
revoke all on table public.tasks from anon;
revoke all on table public.goals from anon;
revoke all on table public.schedule_records from anon;
revoke all on table public.app_layout_settings from anon;
revoke all on table public.sync_mutations from anon;

alter table public.profiles force row level security;
alter table public.fields force row level security;
alter table public.projects force row level security;
alter table public.tasks force row level security;
alter table public.goals force row level security;
alter table public.schedule_records force row level security;
alter table public.app_layout_settings force row level security;
alter table public.sync_mutations force row level security;

drop policy if exists "Profiles are user-owned" on public.profiles;
create policy "Profiles are user-owned" on public.profiles
    for all to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

drop policy if exists "Fields are user-owned" on public.fields;
create policy "Fields are user-owned" on public.fields
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Projects are user-owned" on public.projects;
create policy "Projects are user-owned" on public.projects
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Tasks are user-owned" on public.tasks;
create policy "Tasks are user-owned" on public.tasks
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Goals are user-owned" on public.goals;
create policy "Goals are user-owned" on public.goals
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Schedules are user-owned" on public.schedule_records;
create policy "Schedules are user-owned" on public.schedule_records
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Layout settings are user-owned" on public.app_layout_settings;
create policy "Layout settings are user-owned" on public.app_layout_settings
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Sync mutations are user-owned" on public.sync_mutations;
create policy "Sync mutations are user-owned" on public.sync_mutations
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create unique index if not exists fields_user_id_id_unique on public.fields(user_id, id);
create unique index if not exists projects_user_id_id_unique on public.projects(user_id, id);

create index if not exists tasks_user_status_idx on public.tasks(user_id, status);
create index if not exists tasks_user_scheduled_date_idx on public.tasks(user_id, scheduled_date);
create index if not exists projects_user_field_idx on public.projects(user_id, field_id);
create index if not exists goals_user_status_idx on public.goals(user_id, status);

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'projects_user_field_owner_fk'
    ) then
        alter table public.projects
            add constraint projects_user_field_owner_fk
            foreign key (user_id, field_id)
            references public.fields(user_id, id)
            on delete set null;
    end if;

    if not exists (
        select 1 from pg_constraint where conname = 'tasks_user_field_owner_fk'
    ) then
        alter table public.tasks
            add constraint tasks_user_field_owner_fk
            foreign key (user_id, field_id)
            references public.fields(user_id, id)
            on delete set null;
    end if;

    if not exists (
        select 1 from pg_constraint where conname = 'tasks_user_project_owner_fk'
    ) then
        alter table public.tasks
            add constraint tasks_user_project_owner_fk
            foreign key (user_id, project_id)
            references public.projects(user_id, id)
            on delete set null;
    end if;
end $$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, display_name, avatar_url)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', new.email),
        new.raw_user_meta_data->>'avatar_url'
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists create_profile_after_auth_user_insert on auth.users;
create trigger create_profile_after_auth_user_insert
    after insert on auth.users
    for each row execute function public.create_profile_for_new_user();

insert into public.profiles (id, display_name, avatar_url)
select
    users.id,
    coalesce(users.raw_user_meta_data->>'full_name', users.email),
    users.raw_user_meta_data->>'avatar_url'
from auth.users
left join public.profiles on profiles.id = users.id
where profiles.id is null;
