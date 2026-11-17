-- Disposable regression test for growth-function authorization hardening.
-- Run in a fresh PostgreSQL 17 database as postgres:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f this-file.sql

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA public, auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;

CREATE TABLE public.download_files (
  id uuid PRIMARY KEY,
  published boolean NOT NULL,
  download_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,
  role text,
  growth_points integer NOT NULL DEFAULT 0,
  growth_level text NOT NULL DEFAULT 'newbie',
  nickname text
);
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $is_admin$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id=auth.uid() AND role='admin'
  )
$is_admin$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO PUBLIC, anon, authenticated, service_role;

CREATE TABLE public.growth_levels (
  code text PRIMARY KEY,
  name text NOT NULL,
  min_points integer NOT NULL,
  sort_order integer NOT NULL DEFAULT 0
);
CREATE TABLE public.growth_tasks (
  id uuid PRIMARY KEY,
  code text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  task_type text NOT NULL,
  requirement_count integer NOT NULL DEFAULT 1,
  reward_points integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  cycle_type text NOT NULL DEFAULT 'one_time',
  start_at timestamptz,
  end_at timestamptz
);
CREATE TABLE public.growth_user_tasks (
  user_id uuid NOT NULL,
  task_id uuid NOT NULL,
  progress integer NOT NULL DEFAULT 0,
  completed_at timestamptz,
  cycle_key text NOT NULL DEFAULT 'once',
  PRIMARY KEY(user_id,task_id,cycle_key)
);
CREATE TABLE public.growth_achievements (
  id uuid PRIMARY KEY,
  active boolean NOT NULL,
  achievement_type text NOT NULL,
  requirement_count integer NOT NULL,
  reward_points integer NOT NULL DEFAULT 0,
  title text NOT NULL
);
CREATE TABLE public.growth_activity_days (
  user_id uuid NOT NULL,
  activity_date date NOT NULL
);
CREATE TABLE public.growth_user_achievements (
  user_id uuid NOT NULL,
  achievement_id uuid NOT NULL,
  UNIQUE(user_id, achievement_id)
);
CREATE TABLE public.competition_registrations (
  user_id uuid NOT NULL,
  status text NOT NULL
);
CREATE TABLE public.competition_results (
  user_id uuid NOT NULL,
  place integer
);
CREATE TABLE public.notifications (
  user_id uuid NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  type text NOT NULL
);
CREATE TABLE public.growth_point_transactions (
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  reason text,
  source_type text,
  source_id text,
  source_key text,
  admin_user_id uuid
);
CREATE TABLE public.growth_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  title text NOT NULL,
  description text,
  icon text,
  category text,
  reward_type text NOT NULL,
  point_cost integer NOT NULL,
  min_level text,
  required_achievement_id uuid,
  user_limit integer,
  total_limit integer,
  coupon_title text,
  coupon_description text,
  coupon_discount text,
  coupon_expires_days integer,
  available_from timestamptz,
  available_until timestamptz,
  sort_order integer,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.growth_reward_redemptions (
  reward_id uuid NOT NULL
);
CREATE TABLE public.competition_attendance (
  user_id uuid NOT NULL,
  status text NOT NULL,
  points_awarded integer NOT NULL DEFAULT 0,
  completion_points_awarded integer NOT NULL DEFAULT 0
);
CREATE TABLE public.activity_badges (
  id uuid PRIMARY KEY,
  active boolean NOT NULL,
  requirement_type text NOT NULL,
  requirement_value integer NOT NULL
);
CREATE TABLE public.user_activity_badges (
  user_id uuid NOT NULL,
  badge_id uuid NOT NULL,
  UNIQUE(user_id,badge_id)
);

GRANT SELECT ON public.profiles TO authenticated;

INSERT INTO public.growth_levels(code,name,min_points,sort_order)
VALUES ('newbie','新手',0,0),('sprout','萌芽',10,1);
INSERT INTO public.profiles(id,role,growth_points,growth_level) VALUES
 ('00000000-0000-4000-8000-000000000001','admin',0,'newbie'),
 ('00000000-0000-4000-8000-000000000002','visitor',10,'newbie'),
 ('00000000-0000-4000-8000-000000000003','visitor',0,'newbie');
