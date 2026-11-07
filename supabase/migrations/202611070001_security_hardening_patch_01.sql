-- Smart Class v26.11.7 - consolidated security hardening review draft
-- Branch-only. NOT approved for production. No table rows are deleted/truncated.
-- The member-only activity stats view is switched to security_invoker;
-- public leaderboard output is moved to a column-restricted aggregate table without user IDs/no-show data.

begin;

-- 1. NULL-safe admin checks on the two reward management RPCs.
create or replace function public.admin_delete_growth_reward(p_reward_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare n integer := 0; caller_role text;
begin
  if auth.uid() is null then raise exception '需要登入後才能執行此操作' using errcode='42501'; end if;
  select role into caller_role from public.profiles where id=auth.uid() limit 1;
  if caller_role is distinct from 'admin' then raise exception '只有管理員可以刪除獎勵' using errcode='42501'; end if;
  if not exists(select 1 from public.growth_rewards where id=p_reward_id) then raise exception '找不到這個獎勵'; end if;
  select count(*) into n from public.growth_reward_redemptions where reward_id=p_reward_id;
  if n>0 then
    update public.growth_rewards set enabled=false,updated_at=now() where id=p_reward_id;
    return jsonb_build_object('success',true,'action','disabled','redemptions',n);
  end if;
  delete from public.growth_rewards where id=p_reward_id;
  if not found then raise exception '獎勵刪除失敗'; end if;
  return jsonb_build_object('success',true,'action','deleted','redemptions',0);
end;
$function$;

create or replace function public.admin_upsert_growth_reward(
 p_reward_id uuid,p_code text,p_title text,p_description text,p_icon text,p_category text,
 p_point_cost integer,p_min_level text,p_required_achievement_id uuid,p_user_limit integer,
 p_total_limit integer,p_coupon_title text,p_coupon_description text,p_coupon_discount text,
 p_coupon_expires_days integer,p_available_from timestamptz,p_available_until timestamptz,
 p_sort_order integer,p_enabled boolean
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare caller_role text; row_data public.growth_rewards%rowtype;
begin
  if auth.uid() is null then raise exception '需要登入後才能執行此操作' using errcode='42501'; end if;
  select role into caller_role from public.profiles where id=auth.uid() limit 1;
  if caller_role is distinct from 'admin' then raise exception '只有管理員可以管理獎勵' using errcode='42501'; end if;
  if coalesce(trim(p_code),'')='' then raise exception '獎勵代碼不可空白'; end if;
  if coalesce(trim(p_title),'')='' then raise exception '獎勵名稱不可空白'; end if;
  if p_point_cost is null or p_point_cost<1 then raise exception '所需積分必須大於 0'; end if;
  if p_user_limit is not null and p_user_limit<1 then raise exception '每人兌換上限必須大於 0'; end if;
  if p_total_limit is not null and p_total_limit<1 then raise exception '總兌換上限必須大於 0'; end if;
  if p_coupon_expires_days is not null and p_coupon_expires_days<1 then raise exception '優惠券有效天數必須大於 0'; end if;
  if p_available_from is not null and p_available_until is not null and p_available_from>=p_available_until then raise exception '開始時間必須早於結束時間'; end if;
  if p_reward_id is null then
    insert into public.growth_rewards(code,title,description,icon,category,reward_type,point_cost,min_level,required_achievement_id,user_limit,total_limit,coupon_title,coupon_description,coupon_discount,coupon_expires_days,available_from,available_until,sort_order,enabled)
    values(p_code,p_title,p_description,p_icon,p_category,'coupon',p_point_cost,p_min_level,p_required_achievement_id,p_user_limit,p_total_limit,p_coupon_title,p_coupon_description,p_coupon_discount,p_coupon_expires_days,p_available_from,p_available_until,p_sort_order,p_enabled)
    returning * into row_data;
  else
    update public.growth_rewards set code=p_code,title=p_title,description=p_description,icon=p_icon,category=p_category,reward_type='coupon',point_cost=p_point_cost,min_level=p_min_level,required_achievement_id=p_required_achievement_id,user_limit=p_user_limit,total_limit=p_total_limit,coupon_title=p_coupon_title,coupon_description=p_coupon_description,coupon_discount=p_coupon_discount,coupon_expires_days=p_coupon_expires_days,available_from=p_available_from,available_until=p_available_until,sort_order=p_sort_order,enabled=p_enabled,updated_at=now()
    where id=p_reward_id returning * into row_data;
    if row_data.id is null then raise exception '找不到這個獎勵'; end if;
  end if;
  return jsonb_build_object('success',true,'id',row_data.id,'action',case when p_reward_id is null then 'created' else 'updated' end);
end;
$function$;

-- 2. Cross-user achievement / level / badge RPCs require admin or trusted service.
create or replace function public.check_growth_achievements(p_user_id uuid default auth.uid())
returns integer language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
 a public.growth_achievements%rowtype;
 v_caller uuid:=auth.uid();
 v_target uuid:=coalesce(p_user_id,auth.uid());
 v_service boolean:=coalesce(auth.jwt()->>'role','')='service_role';
 unlocked integer:=0; n integer:=0; pts integer:=0; streak integer:=0; days integer:=0;
begin
 if v_target is null then raise exception '請先登入' using errcode='42501'; end if;
 if not v_service and (v_caller is null or (v_target is distinct from v_caller and not public.is_admin())) then raise exception '沒有權限' using errcode='42501'; end if;
 select growth_points into pts from public.profiles where id=v_target;
 select count(*) into days from public.growth_activity_days where user_id=v_target and activity_date>=date_trunc('month',current_date)::date;
 if days=0 then select count(*) into days from public.growth_activity_days where user_id=v_target; end if;
 if exists(select 1 from public.growth_activity_days where user_id=v_target and activity_date=current_date) then
   n:=0;
   while exists(select 1 from public.growth_activity_days where user_id=v_target and activity_date=current_date-n) loop n:=n+1; end loop;
   streak:=n;
 end if;
 for a in select * from public.growth_achievements where active=true loop
   if exists(select 1 from public.growth_user_achievements where user_id=v_target and achievement_id=a.id) then continue; end if;
   n:=0;
   if a.achievement_type='registration_count' then
     select count(*) into n from public.competition_registrations where user_id=v_target and status in ('active','pending','approved');
   elsif a.achievement_type='result_place' then
     select count(*) into n from public.competition_results where user_id=v_target and place=1;
   elsif a.achievement_type='points' then n:=coalesce(pts,0);
   elsif a.achievement_type='active_days' then n:=days;
   elsif a.achievement_type='login_streak' then n:=streak;
   elsif a.achievement_type='registration_streak' then
     select count(*) into n from public.growth_activity_days where user_id=v_target and activity_date>=current_date-6;
   elsif a.achievement_type='night_visit' then
     select count(*) into n from public.growth_activity_days where user_id=v_target and activity_date=current_date and extract(hour from now()) between 0 and 4;
   elsif a.achievement_type='weekend_visit' then
     select count(*) into n from public.growth_activity_days where user_id=v_target and activity_date=current_date and extract(isodow from current_date) in (6,7);
   end if;
   if n>=a.requirement_count then
     insert into public.growth_user_achievements(user_id,achievement_id) values(v_target,a.id) on conflict do nothing;
     if found then
       unlocked:=unlocked+1;
       insert into public.notifications(user_id,title,content,type) values(v_target,'🥚 彩蛋成就解鎖！','恭喜你發現「'||a.title||'」'||case when a.reward_points>0 then '，獲得 +'||a.reward_points||' 積分。' else '。' end,'成長');
       if a.reward_points>0 then perform public.award_growth_points(v_target,a.reward_points,'解鎖成就：'||a.title,'achievement',a.id::text,'achievement:'||a.id::text||':'||v_target::text,null); end if;
     end if;
   end if;
 end loop;
 return unlocked;
end;
$function$;

create or replace function public.refresh_growth_level(p_user_id uuid)
returns text language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare lvl public.growth_levels%rowtype; v_caller uuid:=auth.uid(); v_service boolean:=coalesce(auth.jwt()->>'role','')='service_role';
begin
 if p_user_id is null then raise exception '缺少會員 ID'; end if;
 if not v_service and (v_caller is null or (p_user_id is distinct from v_caller and not public.is_admin())) then raise exception '沒有權限' using errcode='42501'; end if;
 select * into lvl from public.growth_levels where min_points<=coalesce((select growth_points from public.profiles where id=p_user_id),0) order by min_points desc,sort_order desc limit 1;
 if lvl.code is null then lvl.code:='newbie'; end if;
 update public.profiles set growth_level=lvl.code where id=p_user_id;
 return lvl.code;
end;
$function$;

create or replace function public.check_activity_badges(p_user_id uuid default auth.uid())
returns jsonb language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
 v_user uuid:=coalesce(p_user_id,auth.uid()); v_caller uuid:=auth.uid();
 v_service boolean:=coalesce(auth.jwt()->>'role','')='service_role';
 v_count integer; v_points integer; v_no_show integer; v_unlocked integer:=0; b record;
begin
 if v_user is null then raise exception '請先登入' using errcode='42501'; end if;
 if not v_service and (v_caller is null or (v_user is distinct from v_caller and not public.is_admin())) then raise exception '沒有權限' using errcode='42501'; end if;
 select count(*) into v_count from public.competition_attendance where user_id=v_user and status in ('checked_in','late');
 select coalesce(sum(points_awarded)+sum(completion_points_awarded),0) into v_points from public.competition_attendance where user_id=v_user;
 select count(*) into v_no_show from public.competition_attendance where user_id=v_user and status='no_show';
 for b in select * from public.activity_badges where active=true loop
   if (b.requirement_type='first_activity' and v_count>=1)
      or (b.requirement_type='activity_count' and v_count>=b.requirement_value)
      or (b.requirement_type='total_points' and v_points>=b.requirement_value)
      or (b.requirement_type='perfect_attendance' and v_count>=b.requirement_value and v_no_show=0) then
     insert into public.user_activity_badges(user_id,badge_id) values(v_user,b.id) on conflict do nothing;
     if found then v_unlocked:=v_unlocked+1; end if;
   end if;
 end loop;
 return jsonb_build_object('success',true,'new_badges',v_unlocked,'activity_count',v_count,'activity_points',v_points);
end;
$function$;

-- 3. Protect member-editable competition registration fields and statuses.
create or replace function public.guard_competition_registration_member_update()
returns trigger language plpgsql
set search_path = ''
as $function$
begin
 if public.is_admin() or coalesce(auth.jwt()->>'role','')='service_role' then return new; end if;
 if new.id is distinct from old.id
    or new.competition_id is distinct from old.competition_id
    or new.user_id is distinct from old.user_id
    or new.member_no is distinct from old.member_no
    or new.created_at is distinct from old.created_at then
   raise exception '會員不可修改報名所屬活動或身分欄位' using errcode='42501';
 end if;
 if new.status is distinct from old.status then
   if new.status='cancelled' and old.status in ('active','pending','approved') then
     new.cancelled_at:=now();
   elsif new.status='active' and old.status='cancelled' then
     new.cancelled_at:=null;
   else
     raise exception '會員只能取消或重新啟用自己的報名' using errcode='42501';
   end if;
 else
   new.cancelled_at:=old.cancelled_at;
 end if;
 new.updated_at:=now();
 return new;
end;
$function$;

do $$
begin
 if not exists(select 1 from pg_trigger where tgname='trg_a_guard_competition_registration_update' and tgrelid='public.competition_registrations'::regclass and not tgisinternal) then
   create trigger trg_a_guard_competition_registration_update before update on public.competition_registrations
   for each row execute function public.guard_competition_registration_member_update();
 end if;
end;
$$;

-- 3A. Split private member statistics from the public leaderboard.
alter view public.activity_member_stats set (security_invoker = true);
revoke select on public.activity_member_stats from anon;
grant select on public.activity_member_stats to authenticated;

-- Public leaderboard data is stored separately. The internal user_id is never
-- granted to browser roles; no-show counts are deliberately excluded.
create table if not exists public.activity_public_leaderboard (
  user_id uuid primary key,
  nickname text not null default '會員',
  attended_count integer not null default 0,
  late_count integer not null default 0,
  activity_points integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.activity_public_leaderboard enable row level security;
revoke all on table public.activity_public_leaderboard from public, anon, authenticated;
grant select (nickname, attended_count, late_count, activity_points)
  on table public.activity_public_leaderboard to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='activity_public_leaderboard'
      and policyname='activity_public_leaderboard_read'
  ) then
    create policy activity_public_leaderboard_read
      on public.activity_public_leaderboard
      for select to anon, authenticated using (true);
  end if;
end;
$$;

create or replace function public.sync_activity_public_leaderboard_user(p_user_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if p_user_id is null then return; end if;
  if exists (select 1 from public.competition_attendance where user_id=p_user_id) then
    insert into public.activity_public_leaderboard(
      user_id,nickname,attended_count,late_count,activity_points,updated_at
    )
    select a.user_id,coalesce(nullif(max(btrim(p.nickname)),''),'會員'),
      count(*) filter (where a.status in ('checked_in','late'))::integer,
      count(*) filter (where a.status='late')::integer,
      (coalesce(sum(a.points_awarded),0)+coalesce(sum(a.completion_points_awarded),0))::integer,
      now()
    from public.competition_attendance a
    left join public.profiles p on p.id=a.user_id
    where a.user_id=p_user_id
    group by a.user_id
    on conflict (user_id) do update set
      nickname=excluded.nickname,attended_count=excluded.attended_count,
      late_count=excluded.late_count,activity_points=excluded.activity_points,
      updated_at=excluded.updated_at;
  else
    -- Remove only the derived leaderboard row when its final source attendance row is gone.
    delete from public.activity_public_leaderboard where user_id=p_user_id;
  end if;
end;
$function$;

create or replace function public.sync_activity_public_leaderboard_from_attendance()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if tg_op='DELETE' then
    perform public.sync_activity_public_leaderboard_user(old.user_id);
    return old;
  elsif tg_op='UPDATE' then
    if old.user_id is distinct from new.user_id then
      perform public.sync_activity_public_leaderboard_user(old.user_id);
    end if;
    perform public.sync_activity_public_leaderboard_user(new.user_id);
    return new;
  else
    perform public.sync_activity_public_leaderboard_user(new.user_id);
    return new;
  end if;
end;
$function$;

create or replace function public.sync_activity_public_leaderboard_from_profile()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if new.nickname is distinct from old.nickname then
    update public.activity_public_leaderboard
    set nickname=coalesce(nullif(btrim(new.nickname),''),'會員'),updated_at=now()
    where user_id=new.id;
  end if;
  return new;
end;
$function$;

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname='trg_activity_public_leaderboard_attendance'
      and tgrelid='public.competition_attendance'::regclass and not tgisinternal
  ) then
    create trigger trg_activity_public_leaderboard_attendance
      after insert or update or delete on public.competition_attendance
      for each row execute function public.sync_activity_public_leaderboard_from_attendance();
  end if;
  if not exists (
    select 1 from pg_trigger where tgname='trg_activity_public_leaderboard_profile'
      and tgrelid='public.profiles'::regclass and not tgisinternal
  ) then
    create trigger trg_activity_public_leaderboard_profile
      after update of nickname on public.profiles
      for each row execute function public.sync_activity_public_leaderboard_from_profile();
  end if;
end;
$$;

insert into public.activity_public_leaderboard(
  user_id,nickname,attended_count,late_count,activity_points,updated_at
)
select a.user_id,coalesce(nullif(max(btrim(p.nickname)),''),'會員'),
  count(*) filter (where a.status in ('checked_in','late'))::integer,
  count(*) filter (where a.status='late')::integer,
  (coalesce(sum(a.points_awarded),0)+coalesce(sum(a.completion_points_awarded),0))::integer,
  now()
from public.competition_attendance a
left join public.profiles p on p.id=a.user_id
group by a.user_id
on conflict (user_id) do update set
  nickname=excluded.nickname,attended_count=excluded.attended_count,
  late_count=excluded.late_count,activity_points=excluded.activity_points,
  updated_at=excluded.updated_at;

revoke execute on function public.sync_activity_public_leaderboard_user(uuid) from public, anon, authenticated;
revoke execute on function public.sync_activity_public_leaderboard_from_attendance() from public, anon, authenticated;
revoke execute on function public.sync_activity_public_leaderboard_from_profile() from public, anon, authenticated;

-- 4. Authenticated members must not read unpublished announcements.
alter policy announcement_authenticated_read on public.announcements
using (published=true and published_at<=now());

-- 5. Remove anon grants from tables with no anon-facing RLS policy.
-- Public content tables and public submission tables are deliberately untouched.
revoke all on table
 public.activity_badges,public.announcement_reads,public.competition_attendance,
 public.competition_registrations,public.competition_reward_grants,public.competition_reward_rules,
 public.competition_waitlist,public.coupons,public.device_push_tokens,public.download_files,
 public.growth_achievement_unlock_history,public.growth_achievements,public.growth_activity_days,
 public.growth_levels,public.growth_point_transactions,public.growth_reset_history,
 public.growth_reward_redemptions,public.growth_rewards,public.growth_tasks,public.growth_user_achievements,
 public.growth_user_tasks,public.notifications,public.order_items,public.orders,public.support_tickets,
 public.user_activity_badges,public.visitor_accounts,public.visitor_profiles
from anon;

-- Published download catalog is intentionally visible before login.
-- Expose only the fields used by the public catalog; never expose storage internals or counters.
grant select (id,title,description,file_url,published,created_at,storage_provider,file_size,version)
  on table public.download_files to anon;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='download_files'
      and policyname='download_files_published_anon_read'
  ) then
    create policy download_files_published_anon_read
      on public.download_files for select to anon
      using (published=true);
  end if;
end;
$$;

-- 6. Remove anonymous execution from all admin RPCs.
do $$
declare r record;
begin
 for r in select p.oid::regprocedure AS sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and left(p.proname,6)='admin_'
 loop execute format('revoke execute on function %s from public, anon',r.sig); end loop;
end;
$$;

-- 7. Keep member-facing RPCs authenticated; remove anon/PUBLIC execution.
revoke execute on function public.check_growth_achievements(uuid) from public,anon;
revoke execute on function public.refresh_growth_level(uuid) from public,anon;
revoke execute on function public.checkin_competition(uuid,text) from public,anon;
revoke execute on function public.close_my_support_ticket(uuid) from public,anon;
revoke execute on function public.complete_growth_task(text) from public,anon;
revoke execute on function public.create_cash_order(uuid,integer,text) from public,anon;
revoke execute on function public.join_competition_waitlist(uuid,text) from public,anon;
revoke execute on function public.record_growth_activity() from public,anon;
revoke execute on function public.redeem_growth_reward(uuid) from public,anon;
revoke execute on function public.use_growth_coupon(uuid) from public,anon;
revoke execute on function public.is_admin_user() from public,anon;

-- Internal writers and trigger handlers are not browser RPC endpoints.
revoke execute on function public.award_growth_points(uuid,integer,text,text,text,text,uuid) from public,anon,authenticated;
revoke execute on function public.check_activity_badges(uuid) from public,anon,authenticated;
revoke execute on function public.check_competition_registration_rules() from public,anon,authenticated;
revoke execute on function public.ensure_visitor_profile() from public,anon,authenticated;
revoke execute on function public.growth_registration_reward() from public,anon,authenticated;
revoke execute on function public.growth_result_reward() from public,anon,authenticated;
revoke execute on function public.assign_member_no_and_nickname() from public,anon,authenticated;
-- Download count is a signed-in feature in the current UI, not an anonymous RPC.
revoke execute on function public.increment_download_count(uuid) from public, anon;

-- 8. Harden SECURITY DEFINER search paths; pg_temp is last.
do $$
declare r record;
begin
 for r in select p.oid::regprocedure AS sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and p.proname not in ('is_admin','assign_member_no_and_nickname')
 loop execute format('alter function %s set search_path = public, pg_temp',r.sig); end loop;
end;
$$;

commit;

-- Verification queries to run after separate production approval:
-- SELECT p.oid::regprocedure,has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
--        has_function_privilege('authenticated',p.oid,'EXECUTE') auth_exec,p.proconfig
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.prosecdef ORDER BY p.proname;
-- SELECT policyname,roles,qual FROM pg_policies WHERE schemaname='public' AND tablename='announcements';
-- SELECT policyname,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname='public' AND tablename='competition_registrations';
