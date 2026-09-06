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
alter table public.announcements add column if not exists popup_enabled boolean not null default false;
alter table public.announcements add column if not exists popup_mode text not null default 'once';
alter table public.announcements add column if not exists popup_start_at timestamptz;
alter table public.announcements add column if not exists popup_end_at timestamptz;
update public.announcements set popup_start_at=published_at where popup_start_at is null and popup_enabled=true;
alter table public.announcements drop constraint if exists announcements_popup_mode_check;
alter table public.announcements add constraint announcements_popup_mode_check check (popup_mode in ('once','every_visit'));

create table if not exists public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id,user_id)
);
alter table public.announcement_reads enable row level security;
drop policy if exists announcement_read_owner_select on public.announcement_reads;
drop policy if exists announcement_read_owner_insert on public.announcement_reads;
create policy announcement_read_owner_select on public.announcement_reads for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy announcement_read_owner_insert on public.announcement_reads for insert to authenticated with check(user_id=auth.uid());
create index if not exists announcement_reads_user_idx on public.announcement_reads(user_id);


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
alter table public.support_tickets add column if not exists updated_at timestamptz not null default now();
alter table public.support_tickets add column if not exists status text;


alter table public.site_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.announcements enable row level security;
alter table public.products enable row level security;
alter table public.visitor_accounts enable row level security;

update public.support_tickets set status='open' where status is null;
alter table public.support_tickets drop constraint if exists support_tickets_status_check;
alter table public.support_tickets add constraint support_tickets_status_check check (status in ('open','answered','closed'));
create index if not exists support_tickets_status_idx on public.support_tickets(status);
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

-- 會員安全結案：會員只能將自己的客服案件標記為已結案，不能透過一般 UPDATE 改寫主旨、內容或管理員回覆。
create or replace function public.close_my_support_ticket(p_ticket_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.support_tickets
     set status='closed', updated_at=now()
   where id=p_ticket_id
     and user_id=auth.uid()
     and status <> 'closed';
  return found;
end;
$$;
revoke all on function public.close_my_support_ticket(uuid) from public;
grant execute on function public.close_my_support_ticket(uuid) to authenticated;


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
  parent_category text,
  created_at timestamptz not null default now()
);

-- 歷屆成績分類階層：既有自訂分類歸到「蛋仔派對」子選單；之後新建分類預設為最外層。
alter table public.competition_categories add column if not exists parent_category text;
update public.competition_categories
set parent_category='蛋仔'
where name not in ('Minecraft','蛋仔') and parent_category is null;

alter table public.competition_categories enable row level security;
drop policy if exists competition_categories_admin_all on public.competition_categories;
create policy competition_categories_admin_all on public.competition_categories
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

insert into public.competition_categories(name, parent_category)
values ('Minecraft',null),('蛋仔',null)
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
alter table public.notifications add column if not exists ticket_id uuid references public.support_tickets(id) on delete set null;
alter table public.notifications enable row level security;
drop policy if exists notification_owner_read on public.notifications;
drop policy if exists notification_owner_update on public.notifications;
drop policy if exists notification_owner_delete on public.notifications;
drop policy if exists notification_admin_all on public.notifications;
create policy notification_owner_read on public.notifications
for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy notification_owner_update on public.notifications
for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy notification_owner_delete on public.notifications
for delete to authenticated using(user_id=auth.uid());
create policy notification_admin_all on public.notifications
for all to authenticated using(public.is_admin()) with check(public.is_admin());
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);
create index if not exists notifications_ticket_idx on public.notifications(ticket_id);

