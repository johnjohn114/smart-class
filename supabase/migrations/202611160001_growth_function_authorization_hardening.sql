-- Growth RPC authorization hardening.
-- Definitions copied from the live catalog and reviewed on 2026-11-16.
-- This file is for isolated verification first; never auto-apply to production.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_delete_growth_reward(p_reward_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n integer := 0;
  caller_role text;
begin
  select role into caller_role from public.profiles where id = auth.uid() limit 1;
  if auth.uid() is null or caller_role is distinct from 'admin' then
    raise exception '只有管理員可以刪除獎勵';
  end if;

  if not exists(select 1 from public.growth_rewards where id = p_reward_id) then
    raise exception '找不到這個獎勵';
  end if;

  select count(*) into n
  from public.growth_reward_redemptions
  where reward_id = p_reward_id;

  if n > 0 then
    update public.growth_rewards
    set enabled = false, updated_at = now()
    where id = p_reward_id;
    return jsonb_build_object('success', true, 'action', 'disabled', 'redemptions', n);
  end if;

  delete from public.growth_rewards where id = p_reward_id;
  if not found then
    raise exception '獎勵刪除失敗';
  end if;
  return jsonb_build_object('success', true, 'action', 'deleted', 'redemptions', 0);
end;
$function$;


CREATE OR REPLACE FUNCTION public.admin_upsert_growth_reward(p_reward_id uuid, p_code text, p_title text, p_description text, p_icon text, p_category text, p_point_cost integer, p_min_level text, p_required_achievement_id uuid, p_user_limit integer, p_total_limit integer, p_coupon_title text, p_coupon_description text, p_coupon_discount text, p_coupon_expires_days integer, p_available_from timestamp with time zone, p_available_until timestamp with time zone, p_sort_order integer, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller_role text;
  row_data public.growth_rewards%rowtype;
begin
  select role into caller_role from public.profiles where id=auth.uid() limit 1;
  if auth.uid() is null or caller_role is distinct from 'admin' then raise exception '只有管理員可以管理獎勵'; end if;
  if coalesce(trim(p_code),'')='' then raise exception '獎勵代碼不可空白'; end if;
  if coalesce(trim(p_title),'')='' then raise exception '獎勵名稱不可空白'; end if;
  if p_point_cost is null or p_point_cost < 1 then raise exception '所需積分必須大於 0'; end if;
  if p_user_limit is not null and p_user_limit < 1 then raise exception '每人兌換上限必須大於 0'; end if;
  if p_total_limit is not null and p_total_limit < 1 then raise exception '總兌換上限必須大於 0'; end if;
  if p_coupon_expires_days is not null and p_coupon_expires_days < 1 then raise exception '優惠券有效天數必須大於 0'; end if;
  if p_available_from is not null and p_available_until is not null and p_available_from >= p_available_until then raise exception '開始時間必須早於結束時間'; end if;
  if p_reward_id is null then
    insert into public.growth_rewards(code,title,description,icon,category,reward_type,point_cost,min_level,required_achievement_id,user_limit,total_limit,coupon_title,coupon_description,coupon_discount,coupon_expires_days,available_from,available_until,sort_order,enabled)
    values(p_code,p_title,p_description,p_icon,p_category,'coupon',p_point_cost,p_min_level,p_required_achievement_id,p_user_limit,p_total_limit,p_coupon_title,p_coupon_description,p_coupon_discount,p_coupon_expires_days,p_available_from,p_available_until,p_sort_order,p_enabled)
    returning * into row_data;
  else
    update public.growth_rewards set
      code=p_code,title=p_title,description=p_description,icon=p_icon,category=p_category,reward_type='coupon',point_cost=p_point_cost,min_level=p_min_level,required_achievement_id=p_required_achievement_id,user_limit=p_user_limit,total_limit=p_total_limit,coupon_title=p_coupon_title,coupon_description=p_coupon_description,coupon_discount=p_coupon_discount,coupon_expires_days=p_coupon_expires_days,available_from=p_available_from,available_until=p_available_until,sort_order=p_sort_order,enabled=p_enabled,updated_at=now()
    where id=p_reward_id returning * into row_data;
    if row_data.id is null then raise exception '找不到這個獎勵'; end if;
  end if;
  return jsonb_build_object('success',true,'id',row_data.id,'action',case when p_reward_id is null then 'created' else 'updated' end);
end;
$function$;


CREATE OR REPLACE FUNCTION public._refresh_growth_level_internal(p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lvl growth_levels%rowtype;
begin
 select * into lvl from public.growth_levels where min_points <= coalesce((select growth_points from public.profiles where id=p_user_id),0) order by min_points desc,sort_order desc limit 1;
 if lvl.code is null then lvl.code:='newbie'; end if;
 update public.profiles set growth_level=lvl.code where id=p_user_id;
 return lvl.code;
end; $function$;


CREATE OR REPLACE FUNCTION public.refresh_growth_level(p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null
     or (auth.uid() is distinct from p_user_id
         and not exists (
           select 1 from public.profiles
           where id = auth.uid() and role = 'admin'
         )) then
    raise exception '沒有權限更新此會員等級';
  end if;

  return public._refresh_growth_level_internal(p_user_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.award_growth_points(p_user_id uuid, p_amount integer, p_reason text, p_source_type text DEFAULT 'manual'::text, p_source_id text DEFAULT NULL::text, p_source_key text DEFAULT NULL::text, p_admin_user_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  new_points integer;
  old_points integer;
  old_level text;
  new_level text;
  level_name text;
begin
  if p_user_id is null or p_amount=0 then raise exception '積分資料無效'; end if;
  if p_source_key is not null and exists(select 1 from public.growth_point_transactions where source_key=p_source_key) then
    return coalesce((select growth_points from public.profiles where id=p_user_id),0);
  end if;
  select growth_points,growth_level into old_points,old_level from public.profiles where id=p_user_id for update;
  if old_points is null then raise exception '找不到會員'; end if;
  new_points:=old_points+p_amount;
  if new_points<0 then raise exception '積分不足，無法扣除'; end if;
  update public.profiles set growth_points=new_points where id=p_user_id;
  insert into public.growth_point_transactions(user_id,amount,reason,source_type,source_id,source_key,admin_user_id)
  values(p_user_id,p_amount,p_reason,p_source_type,p_source_id,p_source_key,p_admin_user_id);
  new_level:=public._refresh_growth_level_internal(p_user_id);

  if p_source_type <> 'reward' then
    insert into public.notifications(user_id,title,content,type)
    values(
      p_user_id,
      case when p_amount>0 then '💎 獲得成長積分' else '💎 使用成長積分' end,
      case when p_amount>0 then '你獲得 +'||p_amount||' 積分：'||coalesce(p_reason,'')
           else '你使用 '||abs(p_amount)||' 積分：'||coalesce(p_reason,'') end,
      '成長'
    );
  end if;

  if coalesce(old_level,'newbie') is distinct from new_level then
    select name into level_name from public.growth_levels where code=new_level;
    insert into public.notifications(user_id,title,content,type)
    values(p_user_id,'🎉 會員等級升級！','恭喜你從「'||coalesce((select name from public.growth_levels where code=old_level),'新手')||'」升級為「'||coalesce(level_name,new_level)||'」！','成長');
  end if;
  return new_points;
end; $function$;


CREATE OR REPLACE FUNCTION public.check_growth_achievements(p_user_id uuid DEFAULT auth.uid())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 a public.growth_achievements%rowtype;
 unlocked integer:=0;
 n integer:=0;
 pts integer:=0;
 streak integer:=0;
 days integer:=0;
begin
 if auth.uid() is null or (p_user_id is not null and auth.uid() is distinct from p_user_id and not exists (select 1 from public.profiles where id=auth.uid() and role='admin')) then
   raise exception '沒有權限檢查此會員成就';
 end if;
 if p_user_id is null then return 0; end if;
 select growth_points into pts from public.profiles where id=p_user_id;
 select count(*) into days from public.growth_activity_days where user_id=p_user_id and activity_date >= date_trunc('month',current_date)::date;
 if days=0 then select count(*) into days from public.growth_activity_days where user_id=p_user_id; end if;
 if exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=current_date) then
   n:=0; while exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=(current_date-n)) loop n:=n+1; end loop; streak:=n;
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
   elsif a.achievement_type='night_visit' then
     select count(*) into n from public.growth_activity_days d where d.user_id=p_user_id and d.activity_date=current_date and extract(hour from now()) between 0 and 4;
   elsif a.achievement_type='weekend_visit' then
     select count(*) into n from public.growth_activity_days d where d.user_id=p_user_id and d.activity_date=current_date and extract(isodow from current_date) in (6,7);
   end if;
   if n>=a.requirement_count then
     insert into public.growth_user_achievements(user_id,achievement_id) values(p_user_id,a.id) on conflict do nothing;
     if found then
       unlocked:=unlocked+1;
       insert into public.notifications(user_id,title,content,type)
       values(p_user_id,'🥚 彩蛋成就解鎖！','恭喜你發現「'||a.title||'」'||case when a.reward_points>0 then '，獲得 +'||a.reward_points||' 積分。' else '。' end,'成長');
       if a.reward_points>0 then perform public.award_growth_points(p_user_id,a.reward_points,'解鎖成就：'||a.title,'achievement',a.id::text,'achievement:'||a.id::text||':'||p_user_id::text,null); end if;
     end if;
   end if;
 end loop;
 return unlocked;
end; $function$;


CREATE OR REPLACE FUNCTION public.check_activity_badges(p_user_id uuid DEFAULT auth.uid())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid:=coalesce(p_user_id,auth.uid());
  v_count integer; v_points integer; v_no_show integer; v_unlocked integer:=0; b record;
begin
  if v_user is null then raise exception '請先登入'; end if;
  if auth.uid() is null or (p_user_id is not null and p_user_id is distinct from auth.uid() and not exists(select 1 from public.profiles where id=auth.uid() and role='admin')) then raise exception '沒有權限'; end if;
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
end $function$
;

REVOKE EXECUTE ON FUNCTION public.admin_delete_growth_reward(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.award_growth_points(uuid, integer, text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_growth_achievements(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.refresh_growth_level(uuid) FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON FUNCTION public._refresh_growth_level_internal(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_growth_reward(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_growth_achievements(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.check_activity_badges(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_activity_badges(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_download_count(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_download_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_growth_level(uuid) TO authenticated;


-- Apply least-privilege EXECUTE grants to every public SECURITY DEFINER routine.
-- Trigger functions are invoked by their table triggers, not directly by API roles.
DO $acl_hardening$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure AS signature,
           p.proname,
           p.prorettype = 'trigger'::regtype AS is_trigger
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.prokind = 'f'
  LOOP
    IF r.is_trigger THEN
      EXECUTE format(
        'REVOKE ALL PRIVILEGES ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
        r.signature
      );
    ELSE
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',
        r.signature
      );

      IF r.proname IN ('award_growth_points', '_refresh_growth_level_internal') THEN
        EXECUTE format(
          'REVOKE EXECUTE ON FUNCTION %s FROM authenticated',
          r.signature
        );
      ELSE
        EXECUTE format(
          'GRANT EXECUTE ON FUNCTION %s TO authenticated',
          r.signature
        );
      END IF;
    END IF;
  END LOOP;
END;
$acl_hardening$;

COMMIT;
