-- Candidate-only fix for registration reward rollback and overly broad RPC ACLs.
-- DO NOT apply to production until isolated tests pass and migration baseline/order is reviewed.
BEGIN;

-- Dedicated NOLOGIN owner for only the two growth-maintenance SECURITY DEFINER
-- functions. Its table privileges are deliberately column/table scoped.
DO $role$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_points_executor') THEN
    RAISE EXCEPTION 'growth_points_executor already exists; review the role before applying this migration';
  END IF;
  CREATE ROLE growth_points_executor NOLOGIN BYPASSRLS;
END
$role$;

GRANT USAGE ON SCHEMA public TO growth_points_executor;
-- PostgreSQL requires CREATE on the target schema while transferring ownership.
GRANT CREATE ON SCHEMA public TO growth_points_executor;
GRANT EXECUTE ON FUNCTION public.is_admin() TO growth_points_executor;
GRANT SELECT ON public.profiles, public.growth_levels,
                public.growth_point_transactions
TO growth_points_executor;
GRANT UPDATE (growth_points, growth_level)
ON public.profiles TO growth_points_executor;
GRANT INSERT ON public.growth_point_transactions, public.notifications
TO growth_points_executor;

-- These functions are the only functions owned by this restricted executor.
ALTER FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) OWNER TO growth_points_executor;
ALTER FUNCTION public.refresh_growth_level(uuid)
  OWNER TO growth_points_executor;
REVOKE CREATE ON SCHEMA public FROM growth_points_executor;

CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
    IF public.is_admin() THEN
        RETURN NEW;
    END IF;

    -- Only the dedicated function owner may update these two system fields.
    -- The other protected identity/authorization fields remain immutable.
    IF current_user = 'growth_points_executor'
       AND (NEW.growth_points IS DISTINCT FROM OLD.growth_points
            OR NEW.growth_level IS DISTINCT FROM OLD.growth_level)
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.role IS NOT DISTINCT FROM OLD.role
       AND NEW.member_no IS NOT DISTINCT FROM OLD.member_no
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
    THEN
        RETURN NEW;
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.member_no IS DISTINCT FROM OLD.member_no
       OR NEW.growth_points IS DISTINCT FROM OLD.growth_points
       OR NEW.growth_level IS DISTINCT FROM OLD.growth_level
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'You are not allowed to modify protected profile fields.';
    END IF;

    RETURN NEW;
END;
$function$;

-- These routines must not be callable directly by public/ordinary members.
-- Trusted SECURITY DEFINER admin routines and the postgres-owned trigger
-- function continue to invoke them through their existing trusted context.
REVOKE EXECUTE ON FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) TO service_role;

