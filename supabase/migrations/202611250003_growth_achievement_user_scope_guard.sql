-- Candidate-only authorization fix for member-scoped growth achievement/badge RPCs.
-- Apply only in isolated CI after reviewing the production migration baseline.
BEGIN;

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
 -- SECURITY DEFINER must not trust a caller-supplied target user id.
 if auth.uid() is null then raise exception '請先登入'; end if;
 if p_user_id is null then p_user_id:=auth.uid(); end if;
 if p_user_id is distinct from auth.uid() and not public.is_admin() then
   raise exception '沒有權限';
 end if;

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
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_user_id is null then v_user:=auth.uid(); else v_user:=p_user_id; end if;
  if v_user is distinct from auth.uid() and not public.is_admin() then raise exception '沒有權限'; end if;
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

-- These RPCs require a verified user JWT. Keep authenticated execution for
-- self-service and retain backend/admin execution, but remove anonymous access.
REVOKE EXECUTE ON FUNCTION public.check_growth_achievements(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_growth_achievements(uuid) TO authenticated, service_role, postgres;
REVOKE EXECUTE ON FUNCTION public.check_activity_badges(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_activity_badges(uuid) TO authenticated, service_role, postgres;

COMMIT;
