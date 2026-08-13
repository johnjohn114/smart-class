-- 商業簡介網站：資料庫升級（可重複執行版）
-- 請在 Supabase SQL Editor 執行一次。

create extension if not exists pgcrypto;

-- 既有網站設定
create table if not exists public.site_settings (
  id integer primary key default 1,
  site_name text default '商業簡介', hero_title text default '商業簡介', hero_text text default '繽紛、活潑、充滿特色的專屬網站', hero_image text default '1000116817.jpg',
  about_title text default '✨ 商業簡介', about_subtitle text default '讓訪客快速了解你、你的品牌與網站', about1_title text default '🌟 我們是誰？', about1_text text default '在這裡介紹你的品牌、社群或作品。', about2_title text default '💫 我們的特色', about2_text text default '活潑的視覺設計、清楚的資訊分類與簡單方便的網站導覽。',
  features_title text default '⭐ 網站特色 ⭐', features_subtitle text default '用可愛的卡片展示你的內容',
  f1_title text default '角色／品牌', f1_text text default '放入角色、LOGO 或品牌介紹。', f2_title text default '精彩內容', f2_text text default '展示作品、活動或特色內容。', f3_title text default '活動挑戰', f3_text text default '放入活動、比賽或挑戰資訊。', f4_title text default '精彩企劃', f4_text text default '放置你的特色企劃與最新內容。',
  contact1 text default '📧 Email：example@email.com', contact2 text default '💬 社群：加入我們的社群', contact3 text default '📱 聯絡方式：請填入你的資訊',
  created_at timestamptz default now(), updated_at timestamptz default now()
);
insert into public.site_settings(id) values(1) on conflict(id) do nothing;

-- 使用者角色
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'visitor' check (role in ('admin','visitor')),
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

-- 公告
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(), title text not null, content text not null,
  date date default current_date, category text not null default '最新消息' check(category in ('最新消息','活動','蛋仔','Minecraft伺服器更新')),
  pinned boolean not null default false, published boolean not null default true,
  published_at timestamptz not null default now(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.announcements add column if not exists category text not null default '最新消息';
alter table public.announcements add column if not exists pinned boolean not null default false;
alter table public.announcements add column if not exists published_at timestamptz not null default now();
alter table public.announcements add column if not exists updated_at timestamptz not null default now();

-- 商品
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(), name text not null, category text, price numeric(12,2) not null default 0 check(price>=0),
  image_url text, description text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- 訪客帳號資料（真正的登入密碼仍由 Supabase Auth 管理，不會存進這張表）
create table if not exists public.visitor_accounts (
  id uuid primary key references auth.users(id) on delete cascade, email text not null unique, active boolean not null default true, created_at timestamptz not null default now()
);

-- 建立角色資料：
-- 已存在於 visitor_accounts 的使用者一定是 visitor；其他既有 Auth 使用者才預設為 admin。
insert into public.profiles(id, role)
select u.id, case when va.id is not null then 'visitor' else 'admin' end
from auth.users u
left join public.visitor_accounts va on va.id = u.id
on conflict (id) do update set role =
  case when exists (
    select 1 from public.visitor_accounts va2 where va2.id = public.profiles.id
  ) then 'visitor' else public.profiles.role end;

-- 客服
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject text not null, message text not null, status text not null default 'open' check(status in ('open','answered','closed')),
  admin_reply text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table public.site_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.announcements enable row level security;
alter table public.products enable row level security;
alter table public.visitor_accounts enable row level security;
alter table public.support_tickets enable row level security;

drop policy if exists site_public_read on public.site_settings;
drop policy if exists site_admin_update on public.site_settings;
create policy site_public_read on public.site_settings for select using(true);
create policy site_admin_update on public.site_settings for update to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists announcement_public_read on public.announcements;
drop policy if exists announcement_admin_all on public.announcements;
create policy announcement_public_read on public.announcements for select using(public.is_admin() or (published=true and published_at<=now()));
create policy announcement_admin_all on public.announcements for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists product_public_read on public.products;
drop policy if exists product_admin_all on public.products;
create policy product_public_read on public.products for select using(public.is_admin() or active=true);
create policy product_admin_all on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists visitor_admin_read on public.visitor_accounts;
create policy visitor_admin_read on public.visitor_accounts for select to authenticated using(public.is_admin());

drop policy if exists profile_self_read on public.profiles;
drop policy if exists profile_admin_all on public.profiles;
create policy profile_self_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_admin_all on public.profiles for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists ticket_owner_insert on public.support_tickets;
drop policy if exists ticket_owner_read on public.support_tickets;
drop policy if exists ticket_admin_all on public.support_tickets;
drop policy if exists ticket_admin_delete on public.support_tickets;
create policy ticket_owner_insert on public.support_tickets for insert to authenticated with check(user_id=auth.uid());
create policy ticket_owner_read on public.support_tickets for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy ticket_admin_all on public.support_tickets for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy ticket_admin_delete on public.support_tickets for delete to authenticated using(public.is_admin());

-- 將既有公告的分類／排程資料整理好
update public.announcements set category='最新消息' where category is null or category='';
update public.announcements set published_at=(date::timestamptz) where published_at is null;

-- 如果你的舊管理員不是唯一的 Auth 使用者，請在 SQL Editor 手動把真正管理員設為 admin，例如：
-- update public.profiles p set role='admin' from auth.users u where p.id=u.id and u.email='你的管理員Email';


-- 優惠券：每張優惠券綁定一位訪客，因此不同訪客的優惠券完全分開。
create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.visitor_accounts(id) on delete cascade,
  title text not null,
  description text,
  code text not null,
  discount text,
  expires_at timestamptz,
  used boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.coupons enable row level security;

drop policy if exists coupon_owner_read on public.coupons;
drop policy if exists coupon_admin_all on public.coupons;
create policy coupon_owner_read on public.coupons
  for select to authenticated
  using (user_id=auth.uid() or public.is_admin());

create policy coupon_admin_all on public.coupons
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create index if not exists coupons_user_id_idx on public.coupons(user_id);
create index if not exists coupons_expires_at_idx on public.coupons(expires_at);
