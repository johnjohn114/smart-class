-- Forward-only hardening for the live growth RPC exposure and public leaderboard.
-- Stage A: apply after environment/migration-history reconciliation.
-- Stage B (private view hardening) is intentionally a separate migration so the
-- frontend can first move to activity_public_leaderboard.
-- No historical migration is rewritten by this file.

BEGIN;

DO $preflight$
BEGIN
  IF to_regprocedure('public.award_growth_points(uuid,integer,text,text,text,text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Required function public.award_growth_points(...) is missing';
  END IF;
  IF to_regprocedure('public.check_growth_achievements(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Required function public.check_growth_achievements(uuid) is missing';
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.competition_attendance') IS NULL THEN
    RAISE EXCEPTION 'Required leaderboard source tables are missing';
  END IF;
END
$preflight$;

-- The award helper is internal to reviewed SECURITY DEFINER RPCs and triggers.
-- Its owner (postgres) retains execution; browser API roles do not.
REVOKE EXECUTE ON FUNCTION
  public.award_growth_points(uuid, integer, text, text, text, text, uuid)
  FROM PUBLIC, anon, authenticated;

-- Keep the internal SECURITY DEFINER helper independent of caller-controlled
-- search_path settings even though its object references are schema-qualified.
ALTER FUNCTION public.award_growth_points(uuid, integer, text, text, text, text, uuid)
  SET search_path TO '';

-- Restore the self/admin ownership guard even if an older live definition was
-- installed without it. Keep the existing achievement calculation behavior.
CREATE OR REPLACE FUNCTION public.check_growth_achievements(p_user_id uuid DEFAULT auth.uid())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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

-- The function is an authenticated self-service/admin RPC, never anonymous.
REVOKE EXECUTE ON FUNCTION public.check_growth_achievements(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_growth_achievements(uuid)
  TO authenticated;

-- Stage A public projection: exactly the fields rendered by the public
-- leaderboard. Account UUIDs and internal point subtotals are not exposed.
CREATE OR REPLACE VIEW public.activity_public_leaderboard
WITH (security_barrier = true, security_invoker = false) AS
SELECT
  max(COALESCE(NULLIF(btrim(p.nickname), ''), '會員')) AS nickname,
  count(*) FILTER (
    WHERE a.status = ANY (ARRAY['checked_in'::text, 'late'::text])
  )::integer AS attended_count,
  count(*) FILTER (WHERE a.status = 'late'::text)::integer AS late_count,
  count(*) FILTER (WHERE a.status = 'no_show'::text)::integer AS no_show_count,
  (
    COALESCE(sum(a.points_awarded), 0::bigint)
    + COALESCE(sum(a.completion_points_awarded), 0::bigint)
  )::integer AS activity_points
FROM public.competition_attendance a
LEFT JOIN public.profiles p ON p.id = a.user_id
GROUP BY a.user_id;

REVOKE ALL PRIVILEGES ON TABLE public.activity_public_leaderboard
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.activity_public_leaderboard
  TO anon, authenticated, service_role;

COMMENT ON VIEW public.activity_public_leaderboard IS
  'Intentionally public leaderboard projection; contains only nickname and displayed activity aggregates, not account identifiers. Missing or blank nicknames are shown as 會員.';

COMMIT;