-- #12 線上報名系統 v1
create table if not exists public.competition_registrations (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_no integer,
  nickname text not null,
  email text,
  note text,
  status text not null default 'active' check (status in ('active','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  custom_fields jsonb not null default '{}'::jsonb,
  unique (competition_id,user_id)
);

-- #13 線上報名進階：報名截止、名額、審核與自訂欄位
alter table public.competitions add column if not exists registration_deadline timestamptz;
alter table public.competitions add column if not exists registration_capacity integer;
alter table public.competitions add column if not exists registration_approval boolean not null default false;
alter table public.competitions add column if not exists registration_fields jsonb not null default '[]'::jsonb;
alter table public.competition_registrations add column if not exists custom_fields jsonb not null default '{}'::jsonb;
alter table public.competition_registrations drop constraint if exists competition_registrations_status_check;
alter table public.competition_registrations add constraint competition_registrations_status_check check (status in ('active','pending','approved','rejected','cancelled'));

create index if not exists competitions_registration_deadline_idx on public.competitions(registration_deadline);
create index if not exists competition_registrations_status_idx on public.competition_registrations(competition_id,status);

create or replace function public.check_competition_registration_rules()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  c public.competitions%rowtype;
  active_count integer;
  next_status text;
begin
  select * into c from public.competitions where id=new.competition_id;
  if c.id is null then raise exception '找不到活動／比賽'; end if;
  if new.status in ('cancelled','rejected') then return new; end if;
  if c.registration_deadline is not null and now() > c.registration_deadline then
    raise exception '報名已截止';
  end if;
  if c.registration_capacity is not null and c.registration_capacity > 0 then
    select count(*) into active_count from public.competition_registrations
      where competition_id=new.competition_id
        and user_id<>new.user_id
        and status in ('active','pending','approved');
    if active_count >= c.registration_capacity then raise exception '報名名額已滿'; end if;
  end if;
  next_status := case when c.registration_approval then 'pending' else 'approved' end;
  if tg_op='INSERT' then new.status := next_status; end if;
  if tg_op='UPDATE' and new.status='active' then new.status := next_status; end if;
  return new;
end; $$;

drop trigger if exists trg_check_competition_registration_rules on public.competition_registrations;
create trigger trg_check_competition_registration_rules
before insert or update on public.competition_registrations
for each row execute function public.check_competition_registration_rules();
alter table public.competition_registrations enable row level security;
drop policy if exists "competition_registrations_owner_select" on public.competition_registrations;
drop policy if exists "competition_registrations_owner_insert" on public.competition_registrations;
drop policy if exists "competition_registrations_owner_update" on public.competition_registrations;
drop policy if exists "competition_registrations_owner_delete" on public.competition_registrations;
drop policy if exists "competition_registrations_admin_all" on public.competition_registrations;
create policy "competition_registrations_owner_select" on public.competition_registrations for select to authenticated using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
create policy "competition_registrations_owner_insert" on public.competition_registrations for insert to authenticated with check (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
create policy "competition_registrations_owner_update" on public.competition_registrations for update to authenticated using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
create policy "competition_registrations_owner_delete" on public.competition_registrations for delete to authenticated using (user_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));
create index if not exists competition_registrations_competition_idx on public.competition_registrations(competition_id,created_at desc);
create index if not exists competition_registrations_user_idx on public.competition_registrations(user_id,created_at desc);




-- #22 會員成長第2階段：活躍／連續參與＋隱藏／彩蛋成就
create table if not exists public.growth_activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  source text not null default 'visit',
  created_at timestamptz not null default now(),
  primary key(user_id,activity_date)
);
create index if not exists growth_activity_days_user_date_idx on public.growth_activity_days(user_id,activity_date desc);
alter table public.growth_activity_days enable row level security;
drop policy if exists growth_activity_days_owner on public.growth_activity_days;
create policy growth_activity_days_owner on public.growth_activity_days for select to authenticated using(user_id=auth.uid() or public.is_admin());

alter table public.growth_achievements drop constraint if exists growth_achievements_achievement_type_check;
alter table public.growth_achievements add constraint growth_achievements_achievement_type_check check(achievement_type in ('registration_count','result_place','points','active_days','login_streak','registration_streak'));

create or replace function public.record_growth_activity()
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); d date:=current_date; streak integer:=0; days integer:=0; cur date;
begin
 if uid is null then raise exception '請先登入'; end if;
 insert into public.growth_activity_days(user_id,activity_date,source) values(uid,d,'visit') on conflict do nothing;
 select count(*) into days from public.growth_activity_days where user_id=uid and activity_date >= date_trunc('month',current_date)::date;
 cur:=d;
 while exists(select 1 from public.growth_activity_days where user_id=uid and activity_date=cur) loop
   streak:=streak+1; cur:=cur-1;
 end loop;
 return jsonb_build_object('active_days',days,'login_streak',streak);
end; $$;
revoke all on function public.record_growth_activity() from public;
grant execute on function public.record_growth_activity() to authenticated;

