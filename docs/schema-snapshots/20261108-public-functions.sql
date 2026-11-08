-- Catalog-reconstructed public function definitions.
-- Function owners, ACLs, comments and extension-managed functions are not fully represented.
CREATE OR REPLACE FUNCTION public.admin_activity_analytics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v jsonb;
begin
 if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以查看活動分析'; end if;
 select jsonb_build_object(
  'competitions',(select count(*) from public.competitions),
  'published',(select count(*) from public.competitions where published=true),
  'registrations',(select count(*) from public.competition_registrations where status in ('active','approved')),
  'attended',(select count(*) from public.competition_attendance where status in ('checked_in','late')),
  'late',(select count(*) from public.competition_attendance where status='late'),
  'no_show',(select count(*) from public.competition_attendance where status='no_show'),
  'attendance_points',(select coalesce(sum(points_awarded),0) from public.competition_attendance),
  'completion_points',(select coalesce(sum(completion_points_awarded),0) from public.competition_attendance),
  'badges',(select count(*) from public.user_activity_badges)
 ) into v;
 return v;
end $function$;


CREATE OR REPLACE FUNCTION public.admin_adjust_growth_points(p_user_id uuid, p_amount integer, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.is_admin() then raise exception '沒有管理員權限'; end if;
 if p_reason is null or trim(p_reason)='' then raise exception '請填寫調整原因'; end if;
 return public.award_growth_points(p_user_id,p_amount,p_reason,'admin',null,null,auth.uid());
end; $function$;


CREATE OR REPLACE FUNCTION public.admin_apply_competition_rewards(p_competition_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_rule record; v_att record; v_granted integer:=0; v_points integer:=0; v_badges integer:=0;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以發放活動獎勵'; end if;
  for v_rule in select * from public.competition_reward_rules where competition_id=p_competition_id and enabled=true loop
    for v_att in select * from public.competition_attendance where competition_id=p_competition_id and status in ('checked_in','late') loop
      begin
        insert into public.competition_reward_grants(competition_id,reward_rule_id,user_id) values(p_competition_id,v_rule.id,v_att.user_id);
        if v_rule.reward_type='points' then
          update public.profiles set growth_points=coalesce(growth_points,0)+v_rule.reward_value where id=v_att.user_id;
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
    update public.profiles p set growth_level=coalesce((select gl.code from public.growth_levels gl where gl.min_points<=p.growth_points order by gl.min_points desc limit 1),p.growth_level,'newbie') where p.id=v_att.user_id;
  end loop;
  return jsonb_build_object('success',true,'grants',v_granted,'points',v_points,'badges',v_badges);
end $function$;


CREATE OR REPLACE FUNCTION public.admin_cancel_order(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_order public.orders%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以取消訂單'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception '找不到訂單'; end if;
  if v_order.status='completed' then raise exception '已完成的訂單不能取消'; end if;
  update public.orders set status='cancelled',cancelled_at=now(),updated_at=now() where id=p_order_id returning * into v_order;
  begin
    insert into public.notifications(user_id,type,title,content)
    values(v_order.user_id,'訂單','❌ 訂單已取消','訂單 '||v_order.order_no||' 已被管理員取消。');
  exception when others then null;
  end;
  return jsonb_build_object('success',true,'order_no',v_order.order_no,'status',v_order.status);
end $function$;


CREATE OR REPLACE FUNCTION public.admin_complete_order(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_order public.orders%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以完成訂單'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception '找不到訂單'; end if;
  if v_order.status<>'paid' then raise exception '只有已付款訂單才能完成'; end if;
  update public.orders set status='completed',completed_at=now(),updated_at=now() where id=p_order_id returning * into v_order;
  begin
    insert into public.notifications(user_id,type,title,content)
    values(v_order.user_id,'訂單','📦 訂單已完成','訂單 '||v_order.order_no||' 已完成。');
  exception when others then null;
  end;
  return jsonb_build_object('success',true,'order_no',v_order.order_no,'status',v_order.status);
end $function$;


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
  if caller_role <> 'admin' then
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


CREATE OR REPLACE FUNCTION public.admin_delete_video(p_video_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin_user() then raise exception 'not authorized'; end if;
  delete from public.videos where id=p_video_id;
  return found;
end;
$function$;


CREATE OR REPLACE FUNCTION public.admin_grant_competition_reward(p_competition_id uuid, p_reward_type text, p_title text, p_description text DEFAULT NULL::text, p_points integer DEFAULT NULL::integer, p_badge_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_rule public.competition_reward_rules%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以設定活動獎勵'; end if;
  if p_reward_type not in ('points','badge') then raise exception '獎勵類型錯誤'; end if;
  if p_reward_type='points' and greatest(coalesce(p_points,0),0)=0 then raise exception '積分獎勵必須大於 0'; end if;
  if p_reward_type='badge' and p_badge_id is null then raise exception '徽章獎勵需要指定徽章'; end if;
  insert into public.competition_reward_rules(competition_id,reward_type,reward_value,badge_id,title,description)
  values(p_competition_id,p_reward_type,case when p_reward_type='points' then greatest(coalesce(p_points,0),0) else null end,p_badge_id,p_title,p_description)
  returning * into v_rule;
  return jsonb_build_object('success',true,'rule_id',v_rule.id);
end $function$;


CREATE OR REPLACE FUNCTION public.admin_mark_competition_attendance(p_attendance_id uuid, p_status text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin uuid := auth.uid();
  v_row public.competition_attendance%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以修改簽到紀錄'; end if;
  if p_status not in ('checked_in','late','no_show','cancelled') then raise exception '無效的簽到狀態'; end if;
  update public.competition_attendance
  set status=p_status,note=nullif(trim(coalesce(p_note,'')),''),checked_in_at=case when p_status in ('checked_in','late') and checked_in_at is null then now() else checked_in_at end,updated_at=now()
  where id=p_attendance_id returning * into v_row;
  if not found then raise exception '找不到簽到紀錄'; end if;
  return jsonb_build_object('success',true,'attendance_id',v_row.id,'status',v_row.status);
end;
$function$;


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
    update public.profiles set growth_points=coalesce(growth_points,0)+v_points where id=p_user_id;
    begin
      insert into public.growth_point_transactions(user_id,amount,reason,source_type) values(p_user_id,v_points,'活動簽到：' || v_comp.name,'activity_checkin');
    exception when others then null; end;
    update public.profiles p
      set growth_level = coalesce((select gl.code from public.growth_levels gl where gl.min_points <= p.growth_points order by gl.min_points desc limit 1), p.growth_level, 'newbie')
      where p.id=p_user_id;
  end if;
  return jsonb_build_object('success',true,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_att.points_awarded);
end;
$function$;


CREATE OR REPLACE FUNCTION public.admin_mark_order_paid(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin uuid:=auth.uid();
  v_order public.orders%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以確認收款'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception '找不到訂單'; end if;
  if v_order.status='cancelled' then raise exception '已取消的訂單不能確認收款'; end if;

  update public.orders set status='paid',paid_at=coalesce(paid_at,now()),updated_at=now() where id=p_order_id returning * into v_order;
  begin
    insert into public.notifications(user_id,type,title,content)
    values(v_order.user_id,'訂單','💵 已確認收到現金','訂單 '||v_order.order_no||' 已確認收到現金付款。');
  exception when others then null;
  end;
  return jsonb_build_object('success',true,'order_no',v_order.order_no,'status',v_order.status);
end $function$;


CREATE OR REPLACE FUNCTION public.admin_promote_competition_waitlist(p_waitlist_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_admin uuid:=auth.uid();
  v_wait public.competition_waitlist%rowtype;
  v_comp public.competitions%rowtype;
  v_count integer;
  v_status text;
  v_reg public.competition_registrations%rowtype;
begin
  if not exists(select 1 from public.profiles where id=v_admin and role='admin') then raise exception '只有管理員可以遞補候補會員'; end if;
  select * into v_wait from public.competition_waitlist where id=p_waitlist_id and status='waiting' for update;
  if not found then raise exception '找不到等待中的候補'; end if;
  select * into v_comp from public.competitions where id=v_wait.competition_id for update;
  if not found then raise exception '找不到活動'; end if;
  if v_comp.registration_capacity is null then raise exception '此活動沒有設定名額上限'; end if;
  select count(*)::integer into v_count from public.competition_registrations where competition_id=v_comp.id and status in ('active','approved','pending');
  if v_count >= v_comp.registration_capacity then raise exception '目前仍沒有空缺名額'; end if;
  v_status:=case when coalesce(v_comp.registration_approval,false) then 'pending' else 'active' end;
  insert into public.competition_registrations(competition_id,user_id,member_no,nickname,email,note,status,custom_fields)
  values(v_comp.id,v_wait.user_id,v_wait.member_no,v_wait.nickname,v_wait.email,v_wait.note,v_status,'{}'::jsonb)
  returning * into v_reg;
  update public.competition_waitlist set status='promoted',promoted_at=now() where id=v_wait.id;
  return jsonb_build_object('success',true,'registration_id',v_reg.id,'user_id',v_wait.user_id,'status',v_status);
exception when unique_violation then
  raise exception '此會員已經有報名紀錄';
end;
$function$;


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

  update public.profiles
  set growth_points=0,growth_level='newbie'
  where id=p_user_id;

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
$function$;


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
    update public.profiles set growth_points=coalesce(growth_points,0)+v_completion where id=v_reg.user_id;
    begin insert into public.growth_point_transactions(user_id,amount,reason,source_type) values(v_reg.user_id,v_completion,'活動完成：'||v_comp.name,'activity_completion'); exception when others then null; end;
    update public.profiles p set growth_level=coalesce((select gl.code from public.growth_levels gl where gl.min_points<=p.growth_points order by gl.min_points desc limit 1),p.growth_level,'newbie') where p.id=v_reg.user_id;
    v_points:=v_points+v_completion;
   end if;
   v_completed:=v_completed+1;
  end if;
 end loop;
 update public.competitions set settled_at=now() where id=p_competition_id;
 v_reward:=public.admin_apply_competition_rewards(p_competition_id);
 return jsonb_build_object('success',true,'already',false,'completed',v_completed,'no_show',v_no_show,'completion_points',v_points,'rewards',v_reward,'settled_at',now());
end $function$;


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
  if caller_role <> 'admin' then raise exception '只有管理員可以管理獎勵'; end if;
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


CREATE OR REPLACE FUNCTION public.admin_upsert_video(p_video jsonb)
 RETURNS videos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.videos;
begin
  if not public.is_admin_user() then raise exception 'not authorized'; end if;
  if nullif(trim(p_video->>'title'),'') is null then raise exception '影片標題不能為空'; end if;
  if nullif(trim(p_video->>'youtube_id'),'') is null then raise exception 'YouTube 影片 ID 不能為空'; end if;
  if nullif(trim(p_video->>'youtube_url'),'') is null then raise exception 'YouTube 網址不能為空'; end if;
  if (p_video->>'id') is not null and nullif(p_video->>'id','') is not null then
    update public.videos set
      title=trim(p_video->>'title'), description=coalesce(p_video->>'description',''), youtube_url=trim(p_video->>'youtube_url'), youtube_id=trim(p_video->>'youtube_id'), thumbnail_url=coalesce(nullif(trim(p_video->>'thumbnail_url'),''),'https://img.youtube.com/vi/'||trim(p_video->>'youtube_id')||'/hqdefault.jpg'), category=coalesce(nullif(trim(p_video->>'category'),''),'其他'), featured=coalesce((p_video->>'featured')::boolean,false), published=coalesce((p_video->>'published')::boolean,true), sort_order=coalesce((p_video->>'sort_order')::integer,0), published_at=coalesce(nullif(p_video->>'published_at','')::timestamptz,now()), updated_at=now()
    where id=(p_video->>'id')::uuid returning * into r;
    if r.id is null then raise exception '找不到影片'; end if;
  else
    insert into public.videos(title,description,youtube_url,youtube_id,thumbnail_url,category,featured,published,sort_order,published_at)
    values(trim(p_video->>'title'),coalesce(p_video->>'description',''),trim(p_video->>'youtube_url'),trim(p_video->>'youtube_id'),coalesce(nullif(trim(p_video->>'thumbnail_url'),''),'https://img.youtube.com/vi/'||trim(p_video->>'youtube_id')||'/hqdefault.jpg'),coalesce(nullif(trim(p_video->>'category'),''),'其他'),coalesce((p_video->>'featured')::boolean,false),coalesce((p_video->>'published')::boolean,true),coalesce((p_video->>'sort_order')::integer,0),coalesce(nullif(p_video->>'published_at','')::timestamptz,now())) returning * into r;
  end if;
  return r;
end;
$function$;


CREATE OR REPLACE FUNCTION public.assign_member_no_and_nickname()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  new_level:=public.refresh_growth_level(p_user_id);

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
  if p_user_id is not null and p_user_id<>auth.uid() and not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then raise exception '沒有權限'; end if;
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
end $function$;


CREATE OR REPLACE FUNCTION public.check_competition_registration_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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


CREATE OR REPLACE FUNCTION public.checkin_competition(p_competition_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_comp public.competitions%rowtype;
  v_reg public.competition_registrations%rowtype;
  v_att public.competition_attendance%rowtype;
  v_points integer := 0;
  v_status text := 'checked_in';
begin
  if v_user is null then raise exception '請先登入會員帳號'; end if;
  select * into v_comp from public.competitions where id=p_competition_id and published=true;
  if not found then raise exception '找不到已公布的活動'; end if;
  if not coalesce(v_comp.checkin_enabled,false) then raise exception '此活動尚未開放簽到'; end if;
  if coalesce(v_comp.checkin_code,'') <> coalesce(trim(p_code),'') then raise exception '簽到碼錯誤'; end if;
  if v_comp.checkin_start_at is not null and now() < v_comp.checkin_start_at then raise exception '尚未到簽到時間'; end if;
  if v_comp.checkin_end_at is not null and now() > v_comp.checkin_end_at then raise exception '簽到時間已結束'; end if;

  select * into v_reg from public.competition_registrations
  where competition_id=p_competition_id and user_id=v_user and status in ('active','approved')
  order by created_at desc limit 1;
  if not found then raise exception '請先完成活動報名'; end if;

  select * into v_att from public.competition_attendance where competition_id=p_competition_id and user_id=v_user;
  if found and v_att.status in ('checked_in','late') then
    return jsonb_build_object('success',true,'already',true,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_att.points_awarded);
  end if;

  v_points := greatest(coalesce(v_comp.checkin_points,0),0);
  if v_att.id is null then
    insert into public.competition_attendance(competition_id,registration_id,user_id,status,checked_in_at,points_awarded)
    values(v_comp.id,v_reg.id,v_user,v_status,now(),v_points)
    returning * into v_att;
  else
    update public.competition_attendance set registration_id=v_reg.id,status=v_status,checked_in_at=now(),points_awarded=v_points,updated_at=now() where id=v_att.id returning * into v_att;
  end if;

  if v_points > 0 then
    update public.profiles
      set growth_points = coalesce(growth_points,0) + v_points
      where id = v_user;
    begin
      insert into public.growth_point_transactions(user_id,amount,reason,source_type)
        values(v_user,v_points,'活動簽到：' || v_comp.name,'activity_checkin');
    exception when others then
      null;
    end;
    update public.profiles p
      set growth_level = coalesce((select gl.code from public.growth_levels gl where gl.min_points <= p.growth_points order by gl.min_points desc limit 1), p.growth_level, 'newbie')
      where p.id=v_user;
  end if;

  begin
    perform public.record_growth_activity();
  exception when others then
    null;
  end;

  return jsonb_build_object('success',true,'already',false,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_points);
end;
$function$;


CREATE OR REPLACE FUNCTION public.close_my_support_ticket(p_ticket_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.support_tickets
     set status='closed', updated_at=now()
   where id=p_ticket_id
     and user_id=auth.uid()
     and status <> 'closed';
  return found;
end;
$function$;


CREATE OR REPLACE FUNCTION public.complete_growth_task(p_task_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
   if t.reward_points>0 then perform public.award_growth_points(uid,t.reward_points,'完成任務：'||t.title,'task',t.id::text,'task:'||t.id::text||':'||uid::text||':'||cycle,null); end if;
   insert into public.notifications(user_id,title,content,type)
   values(uid,'🎯 任務完成！','你已完成「'||t.title||'」'||case when t.reward_points>0 then '，獲得 +'||t.reward_points||' 積分。' else '。' end,'成長');
   return true;
 end if;
 return false;
end; $function$;


CREATE OR REPLACE FUNCTION public.create_cash_order(p_product_id uuid, p_quantity integer DEFAULT 1, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid:=auth.uid();
  v_product public.products%rowtype;
  v_order public.orders%rowtype;
  v_total numeric(12,2);
begin
  if v_user is null then raise exception '請先登入會員帳號'; end if;
  if greatest(coalesce(p_quantity,0),0) < 1 then raise exception '購買數量至少為 1'; end if;

  select * into v_product from public.products where id=p_product_id and active=true for update;
  if not found then raise exception '商品不存在或目前未上架'; end if;
  if coalesce(v_product.price,0) < 0 then raise exception '商品價格無效'; end if;

  v_total:=round(coalesce(v_product.price,0)*p_quantity,2);
  insert into public.orders(user_id,status,payment_method,total_amount,note)
  values(v_user,'pending_payment','cash',v_total,left(coalesce(p_note,''),500))
  returning * into v_order;

  insert into public.order_items(order_id,product_id,product_name,unit_price,quantity,subtotal)
  values(v_order.id,v_product.id,v_product.name,v_product.price,p_quantity,v_total);

  begin
    insert into public.notifications(user_id,type,title,content)
    values(v_user,'訂單','🧾 訂單已建立','訂單 '||v_order.order_no||' 已建立，付款方式為線下現金，應付 NT$ '||to_char(v_total,'FM999,999,990.00')||'。');
  exception when others then null;
  end;

  return jsonb_build_object('success',true,'order_id',v_order.id,'order_no',v_order.order_no,'total_amount',v_total,'payment_method','cash');
end $function$;


CREATE OR REPLACE FUNCTION public.ensure_visitor_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
begin
  insert into public.profiles(id,role)
  values(NEW.id,'visitor')
  on conflict(id) do update set role='visitor';
  return NEW;
end;
$function$;


CREATE OR REPLACE FUNCTION public.growth_registration_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if new.status in ('active','pending','approved') then
   perform public.award_growth_points(new.user_id,5,'完成活動／比賽報名','registration',new.id::text,'registration:'||new.id::text,null);
 end if;
 return new;
end; $function$;


CREATE OR REPLACE FUNCTION public.growth_result_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pts integer:=10; published boolean;
begin
 if new.user_id is null then return new; end if;
 select c.published into published from public.competitions c where c.id=new.competition_id;
 if coalesce(published,false) then
   pts:=case when new.place=1 then 50 when new.place=2 then 30 when new.place=3 then 20 else 10 end;
   perform public.award_growth_points(new.user_id,pts,'比賽成績：第 '||new.place||' 名','result',new.id::text,'result:'||new.id::text,null);
 end if;
 return new;
end; $function$;


CREATE OR REPLACE FUNCTION public.increment_download_count(p_file_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.download_files
  SET
    download_count = COALESCE(download_count, 0) + 1,
    updated_at = now()
  WHERE id = p_file_id
    AND published = true;
END;
$function$;


CREATE OR REPLACE FUNCTION public.is_admin_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$function$;


CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $function$;


CREATE OR REPLACE FUNCTION public.join_competition_waitlist(p_competition_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid:=auth.uid();
  v_comp public.competitions%rowtype;
  v_profile public.profiles%rowtype;
  v_email text;
  v_existing public.competition_waitlist%rowtype;
  v_registered integer;
  v_position integer;
  v_row public.competition_waitlist%rowtype;
begin
  if v_user is null then raise exception '請先登入會員帳號'; end if;
  select * into v_comp from public.competitions where id=p_competition_id and published=true;
  if not found then raise exception '找不到已公布的活動'; end if;
  if not coalesce(v_comp.waitlist_enabled,true) then raise exception '此活動未開放候補'; end if;
  if v_comp.registration_deadline is not null and now()>v_comp.registration_deadline then raise exception '報名已截止'; end if;
  if v_comp.registration_capacity is null then raise exception '此活動沒有設定名額上限'; end if;

  if exists(select 1 from public.competition_registrations r where r.competition_id=p_competition_id and r.user_id=v_user and r.status in ('active','approved','pending')) then
    raise exception '你已經有這場活動的報名紀錄';
  end if;
  select * into v_existing from public.competition_waitlist where competition_id=p_competition_id and user_id=v_user;
  if found and v_existing.status='waiting' then
    return jsonb_build_object('success',true,'already',true,'waitlist_id',v_existing.id,'position',v_existing.position,'status',v_existing.status);
  end if;

  select count(*)::integer into v_registered from public.competition_registrations
  where competition_id=p_competition_id and status in ('active','approved','pending');
  if v_registered < v_comp.registration_capacity then raise exception '目前仍有名額，可以直接報名'; end if;

  select * into v_profile from public.profiles where id=v_user;
  select email into v_email from auth.users where id=v_user;
  select coalesce(max(position),0)+1 into v_position from public.competition_waitlist where competition_id=p_competition_id;
  if found and v_existing.id is not null then
    update public.competition_waitlist set status='waiting',position=v_position,created_at=now(),promoted_at=null,note=nullif(trim(coalesce(p_note,'')),'') where id=v_existing.id returning * into v_row;
  else
    insert into public.competition_waitlist(competition_id,user_id,member_no,nickname,email,note,position)
    values(p_competition_id,v_user,v_profile.member_no,v_profile.nickname,v_email,nullif(trim(coalesce(p_note,'')),''),v_position)
    returning * into v_row;
  end if;
  return jsonb_build_object('success',true,'already',false,'waitlist_id',v_row.id,'position',v_row.position,'status',v_row.status);
end;
$function$;


CREATE OR REPLACE FUNCTION public.protect_profile_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    -- 管理員可以正常管理會員資料
    IF public.is_admin() THEN
        RETURN NEW;
    END IF;

    -- 一般使用者不得修改重要欄位
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


CREATE OR REPLACE FUNCTION public.record_growth_activity()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid:=auth.uid(); d date:=current_date; streak integer:=0; days integer:=0; cur date; new_achievements integer:=0;
begin
 if uid is null then raise exception '請先登入'; end if;
 insert into public.growth_activity_days(user_id,activity_date,source) values(uid,d,'visit') on conflict do nothing;
 select count(*) into days from public.growth_activity_days where user_id=uid and activity_date >= date_trunc('month',current_date)::date;
 cur:=d; while exists(select 1 from public.growth_activity_days where user_id=uid and activity_date=cur) loop streak:=streak+1; cur:=cur-1; end loop;
 new_achievements:=public.check_growth_achievements(uid);
 return jsonb_build_object('active_days',days,'login_streak',streak,'new_achievements',new_achievements);
end; $function$;


CREATE OR REPLACE FUNCTION public.redeem_growth_reward(p_reward_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  r public.growth_rewards%rowtype;
  p public.profiles%rowtype;
  unlocked boolean := false;
  user_count integer := 0;
  coupon uuid;
  new_points integer;
  coupon_code text;
  coupon_expires timestamptz;
  level_ok boolean := false;
  now_ts timestamptz := now();
begin
  if uid is null then raise exception '請先登入'; end if;

  select * into r from public.growth_rewards
  where id=p_reward_id and enabled=true
  for update;
  if r.id is null then raise exception '找不到可兌換的獎勵'; end if;

  if r.available_from is not null and r.available_from > now_ts then
    raise exception '此獎勵尚未開始兌換';
  end if;
  if r.available_until is not null and r.available_until < now_ts then
    raise exception '此獎勵已結束兌換';
  end if;

  select * into p from public.profiles where id=uid for update;
  if p.id is null then raise exception '找不到會員'; end if;
  if coalesce(p.growth_points,0) < r.point_cost then
    raise exception '積分不足，還需要 % 點', r.point_cost-coalesce(p.growth_points,0);
  end if;

  select exists(
    select 1 from public.growth_levels g
    where g.code=r.min_level
      and g.min_points <= coalesce(p.growth_points,0)
  ) into level_ok;
  if r.min_level is not null and not level_ok then
    raise exception '會員等級不足，需達到 %', r.min_level;
  end if;

  if r.required_achievement_id is not null then
    select exists(
      select 1 from public.growth_user_achievements
      where user_id=uid and achievement_id=r.required_achievement_id
    ) into unlocked;
    if not unlocked then raise exception '尚未解鎖指定成就'; end if;
  end if;

  select count(*) into user_count
  from public.growth_reward_redemptions
  where reward_id=r.id and user_id=uid and status='redeemed';
  if r.user_limit is not null and user_count >= r.user_limit then
    raise exception '已達此獎勵的個人兌換上限';
  end if;
  if r.total_limit is not null and coalesce(r.redeemed_count,0) >= r.total_limit then
    raise exception '此獎勵已兌換完畢';
  end if;

  new_points := coalesce(p.growth_points,0) - r.point_cost;
  perform public.award_growth_points(
    uid,-r.point_cost,'兌換獎勵：'||r.title,'reward',r.id::text,
    'reward:'||r.id::text||':'||uid::text||':'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),null
  );

  coupon_code := upper(substr(regexp_replace(coalesce(r.code,'REWARD'),'[^A-Za-z0-9]','','g'),1,12))
    || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  if r.coupon_expires_days is not null then
    coupon_expires := now_ts + make_interval(days=>r.coupon_expires_days);
  elsif r.available_until is not null then
    coupon_expires := r.available_until;
  end if;

  insert into public.coupons(user_id,title,description,code,discount,expires_at)
  values(
    uid,
    coalesce(nullif(r.coupon_title,''),r.title),
    coalesce(r.coupon_description,r.description),
    coupon_code,
    r.coupon_discount,
    coupon_expires
  ) returning id into coupon;

  insert into public.growth_reward_redemptions(reward_id,user_id,point_cost,status,coupon_id)
  values(r.id,uid,r.point_cost,'redeemed',coupon);

  update public.growth_rewards
  set redeemed_count=coalesce(redeemed_count,0)+1, updated_at=now()
  where id=r.id;

  insert into public.notifications(user_id,title,content,type)
  values(uid,'🎁 獎勵兌換成功','你已使用 '||r.point_cost||' 點兌換「'||r.title||'」，優惠券已加入「我的 → 我的優惠券」。','優惠券');

  return jsonb_build_object(
    'success',true,
    'reward_id',r.id,
    'coupon_id',coupon,
    'remaining_points',new_points,
    'category',r.category
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.refresh_growth_level(p_user_id uuid)
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


CREATE OR REPLACE FUNCTION public.set_competition_publish_time()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if NEW.published = true then
    NEW.published_at := now();
  else
    NEW.published_at := null;
  end if;
  return NEW;
end;
$function$;


CREATE OR REPLACE FUNCTION public.use_growth_coupon(p_coupon_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_coupon public.coupons%rowtype;
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', '請先登入');
  end if;
  select * into v_coupon from public.coupons where id=p_coupon_id for update;
  if not found then return jsonb_build_object('success', false, 'error', '找不到這張優惠券'); end if;
  if v_coupon.user_id <> v_user_id then return jsonb_build_object('success', false, 'error', '無權使用這張優惠券'); end if;
  if v_coupon.used then return jsonb_build_object('success', false, 'error', '這張優惠券已使用'); end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at < now() then return jsonb_build_object('success', false, 'error', '這張優惠券已過期'); end if;
  update public.coupons set used=true, used_at=now() where id=v_coupon.id;
  insert into public.notifications(user_id,title,content,type)
  values(v_user_id,'🎟️ 優惠券已使用','你已使用優惠券：'||coalesce(v_coupon.title,v_coupon.code),'優惠券');
  return jsonb_build_object('success',true,'coupon_id',v_coupon.id,'code',v_coupon.code,'used_at',now());
end;
$function$;


