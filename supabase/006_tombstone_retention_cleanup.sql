-- Hard-delete old soft-deleted records after the sync safety window.
-- Keep tombstones long enough for offline devices to learn about deletes,
-- then remove them so user data does not accumulate forever.

create extension if not exists pg_cron with schema extensions;

create or replace function public.delete_expired_tombstones(retention interval default interval '30 days')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.tasks
    where deleted_at is not null
      and deleted_at < now() - retention;

    delete from public.projects
    where deleted_at is not null
      and deleted_at < now() - retention;

    delete from public.fields
    where deleted_at is not null
      and deleted_at < now() - retention;

    delete from public.goals
    where deleted_at is not null
      and deleted_at < now() - retention;

    delete from public.schedule_records
    where deleted_at is not null
      and deleted_at < now() - retention;

    delete from public.app_layout_settings
    where deleted_at is not null
      and deleted_at < now() - retention;
end;
$$;

do $$
begin
    if not exists (
        select 1
        from cron.job
        where jobname = 'cuein-delete-expired-tombstones-daily'
    ) then
        perform cron.schedule(
            'cuein-delete-expired-tombstones-daily',
            '17 3 * * *',
            $cron$select public.delete_expired_tombstones(interval '30 days');$cron$
        );
    end if;
end $$;
