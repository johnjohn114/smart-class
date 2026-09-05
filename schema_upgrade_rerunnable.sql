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
alter table public.announcements add column if not exists link_url text;
alter table public.announcements add column if not exists link_label text;

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


-- 達人榜：管理員建立比賽、輸入成績，確認後再公布。
create table if not exists public.competitions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'Minecraft' check(category in ('Minecraft','蛋仔')),
  event_date date,
  description text,
  published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 達人榜分類管理：Minecraft / 蛋仔為預設，可再新增、修改、刪除自訂分類。
create table if not exists public.competition_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table public.competition_categories enable row level security;
drop policy if exists competition_categories_admin_all on public.competition_categories;
create policy competition_categories_admin_all on public.competition_categories
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

insert into public.competition_categories(name)
values ('Minecraft'),('蛋仔')
on conflict (name) do nothing;

-- 既有 competitions 以前有固定 CHECK；移除後才能使用自訂分類。
alter table public.competitions drop constraint if exists competitions_category_check;

-- 將既有比賽中的非預設分類補進分類表。
insert into public.competition_categories(name)
select distinct category
from public.competitions
where category is not null
on conflict (name) do nothing;

create table if not exists public.competition_results (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  player_name text not null,
  place integer not null check(place > 0),
  score numeric(12,2),
  prize text,
  created_at timestamptz not null default now()
);

alter table public.competitions enable row level security;
alter table public.competition_results enable row level security;

drop policy if exists competition_public_read on public.competitions;
drop policy if exists competition_admin_all on public.competitions;
create policy competition_public_read on public.competitions
  for select using(public.is_admin() or (published=true and (published_at is null or published_at<=now())));
create policy competition_admin_all on public.competitions
  for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists competition_result_public_read on public.competition_results;
drop policy if exists competition_result_admin_all on public.competition_results;
create policy competition_result_public_read on public.competition_results
  for select using(
    public.is_admin() or exists(
      select 1 from public.competitions c
      where c.id=competition_results.competition_id
        and c.published=true
        and (c.published_at is null or c.published_at<=now())
    )
  );
create policy competition_result_admin_all on public.competition_results
  for all to authenticated using(public.is_admin()) with check(public.is_admin());

create index if not exists competitions_category_idx on public.competitions(category);
create index if not exists competitions_published_idx on public.competitions(published, published_at);
create index if not exists competition_results_competition_idx on public.competition_results(competition_id);
create index if not exists competition_results_place_idx on public.competition_results(competition_id, place);
-- 達人榜公布時間由資料庫自動決定，避免瀏覽器時區／前端時間造成未來時間。
create or replace function public.set_competition_publish_time()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
begin
  if NEW.published = true then
    NEW.published_at := now();
  else
    NEW.published_at := null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_competition_publish_time on public.competitions;
create trigger trg_competition_publish_time
before insert or update of published
on public.competitions
for each row execute function public.set_competition_publish_time();


