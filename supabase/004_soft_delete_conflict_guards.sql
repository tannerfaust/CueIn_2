-- Prevent stale clients from resurrecting rows that were soft-deleted elsewhere.
-- CueIn currently has no explicit restore operation, so deletes are sticky.

create or replace function public.preserve_soft_delete()
returns trigger
language plpgsql
as $$
begin
    if old.deleted_at is not null and new.deleted_at is null then
        new.deleted_at = old.deleted_at;
    end if;
    return new;
end;
$$;

drop trigger if exists preserve_fields_soft_delete on public.fields;
create trigger preserve_fields_soft_delete before update on public.fields
    for each row execute function public.preserve_soft_delete();

drop trigger if exists preserve_projects_soft_delete on public.projects;
create trigger preserve_projects_soft_delete before update on public.projects
    for each row execute function public.preserve_soft_delete();

drop trigger if exists preserve_tasks_soft_delete on public.tasks;
create trigger preserve_tasks_soft_delete before update on public.tasks
    for each row execute function public.preserve_soft_delete();

drop trigger if exists preserve_goals_soft_delete on public.goals;
create trigger preserve_goals_soft_delete before update on public.goals
    for each row execute function public.preserve_soft_delete();

drop trigger if exists preserve_schedule_records_soft_delete on public.schedule_records;
create trigger preserve_schedule_records_soft_delete before update on public.schedule_records
    for each row execute function public.preserve_soft_delete();

drop trigger if exists preserve_app_layout_settings_soft_delete on public.app_layout_settings;
create trigger preserve_app_layout_settings_soft_delete before update on public.app_layout_settings
    for each row execute function public.preserve_soft_delete();
