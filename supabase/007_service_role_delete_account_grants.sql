-- Grants required by the delete-account Edge Function.
-- RLS protects user access; the service_role is only used server-side by Edge Functions.

grant usage on schema public to service_role;

grant select, insert, update, delete on table public.profiles to service_role;
grant select, insert, update, delete on table public.fields to service_role;
grant select, insert, update, delete on table public.projects to service_role;
grant select, insert, update, delete on table public.tasks to service_role;
grant select, insert, update, delete on table public.goals to service_role;
grant select, insert, update, delete on table public.schedule_records to service_role;
grant select, insert, update, delete on table public.app_layout_settings to service_role;
grant select, insert, update, delete on table public.sync_mutations to service_role;