-- 快速連結
create table if not exists public.quick_links (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  url text not null,
  icon text,
  sort_order integer not null default 1,
  visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.quick_links add column if not exists icon text;
alter table public.quick_links add column if not exists sort_order integer not null default 1;
alter table public.quick_links add column if not exists visible boolean not null default true;
alter table public.quick_links add column if not exists updated_at timestamptz not null default now();
alter table public.quick_links enable row level security;
drop policy if exists "quick_links_public_read" on public.quick_links;
create policy "quick_links_public_read" on public.quick_links
for select to public using (visible = true);
drop policy if exists "quick_links_admin_all" on public.quick_links;
create policy "quick_links_admin_all" on public.quick_links
for all to public using (is_admin()) with check (is_admin());



create index if not exists competition_categories_name_idx on public.competition_categories(name);


-- 「我的」會員中心升級：會員編號、暱稱、通知，以及比賽成績綁定會員
alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists member_no integer;
create unique index if not exists profiles_member_no_uidx on public.profiles(member_no) where member_no is not null;

create sequence if not exists public.member_no_seq;
-- 舊版 sequence 在失敗交易／回滾時可能留下空號，例如 007 後直接跳到 011。
-- 本版改用交易內可回滾的計數器：建立失敗會回滾，不會再消耗會員編號；刪除會員也不會讓編號被重用。
create table if not exists public.member_no_counter (
  id boolean primary key default true check(id=true),
  next_no integer not null,
  compacted boolean not null default false,
  repair_version integer not null default 0
);
alter table public.member_no_counter add column if not exists compacted boolean not null default false;
alter table public.member_no_counter add column if not exists repair_version integer not null default 0;
-- 計數器只供資料庫 trigger 使用，前台／一般登入使用者不可直接讀寫。
alter table public.member_no_counter enable row level security;
insert into public.member_no_counter(id,next_no,compacted,repair_version) values(true,1,false,0) on conflict(id) do nothing;

create or replace function public.assign_member_no_and_nickname()
returns trigger
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  mail text;
  assigned_no integer;
begin
  if NEW.role='visitor' then
    if NEW.member_no is null then
      update public.member_no_counter
        set next_no=next_no+1
        where id=true
        returning next_no-1 into assigned_no;
      NEW.member_no:=coalesce(assigned_no,1);
    end if;
    if nullif(trim(coalesce(NEW.nickname,'')),'') is null then
      select email into mail from auth.users where id=NEW.id;
      NEW.nickname:=coalesce(nullif(split_part(coalesce(mail,''),'@',1),''),'會員');
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_profiles_member_no on public.profiles;
create trigger trg_profiles_member_no
before insert on public.profiles
for each row execute function public.assign_member_no_and_nickname();

-- 修正：有些較早建立的訪客只有 Auth / visitor_accounts，沒有對應 profiles。
create or replace function public.ensure_visitor_profile()
returns trigger
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  insert into public.profiles(id,role)
  values(NEW.id,'visitor')
  on conflict(id) do update set role='visitor';
  return NEW;
end;
$$;

drop trigger if exists trg_visitor_accounts_profile on public.visitor_accounts;
create trigger trg_visitor_accounts_profile
after insert on public.visitor_accounts
for each row execute function public.ensure_visitor_profile();

-- 先補齊目前已存在、但缺少 profiles 的訪客。
insert into public.profiles(id,role)
select va.id,'visitor'
from public.visitor_accounts va
left join public.profiles p on p.id=va.id
where p.id is null
on conflict(id) do update set role='visitor';

-- 補齊既有訪客的暱稱。
update public.profiles p
set nickname=coalesce(nullif(trim(p.nickname),''),split_part(coalesce(u.email,''),'@',1),'會員')
from auth.users u
where p.id=u.id and p.role='visitor' and nullif(trim(coalesce(p.nickname,'')),'') is null;

-- 一次性修正舊版造成的空號：目前仍存在的訪客依建立時間整理成 001、002、003……。
-- repair_version=2 可避免之後重跑 SQL 時反覆重新編號。會員 UUID、比賽、優惠券、客服等資料關聯不變。
do $$
declare
  total integer;
  repair_ver integer;
begin
  select coalesce(repair_version,0) into repair_ver
  from public.member_no_counter where id=true;

  select count(*)::integer into total
  from public.profiles
  where role='visitor';

  if repair_ver < 2 then
    if total > 0 then
      -- 先暫時移到負數區間，避免 unique index 在交換編號時衝突。
      with temporary_numbers as (
        select id, (-1000000-row_number() over (order by created_at,id))::integer as temp_no
        from public.profiles
        where role='visitor'
      )
      update public.profiles p
        set member_no=t.temp_no
      from temporary_numbers t
      where p.id=t.id;

      with numbered as(
        select id,row_number() over(order by created_at,id)::integer as new_no
        from public.profiles
        where role='visitor'
      )
      update public.profiles p
        set member_no=n.new_no
      from numbered n
      where p.id=n.id;
    end if;

    update public.member_no_counter
      set next_no=coalesce((select max(member_no)+1 from public.profiles where role='visitor'),1),
          compacted=true,
          repair_version=2
      where id=true;
  else
    -- 正常重跑 SQL 時，只校正計數器，不重新整理既有會員編號。
    update public.member_no_counter
      set next_no=greatest(next_no,coalesce((select max(member_no)+1 from public.profiles where role='visitor'),1))
      where id=true;
  end if;
end $$;

-- 比賽成績可選擇綁定會員；既有資料維持可用。
alter table public.competition_results add column if not exists user_id uuid references auth.users(id) on delete set null;
create index if not exists competition_results_user_idx on public.competition_results(user_id);
drop policy if exists competition_result_public_read on public.competition_results;
create policy competition_result_public_read on public.competition_results
for select using(
  public.is_admin() or user_id=auth.uid() or exists(
    select 1 from public.competitions c
    where c.id=competition_results.competition_id
      and c.published=true
      and (c.published_at is null or c.published_at<=now())
  )
);

-- 我的通知
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  type text not null default '一般',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications add column if not exists type text not null default '一般';
alter table public.notifications add column if not exists read_at timestamptz;
alter table public.notifications enable row level security;
drop policy if exists notification_owner_read on public.notifications;
drop policy if exists notification_owner_update on public.notifications;
drop policy if exists notification_admin_all on public.notifications;
create policy notification_owner_read on public.notifications
for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy notification_owner_update on public.notifications
for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy notification_admin_all on public.notifications
for all to authenticated using(public.is_admin()) with check(public.is_admin());
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);
