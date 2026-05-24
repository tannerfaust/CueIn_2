-- Allow CueIn to use a user-selected/existing Notion task database instead of
-- only the CueIn-managed Tasks database.

alter table public.notion_connections
    add column if not exists external_tasks_database_id text,
    add column if not exists external_tasks_database_title text,
    add column if not exists external_tasks_property_map jsonb;

create index if not exists notion_connections_external_tasks_database_idx
    on public.notion_connections(user_id, external_tasks_database_id)
    where external_tasks_database_id is not null;