create or replace function public.check_growth_achievements(p_user_id uuid default auth.uid())
returns integer language plpgsql security definer set search_path=public as $$
declare a public.growth_achievements%rowtype; unlocked integer:=0; n integer:=0; pts integer:=0; streak integer:=0; days integer:=0;
begin
 if p_user_id is null then return 0; end if;
 select growth_points into pts from public.profiles where id=p_user_id;
 select count(*) into days from public.growth_activity_days where user_id=p_user_id and activity_date >= date_trunc('month',current_date)::date;
 if days=0 then
   select count(*) into days from public.growth_activity_days where user_id=p_user_id;
 end if;
 if exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=current_date) then
   n:=0;
   while exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=(current_date-n)) loop n:=n+1; end loop;
   streak:=n;
 end if;
 for a in select * from public.growth_achievements where active=true loop
   if exists(select 1 from public.growth_user_achievements where user_id=p_user_id and achievement_id=a.id) then continue; end if;
   n:=0;
   if a.achievement_type='registration_count' then
     select count(*) into n from public.competition_registrations where user_id=p_user_id and status in ('active','pending','approved');
   elsif a.achievement_type='result_place' then
     select count(*) into n from public.competition_results where user_id=p_user_id and place=1;
   elsif a.achievement_type='points' then n:=coalesce(pts,0);
   elsif a.achievement_type='active_days' then n:=days;
   elsif a.achievement_type='login_streak' then n:=streak;
   elsif a.achievement_type='registration_streak' then
     select count(*) into n from public.growth_activity_days d where d.user_id=p_user_id and d.activity_date >= current_date-6;
   end if;
   if n>=a.requirement_count then
     insert into public.growth_user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
     if found then
       unlocked:=unlocked+1;
       if a.reward_points>0 then perform public.award_growth_points(p_user_id,a.reward_points,'解鎖成就：'||a.title,'achievement',a.id::text,'achievement:'||a.id::text||':'||p_user_id::text,null); end if;
     end if;
   end if;
 end loop;
 return unlocked;
end; $$;
revoke all on function public.check_growth_achievements(uuid) from public;
grant execute on function public.check_growth_achievements(uuid) to authenticated;

-- Seed two examples for the new system; existing data is preserved.
insert into public.growth_achievements(code,title,description,achievement_type,requirement_count,reward_points,icon,rarity,hidden,active)
values
('active_7_days','活躍一週','累積 7 天活躍紀錄。', 'active_days',7,20,'🔥','rare',false,true),
('secret_midnight','？？？','這是一個神秘的彩蛋成就。', 'login_streak',3,50,'🥚','legendary',true,true)
on conflict(code) do nothing;

notify pgrst, 'reload schema';


-- #21 會員成長系統 v1：積分、等級、任務、成就與管理紀錄
alter table public.profiles add column if not exists growth_points integer not null default 0;
alter table public.profiles add column if not exists growth_level text not null default 'newbie';

create table if not exists public.growth_levels (
  code text primary key,
  name text not null,
  min_points integer not null default 0 check(min_points >= 0),
  icon text not null default '⭐',
  sort_order integer not null default 0
);
insert into public.growth_levels(code,name,min_points,icon,sort_order) values
 ('newbie','新手',0,'🌱',1),('bronze','青銅會員',100,'⭐',2),('silver','白銀會員',300,'🥈',3),('gold','黃金會員',600,'🥇',4),('diamond','鑽石會員',1000,'💎',5)
on conflict(code) do nothing;

create table if not exists public.growth_point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check(amount <> 0),
  reason text not null,
  source_type text not null default 'manual',
  source_id text,
  source_key text unique,
  admin_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists growth_points_user_idx on public.growth_point_transactions(user_id,created_at desc);

