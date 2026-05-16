-- Grants required for signed-in app users to access RLS-protected tables.
-- RLS policies still restrict each user to their own rows.

grant usage on schema public to authenticated;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.fields to authenticated;
grant select, insert, update, delete on table public.projects to authenticated;
grant select, insert, update, delete on table public.tasks to authenticated;
grant select, insert, update, delete on table public.goals to authenticated;
grant select, insert, update, delete on table public.schedule_records to authenticated;
grant select, insert, update, delete on table public.app_layout_settings to authenticated;
grant select, insert, update, delete on table public.sync_mutations to authenticated;

