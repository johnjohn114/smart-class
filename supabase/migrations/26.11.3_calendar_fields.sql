-- 26.11.3 行事曆欄位
-- 在 Supabase SQL Editor 執行一次即可。
alter table public.announcements
  add column if not exists event_date date,
  add column if not exists event_end_date date,
  add column if not exists event_date_source text,
  add column if not exists event_date_confirmed boolean not null default false;

alter table public.announcements
  drop constraint if exists announcements_event_date_source_check;
alter table public.announcements
  add constraint announcements_event_date_source_check
  check (event_date_source is null or event_date_source in ('manual','auto'));

alter table public.announcements
  drop constraint if exists announcements_event_date_range_check;
alter table public.announcements
  add constraint announcements_event_date_range_check
  check (event_end_date is null or event_date is null or event_end_date >= event_date);

create index if not exists announcements_calendar_event_date_idx
  on public.announcements (event_date)
  where published = true and event_date_confirmed = true;