create table if not exists public.growth_tasks (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text,
  task_type text not null check(task_type in ('profile_complete','first_registration','first_result','registration_count','result_count')),
  requirement_count integer not null default 1 check(requirement_count > 0),
  reward_points integer not null default 0 check(reward_points >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.growth_tasks add column if not exists cycle_type text not null default 'one_time';
alter table public.growth_tasks add column if not exists start_at timestamptz;
alter table public.growth_tasks add column if not exists end_at timestamptz;
alter table public.growth_tasks drop constraint if exists growth_tasks_cycle_type_check;
alter table public.growth_tasks add constraint growth_tasks_cycle_type_check check(cycle_type in ('one_time','daily','weekly'));

insert into public.growth_tasks(code,title,description,task_type,requirement_count,reward_points) values
 ('complete_profile','完成會員資料','完成會員暱稱設定', 'profile_complete',1,20),
 ('first_registration','第一次報名','第一次成功報名活動／比賽', 'first_registration',1,20),
 ('first_result','第一次參賽成績','第一次產生已公布的比賽成績', 'first_result',1,30)
on conflict(code) do nothing;

create table if not exists public.growth_user_tasks (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.growth_tasks(id) on delete cascade,
  progress integer not null default 0,
  completed_at timestamptz,
  primary key(user_id,task_id)
);
create index if not exists growth_user_tasks_user_idx on public.growth_user_tasks(user_id);
alter table public.growth_user_tasks add column if not exists cycle_key text not null default 'once';
alter table public.growth_user_tasks drop constraint if exists growth_user_tasks_pkey;
alter table public.growth_user_tasks add constraint growth_user_tasks_pkey primary key(user_id,task_id,cycle_key);
create index if not exists growth_user_tasks_cycle_idx on public.growth_user_tasks(user_id,task_id,cycle_key);

create table if not exists public.growth_achievements (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text,
  achievement_type text not null check(achievement_type in ('registration_count','result_place','points')),
  requirement_count integer not null default 1 check(requirement_count > 0),
  reward_points integer not null default 0 check(reward_points >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.growth_achievements add column if not exists icon text not null default '🏆';
alter table public.growth_achievements add column if not exists rarity text not null default 'common';
alter table public.growth_achievements add column if not exists hidden boolean not null default false;
alter table public.growth_achievements drop constraint if exists growth_achievements_rarity_check;
alter table public.growth_achievements add constraint growth_achievements_rarity_check check(rarity in ('common','rare','epic','legendary'));

insert into public.growth_achievements(code,title,description,achievement_type,requirement_count,reward_points) values
 ('first_registration','初次參賽','完成第一次活動／比賽報名','registration_count',1,10),
 ('first_champion','首次冠軍','取得一次第一名','result_place',1,30),
 ('points_100','積分達人','累積取得 100 積分','points',100,20)
on conflict(code) do nothing;

create table if not exists public.growth_user_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id uuid not null references public.growth_achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key(user_id,achievement_id)
);
create index if not exists growth_user_achievements_user_idx on public.growth_user_achievements(user_id,unlocked_at desc);

-- 成就自動解鎖
create or replace function public.check_growth_achievements(p_user_id uuid default auth.uid())
returns integer language plpgsql security definer set search_path=public as $$
declare a growth_achievements%rowtype; unlocked integer:=0; n integer:=0; pts integer:=0;
begin
 if p_user_id is null then raise exception '請先登入'; end if;
 select growth_points into pts from public.profiles where id=p_user_id;
 for a in select * from public.growth_achievements where active=true loop
   if exists(select 1 from public.growth_user_achievements where user_id=p_user_id and achievement_id=a.id) then continue; end if;
   if a.achievement_type='registration_count' then
     select count(*) into n from public.competition_registrations where user_id=p_user_id and status in ('active','pending','approved');
   elsif a.achievement_type='result_place' then
     select count(*) into n from public.competition_results r join public.competitions c on c.id=r.competition_id where r.user_id=p_user_id and c.published=true and r.place=1;
   elsif a.achievement_type='points' then n:=coalesce(pts,0);
   end if;
   if n>=a.requirement_count then
     insert into public.growth_user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
     if found then
       unlocked:=unlocked+1;
       if a.reward_points>0 then perform public.award_growth_points(p_user_id,a.reward_points,'解鎖成就：'||a.title,'achievement',a.id::text,'achievement:'||a.id::text||':'||p_user_id::text,null); end if;
     end if;
   end if;
 end loop;
 return unlocked;
end; $$;
revoke all on function public.check_growth_achievements(uuid) from public;
grant execute on function public.check_growth_achievements(uuid) to authenticated;


alter table public.growth_levels enable row level security;
drop policy if exists growth_levels_public_read on public.growth_levels;
create policy growth_levels_public_read on public.growth_levels for select to authenticated using(true);
alter table public.growth_point_transactions enable row level security;
drop policy if exists growth_points_owner_read on public.growth_point_transactions;
drop policy if exists growth_points_admin_all on public.growth_point_transactions;
create policy growth_points_owner_read on public.growth_point_transactions for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy growth_points_admin_all on public.growth_point_transactions for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.growth_tasks enable row level security;
drop policy if exists growth_tasks_read on public.growth_tasks;
drop policy if exists growth_tasks_admin_all on public.growth_tasks;
create policy growth_tasks_read on public.growth_tasks for select to authenticated using(active or public.is_admin());
create policy growth_tasks_admin_all on public.growth_tasks for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.growth_user_tasks enable row level security;
drop policy if exists growth_user_tasks_owner on public.growth_user_tasks;
create policy growth_user_tasks_owner on public.growth_user_tasks for select to authenticated using(user_id=auth.uid() or public.is_admin());
alter table public.growth_achievements enable row level security;
drop policy if exists growth_achievements_read on public.growth_achievements;
drop policy if exists growth_achievements_admin_all on public.growth_achievements;
create policy growth_achievements_read on public.growth_achievements for select to authenticated using(active or public.is_admin());
create policy growth_achievements_admin_all on public.growth_achievements for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.growth_user_achievements enable row level security;
drop policy if exists growth_user_achievements_owner on public.growth_user_achievements;
create policy growth_user_achievements_owner on public.growth_user_achievements for select to authenticated using(user_id=auth.uid() or public.is_admin());

create or replace function public.refresh_growth_level(p_user_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare lvl growth_levels%rowtype;
begin
 select * into lvl from public.growth_levels where min_points <= coalesce((select growth_points from public.profiles where id=p_user_id),0) order by min_points desc,sort_order desc limit 1;
 if lvl.code is null then lvl.code:='newbie'; end if;
 update public.profiles set growth_level=lvl.code where id=p_user_id;
 return lvl.code;
end; $$;
revoke all on function public.refresh_growth_level(uuid) from public;
grant execute on function public.refresh_growth_level(uuid) to authenticated;

create or replace function public.award_growth_points(p_user_id uuid,p_amount integer,p_reason text,p_source_type text default 'manual',p_source_id text default null,p_source_key text default null,p_admin_user_id uuid default null)
returns integer language plpgsql security definer set search_path=public as $$
declare new_points integer; old_points integer;
begin
 if p_user_id is null or p_amount=0 then raise exception '積分資料無效'; end if;
 if p_source_key is not null and exists(select 1 from public.growth_point_transactions where source_key=p_source_key) then
   return coalesce((select growth_points from public.profiles where id=p_user_id),0);
 end if;
 select growth_points into old_points from public.profiles where id=p_user_id for update;
 if old_points is null then raise exception '找不到會員'; end if;
 new_points:=old_points+p_amount;
 if new_points<0 then raise exception '積分不足，無法扣除'; end if;
 update public.profiles set growth_points=new_points where id=p_user_id;
 insert into public.growth_point_transactions(user_id,amount,reason,source_type,source_id,source_key,admin_user_id) values(p_user_id,p_amount,p_reason,p_source_type,p_source_id,p_source_key,p_admin_user_id);
 perform public.refresh_growth_level(p_user_id);
 return new_points;
end; $$;
revoke all on function public.award_growth_points(uuid,integer,text,text,text,text,uuid) from public;
revoke all on function public.award_growth_points(uuid,integer,text,text,text,text,uuid) from authenticated;

create or replace function public.complete_growth_task(p_task_code text)
returns boolean language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); t growth_tasks%rowtype; n integer:=0; cycle text; completed boolean:=false;
begin
 if uid is null then raise exception '請先登入'; end if;
 select * into t from public.growth_tasks where code=p_task_code and active=true and (start_at is null or now()>=start_at) and (end_at is null or now()<=end_at);
 if t.id is null then raise exception '找不到任務'; end if;
 cycle:=case when t.cycle_type='daily' then to_char(now(),'YYYY-MM-DD') when t.cycle_type='weekly' then to_char(date_trunc('week',now()),'YYYY-MM-DD') else 'once' end;
 select exists(select 1 from public.growth_user_tasks where user_id=uid and task_id=t.id and cycle_key=cycle and completed_at is not null) into completed;
 if completed then return true; end if;
 if t.task_type='profile_complete' then select count(*) into n from public.profiles where id=uid and coalesce(nullif(trim(nickname),''),'')<>'';
 elsif t.task_type='first_registration' then select count(*) into n from public.competition_registrations where user_id=uid and status in ('active','pending','approved');
 elsif t.task_type='first_result' then select count(*) into n from public.competition_results r join public.competitions c on c.id=r.competition_id where r.user_id=uid and c.published=true;
 elsif t.task_type='registration_count' then select count(*) into n from public.competition_registrations where user_id=uid and status in ('active','pending','approved') and (t.cycle_type='one_time' or created_at >= case when t.cycle_type='daily' then date_trunc('day',now()) else date_trunc('week',now()) end);
 elsif t.task_type='result_count' then select count(*) into n from public.competition_results r join public.competitions c on c.id=r.competition_id where r.user_id=uid and c.published=true and (t.cycle_type='one_time' or r.created_at >= case when t.cycle_type='daily' then date_trunc('day',now()) else date_trunc('week',now()) end);
 end if;
 insert into public.growth_user_tasks(user_id,task_id,cycle_key,progress) values(uid,t.id,cycle,least(n,t.requirement_count)) on conflict(user_id,task_id,cycle_key) do update set progress=excluded.progress;
 if n>=t.requirement_count then
   update public.growth_user_tasks set completed_at=now(),progress=t.requirement_count where user_id=uid and task_id=t.id and cycle_key=cycle and completed_at is null;
   if t.reward_points>0 then perform public.award_growth_points(uid,t.reward_points,'完成任務：'||t.title,'task',t.id::text, 'task:'||t.id::text||':'||uid::text||':'||cycle,null); end if;
   return true;
 end if;
 return false;
end; $$;
revoke all on function public.complete_growth_task(text) from public;
grant execute on function public.complete_growth_task(text) to authenticated;

create or replace function public.admin_adjust_growth_points(p_user_id uuid,p_amount integer,p_reason text)
returns integer language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception '沒有管理員權限'; end if;
 if p_reason is null or trim(p_reason)='' then raise exception '請填寫調整原因'; end if;
 return public.award_growth_points(p_user_id,p_amount,p_reason,'admin',null,null,auth.uid());
end; $$;
revoke all on function public.admin_adjust_growth_points(uuid,integer,text) from public;
grant execute on function public.admin_adjust_growth_points(uuid,integer,text) to authenticated;

-- 報名／成績自動積分（只在第一次產生來源紀錄時發放，避免重複）
create or replace function public.growth_registration_reward()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status in ('active','pending','approved') then
   perform public.award_growth_points(new.user_id,5,'完成活動／比賽報名','registration',new.id::text,'registration:'||new.id::text,null);
 end if;
 return new;
end; $$;
drop trigger if exists trg_growth_registration_reward on public.competition_registrations;
create trigger trg_growth_registration_reward after insert on public.competition_registrations for each row execute function public.growth_registration_reward();

create or replace function public.growth_result_reward()
returns trigger language plpgsql security definer set search_path=public as $$
declare pts integer:=10; published boolean;
begin
 if new.user_id is null then return new; end if;
 select c.published into published from public.competitions c where c.id=new.competition_id;
 if coalesce(published,false) then
   pts:=case when new.place=1 then 50 when new.place=2 then 30 when new.place=3 then 20 else 10 end;
   perform public.award_growth_points(new.user_id,pts,'比賽成績：第 '||new.place||' 名','result',new.id::text,'result:'||new.id::text,null);
 end if;
 return new;
end; $$;
drop trigger if exists trg_growth_result_reward on public.competition_results;
create trigger trg_growth_result_reward after insert on public.competition_results for each row execute function public.growth_result_reward();




-- #22 會員成長第2階段：活躍／連續參與＋隱藏／彩蛋成就
create table if not exists public.growth_activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  source text not null default 'visit',
  created_at timestamptz not null default now(),
  primary key(user_id,activity_date)
);
create index if not exists growth_activity_days_user_date_idx on public.growth_activity_days(user_id,activity_date desc);
alter table public.growth_activity_days enable row level security;
drop policy if exists growth_activity_days_owner on public.growth_activity_days;
create policy growth_activity_days_owner on public.growth_activity_days for select to authenticated using(user_id=auth.uid() or public.is_admin());

alter table public.growth_achievements drop constraint if exists growth_achievements_achievement_type_check;
alter table public.growth_achievements add constraint growth_achievements_achievement_type_check check(achievement_type in ('registration_count','result_place','points','active_days','login_streak','registration_streak'));

create or replace function public.record_growth_activity()
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); d date:=current_date; streak integer:=0; days integer:=0; cur date;
begin
 if uid is null then raise exception '請先登入'; end if;
 insert into public.growth_activity_days(user_id,activity_date,source) values(uid,d,'visit') on conflict do nothing;
 select count(*) into days from public.growth_activity_days where user_id=uid and activity_date >= date_trunc('month',current_date)::date;
 cur:=d;
 while exists(select 1 from public.growth_activity_days where user_id=uid and activity_date=cur) loop
   streak:=streak+1; cur:=cur-1;
 end loop;
 return jsonb_build_object('active_days',days,'login_streak',streak);
end; $$;
revoke all on function public.record_growth_activity() from public;
grant execute on function public.record_growth_activity() to authenticated;

create or replace function public.check_growth_achievements(p_user_id uuid default auth.uid())
returns integer language plpgsql security definer set search_path=public as $$
declare a public.growth_achievements%rowtype; unlocked integer:=0; n integer:=0; pts integer:=0; streak integer:=0; days integer:=0;
begin
 if p_user_id is null then return 0; end if;
 select growth_points into pts from public.profiles where id=p_user_id;
 select count(*) into days from public.growth_activity_days where user_id=p_user_id and activity_date >= date_trunc('month',current_date)::date;
 if days=0 then
   select count(*) into days from public.growth_activity_days where user_id=p_user_id;
 end if;
 if exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=current_date) then
   n:=0;
   while exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=(current_date-n)) loop n:=n+1; end loop;
   streak:=n;
 end if;
 for a in select * from public.growth_achievements where active=true loop
   if exists(select 1 from public.growth_user_achievements where user_id=p_user_id and achievement_id=a.id) then continue; end if;
   n:=0;
   if a.achievement_type='registration_count' then
     select count(*) into n from public.competition_registrations where user_id=p_user_id and status in ('active','pending','approved');
   elsif a.achievement_type='result_place' then
     select count(*) into n from public.competition_results where user_id=p_user_id and place=1;
   elsif a.achievement_type='points' then n:=coalesce(pts,0);
   elsif a.achievement_type='active_days' then n:=days;
   elsif a.achievement_type='login_streak' then n:=streak;
   elsif a.achievement_type='registration_streak' then
     select count(*) into n from public.growth_activity_days d where d.user_id=p_user_id and d.activity_date >= current_date-6;
   end if;
   if n>=a.requirement_count then
     insert into public.growth_user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
     if found then
       unlocked:=unlocked+1;
       if a.reward_points>0 then perform public.award_growth_points(p_user_id,a.reward_points,'解鎖成就：'||a.title,'achievement',a.id::text,'achievement:'||a.id::text||':'||p_user_id::text,null); end if;
     end if;
   end if;
 end loop;
 return unlocked;