REVOKE EXECUTE ON FUNCTION public.refresh_growth_level(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_growth_level(uuid)
  TO service_role;

-- Route member check-in rewards through the restricted growth executor.
-- Previously this SECURITY DEFINER function updated profiles directly as
-- postgres, which the protected-field trigger correctly rejects for members.
-- Preserve production check-in behavior while routing protected profile
-- updates through the narrowly-owned growth RPC.
CREATE OR REPLACE FUNCTION public.checkin_competition(p_competition_id uuid, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_comp public.competitions%rowtype;
  v_reg public.competition_registrations%rowtype;
  v_att public.competition_attendance%rowtype;
  v_points integer := 0;
  v_status text := 'checked_in';
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '請先登入會員帳號'; END IF;
  SELECT * INTO v_comp FROM public.competitions WHERE id=p_competition_id AND published=true;
  IF NOT FOUND THEN RAISE EXCEPTION '找不到已公布的活動'; END IF;
  IF NOT coalesce(v_comp.checkin_enabled,false) THEN RAISE EXCEPTION '此活動尚未開放簽到'; END IF;
  IF coalesce(v_comp.checkin_code,'') <> coalesce(trim(p_code),'') THEN RAISE EXCEPTION '簽到碼錯誤'; END IF;
  IF v_comp.checkin_start_at IS NOT NULL AND now() < v_comp.checkin_start_at THEN RAISE EXCEPTION '尚未到簽到時間'; END IF;
  IF v_comp.checkin_end_at IS NOT NULL AND now() > v_comp.checkin_end_at THEN RAISE EXCEPTION '簽到時間已結束'; END IF;

  SELECT * INTO v_reg FROM public.competition_registrations
  WHERE competition_id=p_competition_id AND user_id=v_user AND status IN ('active','approved')
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION '請先完成活動報名'; END IF;

  SELECT * INTO v_att FROM public.competition_attendance WHERE competition_id=p_competition_id AND user_id=v_user;
  IF FOUND AND v_att.status IN ('checked_in','late') THEN
    RETURN jsonb_build_object('success',true,'already',true,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_att.points_awarded);
  END IF;

  v_points := greatest(coalesce(v_comp.checkin_points,0),0);
  IF v_att.id IS NULL THEN
    INSERT INTO public.competition_attendance(competition_id,registration_id,user_id,status,checked_in_at,points_awarded)
    VALUES(v_comp.id,v_reg.id,v_user,v_status,now(),v_points)
    RETURNING * INTO v_att;
  ELSE
    UPDATE public.competition_attendance
    SET registration_id=v_reg.id,status=v_status,checked_in_at=now(),points_awarded=v_points,updated_at=now()
    WHERE id=v_att.id RETURNING * INTO v_att;
  END IF;

  IF v_points > 0 THEN
    PERFORM public.award_growth_points(
      v_user, v_points, '活動簽到：' || v_comp.name,
      'activity_checkin', v_comp.id::text,
      'checkin:' || v_comp.id::text || ':' || v_user::text, NULL
    );
  END IF;

  BEGIN
    PERFORM public.record_growth_activity();
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success',true,'already',false,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_points);
END;
$function$;

-- Route all remaining trusted competition/growth writers through the
-- restricted growth executor rather than direct profile column updates.
CREATE OR REPLACE FUNCTION public.admin_apply_competition_rewards(p_competition_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_rule record; v_att record; v_granted integer:=0; v_points integer:=0; v_badges integer:=0; v_grant_id uuid;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以發放活動獎勵'; end if;
  for v_rule in select * from public.competition_reward_rules where competition_id=p_competition_id and enabled=true loop
    for v_att in select * from public.competition_attendance where competition_id=p_competition_id and status in ('checked_in','late') loop
      begin
        insert into public.competition_reward_grants(competition_id,reward_rule_id,user_id)
        values(p_competition_id,v_rule.id,v_att.user_id) returning id into v_grant_id;
        if v_rule.reward_type='points' then
          perform public.award_growth_points(
            v_att.user_id, v_rule.reward_value, '活動獎勵：'||v_rule.title,
            'activity_reward', v_grant_id::text,
            'activity-reward:'||v_grant_id::text, v_admin
          );
          begin insert into public.growth_point_transactions(user_id,amount,reason,source_type) values(v_att.user_id,v_rule.reward_value,'活動獎勵：'||v_rule.title,'activity_reward'); exception when others then null; end;
          v_points:=v_points+v_rule.reward_value;
        else
          insert into public.user_activity_badges(user_id,badge_id) values(v_att.user_id,v_rule.badge_id) on conflict do nothing;
          v_badges:=v_badges+1;
        end if;
        v_granted:=v_granted+1;
      exception when unique_violation then null;
      end;
    end loop;
  end loop;
  for v_att in select distinct user_id from public.competition_attendance where competition_id=p_competition_id and status in ('checked_in','late') loop
    perform public.check_activity_badges(v_att.user_id);
  end loop;
  return jsonb_build_object('success',true,'grants',v_granted,'points',v_points,'badges',v_badges);
end $function$


CREATE OR REPLACE FUNCTION public.admin_mark_competition_member_attendance(p_competition_id uuid, p_user_id uuid, p_status text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin uuid := auth.uid();
  v_reg public.competition_registrations%rowtype;
  v_att public.competition_attendance%rowtype;
  v_comp public.competitions%rowtype;
  v_points integer := 0;
  v_was_awarded integer := 0;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以修改簽到紀錄'; end if;
  if p_status not in ('checked_in','late','no_show','cancelled') then raise exception '無效的簽到狀態'; end if;
  select * into v_reg from public.competition_registrations where competition_id=p_competition_id and user_id=p_user_id and status in ('active','approved') order by created_at desc limit 1;
  if not found then raise exception '此會員尚未完成活動報名'; end if;
  select * into v_comp from public.competitions where id=p_competition_id;
  if not found then raise exception '找不到活動'; end if;
  select * into v_att from public.competition_attendance where competition_id=p_competition_id and user_id=p_user_id for update;
  if not found then
    v_points := case when p_status in ('checked_in','late') then greatest(coalesce(v_comp.checkin_points,0),0) else 0 end;
    insert into public.competition_attendance(competition_id,registration_id,user_id,status,checked_in_at,points_awarded,note)
    values(p_competition_id,v_reg.id,p_user_id,p_status,case when p_status in ('checked_in','late') then now() else null end,v_points,nullif(trim(coalesce(p_note,'')),'')) returning * into v_att;
  else
    if p_status in ('checked_in','late') and coalesce(v_att.points_awarded,0)=0 then
      v_points := greatest(coalesce(v_comp.checkin_points,0),0);
      update public.competition_attendance set status=p_status,checked_in_at=coalesce(checked_in_at,now()),points_awarded=v_points,note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=v_att.id returning * into v_att;
    else
      update public.competition_attendance set status=p_status,note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=v_att.id returning * into v_att;
    end if;
  end if;
  if v_points > 0 then
    perform public.award_growth_points(
      p_user_id, v_points, '活動簽到：' || v_comp.name,
      'activity_checkin', p_competition_id::text,
      'admin-checkin:' || p_competition_id::text || ':' || p_user_id::text, v_admin
    );
  end if;
  return jsonb_build_object('success',true,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_att.points_awarded);
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_reset_growth_member(p_user_id uuid, p_reason text DEFAULT '管理員手動重置'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p public.profiles%rowtype;
  rid uuid;
  reset_no integer;
  before_active integer:=0;
  before_streak integer:=0;
  before_tasks integer:=0;
  before_achievements integer:=0;
  cur date;
  n integer:=0;
  a record;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception '只有管理員可以執行會員成長重置';
  end if;
  if p_user_id is null then raise exception '缺少會員 ID'; end if;

  select * into p from public.profiles where id=p_user_id for update;
  if not found then raise exception '找不到會員'; end if;

  select count(*) into before_active
  from public.growth_activity_days
  where user_id=p_user_id
    and activity_date >= date_trunc('month', current_date)::date;
  if before_active=0 then
    select count(*) into before_active from public.growth_activity_days where user_id=p_user_id;
  end if;

  if exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=current_date) then
    cur:=current_date;
    while exists(select 1 from public.growth_activity_days where user_id=p_user_id and activity_date=cur) loop
      before_streak:=before_streak+1;
      cur:=cur-1;
    end loop;
  end if;

  select count(*) into before_tasks
  from public.growth_user_tasks
  where user_id=p_user_id and completed_at is not null;

  select count(*) into before_achievements
  from public.growth_user_achievements
  where user_id=p_user_id;

  select coalesce(max(reset_no),0)+1 into reset_no
  from public.growth_reset_history
  where user_id=p_user_id;

  insert into public.growth_reset_history(
    user_id,reset_by,reset_no,reason,before_points,after_points,
    before_level,after_level,before_active_days,before_login_streak,
    before_completed_tasks,before_achievements
  ) values (
    p_user_id,auth.uid(),reset_no,
    coalesce(nullif(trim(p_reason),''),'管理員手動重置'),
    coalesce(p.growth_points,0),0,
    coalesce(p.growth_level,'newbie'),'newbie',
    before_active,before_streak,before_tasks,before_achievements
  ) returning id into rid;

  -- 封存目前已解鎖成就，讓重置後可以重新挑戰；歷史仍保留。
  insert into public.growth_achievement_unlock_history(
    user_id,achievement_id,unlocked_at,reset_history_id,snapshot_title,snapshot_reward_points
  )
  select ua.user_id,ua.achievement_id,ua.unlocked_at,rid,a.title,a.reward_points
  from public.growth_user_achievements ua
  join public.growth_achievements a on a.id=ua.achievement_id
  where ua.user_id=p_user_id;

  delete from public.growth_user_achievements where user_id=p_user_id;
  delete from public.growth_user_tasks where user_id=p_user_id;
  delete from public.growth_activity_days where user_id=p_user_id;

  if coalesce(p.growth_points,0) > 0 then
    perform public.award_growth_points(
      p_user_id, -p.growth_points,
      coalesce(nullif(trim(p_reason),''),'管理員手動重置'),
      'admin_reset', rid::text, 'growth-reset:' || rid::text, auth.uid()
    );
  else
    perform public.refresh_growth_level(p_user_id);
  end if;

  insert into public.notifications(user_id,title,content,type)
  values(
    p_user_id,
    '🏆 會員成長已重置',
    '你的會員成長進度已重置為 0 點／新手等級；歷史紀錄與已兌換獎勵仍會保留。',
    '成長'
  );

  return jsonb_build_object(
    'reset_id',rid,
    'reset_no',reset_no,
    'before_points',coalesce(p.growth_points,0),
    'after_points',0,
    'before_level',coalesce(p.growth_level,'newbie'),
    'after_level','newbie',
    'before_active_days',before_active,
    'before_login_streak',before_streak,
    'before_completed_tasks',before_tasks,
    'before_achievements',before_achievements
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_settle_competition(p_competition_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_comp public.competitions%rowtype; v_reg record; v_att public.competition_attendance%rowtype; v_completion integer; v_completed integer:=0; v_no_show integer:=0; v_points integer:=0; v_reward jsonb;
begin
 if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以結算活動'; end if;
 select * into v_comp from public.competitions where id=p_competition_id for update;
 if not found then raise exception '找不到活動'; end if;
 if v_comp.settled_at is not null then return jsonb_build_object('success',true,'already',true,'settled_at',v_comp.settled_at); end if;
 v_completion:=greatest(coalesce(v_comp.completion_points,0),0);
 for v_reg in select r.* from public.competition_registrations r where r.competition_id=p_competition_id and r.status in ('active','approved') loop
  select * into v_att from public.competition_attendance where competition_id=p_competition_id and user_id=v_reg.user_id for update;
  if not found then
   insert into public.competition_attendance(competition_id,registration_id,user_id,status,note) values(p_competition_id,v_reg.id,v_reg.user_id,'no_show','活動結算自動判定未到') returning * into v_att;
   v_no_show:=v_no_show+1;
  elsif v_att.status in ('checked_in','late') then
   if v_completion>0 and coalesce(v_att.completion_points_awarded,0)=0 then
    update public.competition_attendance set completion_points_awarded=v_completion,updated_at=now() where id=v_att.id;
    perform public.award_growth_points(
      v_reg.user_id, v_completion, '活動完成：'||v_comp.name,
      'activity_completion', p_competition_id::text,
      'completion:'||p_competition_id::text||':'||v_reg.user_id::text, v_admin
    );
    v_points:=v_points+v_completion;
   end if;
   v_completed:=v_completed+1;
  end if;
 end loop;
 update public.competitions set settled_at=now() where id=p_competition_id;
 v_reward:=public.admin_apply_competition_rewards(p_competition_id);
 return jsonb_build_object('success',true,'already',false,'completed',v_completed,'no_show',v_no_show,'completion_points',v_points,'rewards',v_reward,'settled_at',now());
end $function$


COMMIT;