INSERT INTO public.growth_achievements(id,active,achievement_type,requirement_count,reward_points,title)
VALUES ('00000000-0000-4000-8000-000000000010',true,'points',1,5,'CI points achievement');
INSERT INTO public.activity_badges(id,active,requirement_type,requirement_value)
VALUES ('00000000-0000-4000-8000-000000000020',true,'first_activity',1);
INSERT INTO public.competition_attendance(user_id,status,points_awarded,completion_points_awarded)
VALUES ('00000000-0000-4000-8000-000000000002','checked_in',2,0);

-- Simulate the live project's public download counter and explicit grants.
CREATE FUNCTION public.increment_download_count(p_file_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $body$
  UPDATE public.download_files
  SET download_count=coalesce(download_count,0)+1, updated_at=now()
  WHERE id=p_file_id AND published=true
$body$;
GRANT EXECUTE ON FUNCTION public.increment_download_count(uuid) TO anon, authenticated;

-- Simulate the live project's explicit grants on the pre-existing function.
-- CREATE OR REPLACE preserves function ACLs, so the migration must revoke
-- authenticated's direct EXECUTE grant as well as anon/PUBLIC.
CREATE FUNCTION public.award_growth_points(
  p_user_id uuid,
  p_amount integer,
  p_reason text,
  p_source_type text DEFAULT 'manual',
  p_source_id text DEFAULT NULL,
  p_source_key text DEFAULT NULL,
  p_admin_user_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE sql
AS $body$ SELECT 0 $body$;
GRANT EXECUTE ON FUNCTION public.award_growth_points(uuid,integer,text,text,text,text,uuid)
  TO anon, authenticated, service_role;

-- Trigger functions need no API-role EXECUTE grant once the trigger exists.
CREATE TABLE public.ci_trigger_source(id integer PRIMARY KEY);
CREATE TABLE public.ci_trigger_log(id integer NOT NULL);
CREATE FUNCTION public.ci_security_definer_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $trigger$
BEGIN
  INSERT INTO public.ci_trigger_log(id) VALUES(NEW.id);
  RETURN NEW;
END;
$trigger$;
GRANT EXECUTE ON FUNCTION public.ci_security_definer_trigger() TO anon, authenticated, service_role;
CREATE TRIGGER ci_security_definer_trigger
AFTER INSERT ON public.ci_trigger_source
FOR EACH ROW EXECUTE FUNCTION public.ci_security_definer_trigger();

\ir ../../migrations/202611160001_growth_function_authorization_hardening.sql

-- is_admin() is the one safe SECURITY DEFINER helper exposed to anon because
-- several PUBLIC RLS policies call it; it must return false without a JWT.
DO $anon_is_admin$
BEGIN
  IF NOT has_function_privilege('anon','public.is_admin()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon cannot evaluate public RLS policies using is_admin()';
  END IF;
END
$anon_is_admin$;
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE anon;
DO $anon_is_admin_result$
BEGIN
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: is_admin() did not return false for anon';
  END IF;
END
$anon_is_admin_result$;
RESET ROLE;

-- Anonymous callers cannot execute privileged RPCs or internal helpers.
DO $anon_acl$
BEGIN
  IF has_function_privilege('anon','public.admin_delete_growth_reward(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute admin_delete_growth_reward'; END IF;
  IF has_function_privilege('anon','public.admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamptz,timestamptz,integer,boolean)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute admin_upsert_growth_reward'; END IF;
  IF has_function_privilege('anon','public.award_growth_points(uuid,integer,text,text,text,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute award_growth_points'; END IF;
  IF has_function_privilege('anon','public.check_growth_achievements(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute check_growth_achievements'; END IF;
  IF has_function_privilege('anon','public.refresh_growth_level(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute refresh_growth_level'; END IF;
  IF has_function_privilege('anon','public.check_activity_badges(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute check_activity_badges'; END IF;
  IF has_function_privilege('anon','public.increment_download_count(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon can execute increment_download_count'; END IF;
  IF NOT has_function_privilege('authenticated','public.increment_download_count(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: authenticated cannot execute increment_download_count'; END IF;
  IF has_function_privilege('authenticated','public.award_growth_points(uuid,integer,text,text,text,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: authenticated can execute award_growth_points directly'; END IF;
  IF has_function_privilege('authenticated','public._refresh_growth_level_internal(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: authenticated can execute internal helper'; END IF;
  IF NOT has_function_privilege('authenticated','public.complete_growth_task(text)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: authenticated cannot execute own task RPC'; END IF;
END
$anon_acl$;

-- The authenticated-only download counter still updates published files.
INSERT INTO public.download_files(id,published,download_count) VALUES
 ('00000000-0000-4000-8000-000000000030',true,0),
 ('00000000-0000-4000-8000-000000000031',false,0);
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
SELECT public.increment_download_count('00000000-0000-4000-8000-000000000030');
SELECT public.increment_download_count('00000000-0000-4000-8000-000000000031');
RESET ROLE;
DO $download_counter$
BEGIN
  IF (SELECT download_count FROM public.download_files WHERE id='00000000-0000-4000-8000-000000000030') <> 1 THEN RAISE EXCEPTION 'FAIL: authenticated published download count did not increment'; END IF;
  IF (SELECT download_count FROM public.download_files WHERE id='00000000-0000-4000-8000-000000000031') <> 0 THEN RAISE EXCEPTION 'FAIL: unpublished download count should not increment'; END IF;
END
$download_counter$;

INSERT INTO public.growth_tasks(id,code,title,task_type,requirement_count,reward_points)
VALUES('00000000-0000-4000-8000-000000000040','profile-check','Profile check','profile_complete',1,0);
UPDATE public.profiles SET nickname='CI member'
WHERE id='00000000-0000-4000-8000-000000000002';
CREATE TEMP TABLE growth_levels(
  code text, name text, min_points integer, sort_order integer
);
INSERT INTO pg_temp.growth_levels VALUES('temp_override','Temp override',0,999);
CREATE TEMP TABLE growth_tasks(
  id uuid, code text, title text, description text, task_type text,
  requirement_count integer, reward_points integer, active boolean,
  created_at timestamptz, cycle_type text, start_at timestamptz, end_at timestamptz
);
INSERT INTO pg_temp.growth_tasks VALUES(
  '00000000-0000-4000-8000-000000000041','profile-check','Shadow task',
  NULL,'not_a_real_task_type',999,0,true,now(),'one_time',NULL,NULL
);

-- Authenticated member can inspect own achievements and refresh own level.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $member_self$
DECLARE
  unlocked integer;
  level_code text;
  points integer;
BEGIN
  unlocked := public.check_growth_achievements(auth.uid());
  IF unlocked <> 1 THEN RAISE EXCEPTION 'FAIL: member own achievement check did not unlock expected achievement'; END IF;
  SELECT growth_points INTO points FROM public.profiles WHERE id=auth.uid();
  IF points <> 15 THEN RAISE EXCEPTION 'FAIL: internal award helper did not award expected points'; END IF;
  IF (public.check_activity_badges(auth.uid())->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: member could not check own activity badges'; END IF;
  level_code := public.refresh_growth_level(auth.uid());
  IF level_code <> 'sprout' THEN RAISE EXCEPTION 'FAIL: own growth level refresh returned unexpected level'; END IF;
  IF public.complete_growth_task('profile-check') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: task RPC resolved the shadow pg_temp.growth_tasks instead of public.growth_tasks';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.growth_user_tasks
    WHERE user_id=auth.uid()
      AND task_id='00000000-0000-4000-8000-000000000040'
      AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'FAIL: task completion did not write the public task record';
  END IF;
END
$member_self$;
RESET ROLE;

-- Authenticated member cannot inspect or refresh another member's records.
SET ROLE authenticated;
DO $member_cross_account$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限檢查此會員成就' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member inspected another member achievements'; END IF;
  denied := false;
  BEGIN
    PERFORM public.check_activity_badges('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member checked another member activity badges'; END IF;

  denied := false;
  BEGIN
    PERFORM public.refresh_growth_level('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限更新此會員等級' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member refreshed another member level'; END IF;
END
$member_cross_account$;
RESET ROLE;

-- Admin may manage rewards and refresh another member's level.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $admin_allowed$
DECLARE
  result jsonb;
  level_code text;
  reward_id uuid;
BEGIN
  result := public.admin_upsert_growth_reward(
    NULL,'ci-reward','CI Reward',NULL,'star','test',5,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,1,true
  );
  IF result->>'action' <> 'created' THEN RAISE EXCEPTION 'FAIL: admin could not create reward'; END IF;
  reward_id := (result->>'id')::uuid;
  result := public.admin_delete_growth_reward(reward_id);
  IF result->>'action' <> 'deleted' THEN
    RAISE EXCEPTION 'FAIL: admin reward delete did not return deleted action';
  END IF;
  IF (public.check_activity_badges('00000000-0000-4000-8000-000000000003')->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: admin could not check another member badges'; END IF;
  level_code := public.refresh_growth_level('00000000-0000-4000-8000-000000000003');
  IF level_code <> 'newbie' THEN RAISE EXCEPTION 'FAIL: admin could not refresh another member level'; END IF;
END
$admin_allowed$;
RESET ROLE;

-- An authenticated SQL role without a user JWT must never pass admin guards.
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE authenticated;
DO $missing_identity_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '只有管理員可以刪除獎勵' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: admin delete accepted a missing auth.uid()'; END IF;

  denied := false;
  BEGIN
    PERFORM public.admin_upsert_growth_reward(
      NULL,'should-not-exist','Should Not Exist',NULL,'star','test',5,NULL,NULL,NULL,NULL,
      NULL,NULL,NULL,NULL,NULL,NULL,1,true
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '只有管理員可以管理獎勵' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: admin upsert accepted a missing auth.uid()'; END IF;
END
$missing_identity_denied$;
RESET ROLE;

-- A normal authenticated member cannot use admin reward RPCs.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $member_admin_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '只有管理員可以刪除獎勵' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: non-admin member executed admin delete'; END IF;
END
$member_admin_denied$;
RESET ROLE;


-- Revoking API-role EXECUTE does not disable an already-created trigger.
DO $trigger_acl$
BEGIN
  IF has_function_privilege('anon','public.ci_security_definer_trigger()','EXECUTE')
     OR has_function_privilege('authenticated','public.ci_security_definer_trigger()','EXECUTE')
     OR has_function_privilege('service_role','public.ci_security_definer_trigger()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: trigger function still has API-role EXECUTE';
  END IF;
END
$trigger_acl$;
INSERT INTO public.ci_trigger_source(id) VALUES (7);
DO $trigger_runtime$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ci_trigger_log WHERE id=7) THEN
    RAISE EXCEPTION 'FAIL: trigger stopped running after EXECUTE revoke';
  END IF;
END
$trigger_runtime$;

-- All fixture SECURITY DEFINER RPCs must be unavailable to anon.
DO $all_anon_denied$
DECLARE
  sig text;
BEGIN
  FOREACH sig IN ARRAY ARRAY[
    'public.award_growth_points(uuid,integer,text,text,text,text,uuid)',
    'public.increment_download_count(uuid)',
    'public.admin_delete_growth_reward(uuid)',
    'public.admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamptz,timestamptz,integer,boolean)',
    'public._refresh_growth_level_internal(uuid)',
    'public.refresh_growth_level(uuid)',
    'public.check_growth_achievements(uuid)',
    'public.check_activity_badges(uuid)'
  ] LOOP
    IF has_function_privilege('anon', sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: anon retains EXECUTE on %', sig;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated','public.award_growth_points(uuid,integer,text,text,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated can directly execute internal award_growth_points';
  END IF;
  IF has_function_privilege('authenticated','public._refresh_growth_level_internal(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated can execute internal level helper';
  END IF;
  IF NOT has_function_privilege('authenticated','public.increment_download_count(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated lost download counter access';
  END IF;
END
$all_anon_denied$;

\echo 'PASS: growth function authorization regression tests'
