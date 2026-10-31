-- 事項公告區 App 更新中心
create extension if not exists pgcrypto;

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_name text not null,
  version_code integer not null,
  release_notes text not null default '',
  apk_url text not null,
  is_latest boolean not null default true,
  published boolean not null default true,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint app_releases_version_code_positive check (version_code > 0),
  constraint app_releases_apk_url_https check (apk_url ~ '^https://')
);

create index if not exists app_releases_published_idx
  on public.app_releases (published, is_latest, version_code desc, published_at desc);

alter table public.app_releases enable row level security;

create or replace function public.is_app_release_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

drop policy if exists "Published app releases are readable" on public.app_releases;
create policy "Published app releases are readable"
  on public.app_releases for select
  to anon, authenticated
  using (published = true);

drop policy if exists "Admins manage app releases" on public.app_releases;
create policy "Admins manage app releases"
  on public.app_releases for all
  to authenticated
  using (public.is_app_release_admin())
  with check (public.is_app_release_admin());

grant select on public.app_releases to anon, authenticated;
grant insert, update, delete on public.app_releases to authenticated;
grant execute on function public.is_app_release_admin() to authenticated;
