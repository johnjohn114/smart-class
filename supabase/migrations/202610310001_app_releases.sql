-- 事項公告區 App 更新中心
-- 在 Supabase Dashboard > SQL Editor 執行一次。
create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_code integer not null unique check (version_code > 0),
  version_name text not null,
  release_notes text not null default '',
  apk_url text not null,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  created_by uuid references auth.users(id)
);
alter table public.app_releases enable row level security;
drop policy if exists "Public can read published app releases" on public.app_releases;
create policy "Public can read published app releases" on public.app_releases
  for select to anon, authenticated using (published = true);
drop policy if exists "Admins can read all app releases" on public.app_releases;
create policy "Admins can read all app releases" on public.app_releases
  for select to authenticated using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
drop policy if exists "Admins can insert app releases" on public.app_releases;
create policy "Admins can insert app releases" on public.app_releases
  for insert to authenticated with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    and (created_by is null or created_by = auth.uid())
  );
drop policy if exists "Admins can update app releases" on public.app_releases;
create policy "Admins can update app releases" on public.app_releases
  for update to authenticated using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  ) with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
drop policy if exists "Admins can delete app releases" on public.app_releases;
create policy "Admins can delete app releases" on public.app_releases
  for delete to authenticated using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
grant select on public.app_releases to anon, authenticated;
grant insert, update, delete on public.app_releases to authenticated;
