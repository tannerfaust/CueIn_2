-- Stable identity for user-owned schedule records that are singletons per kind/date.
-- Required for upserting synced formula libraries without creating duplicate rows.

create unique index if not exists schedule_records_user_kind_date_unique
    on public.schedule_records(user_id, kind, record_date);

create index if not exists schedule_records_user_kind_idx
    on public.schedule_records(user_id, kind);