end; $$;
revoke all on function public.check_growth_achievements(uuid) from public;
grant execute on function public.check_growth_achievements(uuid) to authenticated;

-- Seed two examples for the new system; existing data is preserved.
insert into public.growth_achievements(code,title,description,achievement_type,requirement_count,reward_points,icon,rarity,hidden,active)
values
('active_7_days','活躍一週','累積 7 天活躍紀錄。', 'active_days',7,20,'🔥','rare',false,true),
('secret_midnight','？？？','這是一個神秘的彩蛋成就。', 'login_streak',3,50,'🥚','legendary',true,true)
on conflict(code) do nothing;

notify pgrst, 'reload schema';

-- 🎁 獎勵中心 v1：使用成長積分兌換優惠券型獎勵
create table if not exists public.growth_rewards (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text,
  icon text not null default '🎁',
  reward_type text not null default 'coupon' check(reward_type in ('coupon')),
  point_cost integer not null check(point_cost > 0),
  min_level text not null default 'newbie',
  required_achievement_id uuid references public.growth_achievements(id) on delete set null,
  user_limit integer,
  total_limit integer,
  redeemed_count integer not null default 0 check(redeemed_count >= 0),
  coupon_title text,
  coupon_description text,
  coupon_discount text,
  coupon_expires_days integer,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.growth_reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.growth_rewards(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  point_cost integer not null check(point_cost > 0),
  status text not null default 'redeemed' check(status in ('redeemed','cancelled')),
  coupon_id uuid references public.coupons(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists growth_reward_redemptions_user_idx on public.growth_reward_redemptions(user_id,created_at desc);
create index if not exists growth_reward_redemptions_reward_idx on public.growth_reward_redemptions(reward_id,created_at desc);

alter table public.growth_rewards enable row level security;
drop policy if exists growth_rewards_read on public.growth_rewards;
drop policy if exists growth_rewards_admin_all on public.growth_rewards;
create policy growth_rewards_read on public.growth_rewards for select to authenticated using(enabled or public.is_admin());
create policy growth_rewards_admin_all on public.growth_rewards for all to authenticated using(public.is_admin()) with check(public.is_admin());

alter table public.growth_reward_redemptions enable row level security;
drop policy if exists growth_reward_redemptions_owner_read on public.growth_reward_redemptions;
drop policy if exists growth_reward_redemptions_admin_all on public.growth_reward_redemptions;
create policy growth_reward_redemptions_owner_read on public.growth_reward_redemptions for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy growth_reward_redemptions_admin_all on public.growth_reward_redemptions for all to authenticated using(public.is_admin()) with check(public.is_admin());

create or replace function public.redeem_growth_reward(p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.growth_rewards%rowtype;
  p public.profiles%rowtype;
  unlocked boolean := false;
  user_count integer := 0;
  total_count integer := 0;
  coupon uuid;
  new_points integer;
  coupon_code text;
  coupon_expires timestamptz;
  level_ok boolean := false;
begin
  if uid is null then raise exception '請先登入'; end if;

  select * into r from public.growth_rewards where id=p_reward_id and enabled=true for update;
  if r.id is null then raise exception '找不到可兌換的獎勵'; end if;

  select * into p from public.profiles where id=uid for update;
  if p.id is null then raise exception '找不到會員'; end if;
  if coalesce(p.growth_points,0) < r.point_cost then raise exception '積分不足，還需要 % 點', r.point_cost-coalesce(p.growth_points,0); end if;

  select exists(
    select 1 from public.growth_levels g
    where g.code=r.min_level
      and g.min_points <= coalesce(p.growth_points,0)
      and g.min_points <= coalesce((select gl.min_points from public.growth_levels gl where gl.code=coalesce(p.growth_level,'newbie')),0)
  ) into level_ok;
  if r.min_level is not null and not level_ok then
    if not exists(select 1 from public.growth_levels g where g.code=r.min_level and g.min_points <= coalesce(p.growth_points,0)) then
      raise exception '會員等級不足，需達到 %', r.min_level;
    end if;
  end if;

  if r.required_achievement_id is not null then
    select exists(select 1 from public.growth_user_achievements where user_id=uid and achievement_id=r.required_achievement_id) into unlocked;
    if not unlocked then raise exception '尚未解鎖指定成就'; end if;
  end if;

  select count(*) into user_count from public.growth_reward_redemptions where reward_id=r.id and user_id=uid and status='redeemed';
  if r.user_limit is not null and user_count >= r.user_limit then raise exception '已達此獎勵的個人兌換上限'; end if;
  total_count := coalesce(r.redeemed_count,0);
  if r.total_limit is not null and total_count >= r.total_limit then raise exception '此獎勵已兌換完畢'; end if;

  new_points := coalesce(p.growth_points,0) - r.point_cost;
  perform public.award_growth_points(uid,-r.point_cost,'兌換獎勵：'||r.title,'reward',r.id::text,'reward:'||r.id::text||':'||uid::text||':'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),null);

  coupon_code := upper(substr(regexp_replace(coalesce(r.code,'REWARD'),'[^A-Za-z0-9]','','g'),1,12)) || '-' || upper(encode(gen_random_bytes(4),'hex'));
  if r.coupon_expires_days is not null then coupon_expires := now() + make_interval(days=>r.coupon_expires_days); end if;

  insert into public.coupons(user_id,title,description,code,discount,expires_at)
  values(uid,coalesce(nullif(r.coupon_title,''),r.title),coalesce(r.coupon_description,r.description),coupon_code,r.coupon_discount,coupon_expires)
  returning id into coupon;

  insert into public.growth_reward_redemptions(reward_id,user_id,point_cost,status,coupon_id)
  values(r.id,uid,r.point_cost,'redeemed',coupon);

  update public.growth_rewards set redeemed_count=coalesce(redeemed_count,0)+1, updated_at=now() where id=r.id;

  insert into public.notifications(user_id,title,content,type)
  values(uid,'🎁 獎勵兌換成功','你已使用 '||r.point_cost||' 點兌換「'||r.title||'」，優惠券已加入「我的 → 我的優惠券」。','優惠券');

  return jsonb_build_object('success',true,'reward_id',r.id,'coupon_id',coupon,'remaining_points',new_points);
end;
$$;
revoke all on function public.redeem_growth_reward(uuid) from public;
grant execute on function public.redeem_growth_reward(uuid) to authenticated;

insert into public.growth_rewards(code,title,description,icon,point_cost,min_level,coupon_title,coupon_description,coupon_discount,coupon_expires_days,user_limit,total_limit,enabled,sort_order)
values
('reward_coupon_10','10 元優惠券','使用成長積分兌換 10 元優惠券。','🎟️',50,'newbie','10 元優惠券','獎勵中心兌換券','NT$10',30,null,null,true,10),
('reward_coupon_30','30 元優惠券','使用成長積分兌換 30 元優惠券。','🎟️',120,'bronze','30 元優惠券','獎勵中心兌換券','NT$30',30,null,null,true,20),
('reward_coupon_50','50 元優惠券','使用成長積分兌換 50 元優惠券。','🎟️',200,'silver','50 元優惠券','獎勵中心兌換券','NT$50',30,1,null,true,30)
on conflict(code) do nothing;

notify pgrst, 'reload schema';
