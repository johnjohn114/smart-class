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


-- Complete catalog fixture: create any production SECURITY DEFINER signatures
-- not otherwise needed by the behavioral tests, so the ACL matrix covers all
-- 36 live routines plus the private growth-level helper introduced by the
-- candidate migration. These stubs are disposable and never touch production.
DO $catalog_fixtures$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('admin_activity_analytics', '', false),
      ('admin_adjust_growth_points', 'uuid,integer,text', false),
      ('admin_apply_competition_rewards', 'uuid', false),
      ('admin_cancel_order', 'uuid', false),
      ('admin_complete_order', 'uuid', false),
      ('admin_delete_video', 'uuid', false),
      ('admin_grant_competition_reward', 'uuid,text,text,text,integer,uuid', false),
      ('admin_mark_competition_attendance', 'uuid,text,text', false),
      ('admin_mark_competition_member_attendance', 'uuid,uuid,text,text', false),
      ('admin_mark_order_paid', 'uuid', false),
      ('admin_promote_competition_waitlist', 'uuid', false),
      ('admin_reset_growth_member', 'uuid,text', false),
      ('admin_settle_competition', 'uuid', false),
      ('admin_upsert_video', 'jsonb', false),
      ('assign_member_no_and_nickname', '', true),
      ('check_competition_registration_rules', '', true),
      ('checkin_competition', 'uuid,text', false),
      ('close_my_support_ticket', 'uuid', false),
      ('create_cash_order', 'uuid,integer,text', false),
      ('ensure_visitor_profile', '', true),
      ('growth_registration_reward', '', true),
      ('growth_result_reward', '', true),
      ('is_admin_user', '', false),
      ('join_competition_waitlist', 'uuid,text', false),
      ('record_growth_activity', '', false),
      ('redeem_growth_reward', 'uuid', false),
      ('use_growth_coupon', 'uuid', false)
    ) AS v(name, argtypes, is_trigger)
  LOOP
    IF to_regprocedure(format('public.%I(%s)', r.name, r.argtypes)) IS NULL THEN
      IF r.is_trigger THEN
        EXECUTE format(
          'CREATE FUNCTION public.%I(%s) RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS %L',
          r.name, r.argtypes, 'BEGIN RETURN NEW; END;'
        );
      ELSE
        EXECUTE format(
          'CREATE FUNCTION public.%I(%s) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS %L',
          r.name, r.argtypes, 'BEGIN RETURN; END;'
        );
      END IF;
    END IF;
  END LOOP;
END
$catalog_fixtures$;

-- Simulate the live project's unsafe defaults before applying the fix:
-- PUBLIC gets PostgreSQL's normal function EXECUTE default, and the public
-- schema additionally grants anon/authenticated EXECUTE for postgres-owned
-- functions. The migration must remove both sources for future functions.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

\ir ../../migrations/202611160001_growth_function_authorization_hardening.sql

-- A SECURITY DEFINER function created after the migration must not become a
-- callable API endpoint through either PUBLIC or schema-specific defaults.
CREATE FUNCTION public.ci_future_security_definer()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
AS $future$
  SELECT 1
$future$;

DO $future_function_defaults$
BEGIN
  IF has_function_privilege('anon','public.ci_future_security_definer()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: future SECURITY DEFINER function is executable by anon';
  END IF;
  IF has_function_privilege('authenticated','public.ci_future_security_definer()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: future SECURITY DEFINER function is executable by authenticated';
  END IF;
  -- service_role is intentionally retained as a trusted server-side role;
  -- it is not shipped to the browser and is outside the public-client allowlist.
  IF NOT has_function_privilege('service_role','public.ci_future_security_definer()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: trusted service_role default was unexpectedly removed';
  END IF;
END
$future_function_defaults$;

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
  IF NOT has_function_privilege('authenticated','public.admin_delete_growth_reward(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: reviewed admin RPC missing authenticated EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated','public.admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamptz,timestamptz,integer,boolean)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: reviewed admin upsert RPC missing authenticated EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated','public.check_growth_achievements(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: member achievement RPC missing authenticated EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated','public.refresh_growth_level(uuid)','EXECUTE') THEN RAISE EXCEPTION 'FAIL: member level RPC missing authenticated EXECUTE'; END IF;
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
END
$member_self$;
RESET ROLE;
DO $task_record$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.growth_user_tasks
    WHERE user_id='00000000-0000-4000-8000-000000000002'
      AND task_id='00000000-0000-4000-8000-000000000040'
      AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'FAIL: task completion did not write the public task record';
  END IF;
END
$task_record$;

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


-- Exhaustive EXECUTE matrix for every production SECURITY DEFINER routine
-- (36 live signatures) plus the private helper added by this migration.
-- Only is_admin() is callable by anon; authenticated may call the reviewed
-- RPC allowlist and is_admin(); triggers and internal point helpers are denied.
DO $complete_acl_matrix$
DECLARE
  r record;
  resolved regprocedure;
  expected_authenticated boolean;
  expected_anon boolean;
  expected_trigger boolean;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('admin_activity_analytics()', true, false, false),
      ('admin_adjust_growth_points(uuid,integer,text)', true, false, false),
      ('admin_apply_competition_rewards(uuid)', true, false, false),
      ('admin_cancel_order(uuid)', true, false, false),
      ('admin_complete_order(uuid)', true, false, false),
      ('admin_delete_growth_reward(uuid)', true, false, false),
      ('admin_delete_video(uuid)', true, false, false),
      ('admin_grant_competition_reward(uuid,text,text,text,integer,uuid)', true, false, false),
      ('admin_mark_competition_attendance(uuid,text,text)', true, false, false),
      ('admin_mark_competition_member_attendance(uuid,uuid,text,text)', true, false, false),
      ('admin_mark_order_paid(uuid)', true, false, false),
      ('admin_promote_competition_waitlist(uuid)', true, false, false),
      ('admin_reset_growth_member(uuid,text)', true, false, false),
      ('admin_settle_competition(uuid)', true, false, false),
      ('admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamp with time zone,timestamp with time zone,integer,boolean)', true, false, false),
      ('admin_upsert_video(jsonb)', true, false, false),
      ('assign_member_no_and_nickname()', false, false, true),
      ('award_growth_points(uuid,integer,text,text,text,text,uuid)', false, false, false),
      ('check_activity_badges(uuid)', true, false, false),
      ('check_competition_registration_rules()', false, false, true),
      ('check_growth_achievements(uuid)', true, false, false),
      ('checkin_competition(uuid,text)', true, false, false),
      ('close_my_support_ticket(uuid)', true, false, false),
      ('complete_growth_task(text)', true, false, false),
      ('create_cash_order(uuid,integer,text)', true, false, false),
      ('ensure_visitor_profile()', false, false, true),
      ('growth_registration_reward()', false, false, true),
      ('growth_result_reward()', false, false, true),
      ('increment_download_count(uuid)', true, false, false),
      ('is_admin()', true, true, false),
      ('is_admin_user()', true, false, false),
      ('join_competition_waitlist(uuid,text)', true, false, false),
      ('record_growth_activity()', true, false, false),
      ('redeem_growth_reward(uuid)', true, false, false),
      ('refresh_growth_level(uuid)', true, false, false),
      ('use_growth_coupon(uuid)', true, false, false),
      ('_refresh_growth_level_internal(uuid)', false, false, false)
    ) AS v(signature, allow_authenticated, allow_anon, is_trigger)
  LOOP
    resolved := to_regprocedure('public.' || r.signature);
    IF resolved IS NULL THEN
      RAISE EXCEPTION 'FAIL: catalog fixture missing SECURITY DEFINER signature %', r.signature;
    END IF;

    expected_authenticated := r.allow_authenticated;
    expected_anon := r.allow_anon;
    expected_trigger := r.is_trigger;

    IF has_function_privilege('authenticated', resolved, 'EXECUTE')
       IS DISTINCT FROM expected_authenticated THEN
      RAISE EXCEPTION 'FAIL: authenticated EXECUTE mismatch for %, expected %',
        r.signature, expected_authenticated;
    END IF;

    IF has_function_privilege('anon', resolved, 'EXECUTE')
       IS DISTINCT FROM expected_anon THEN
      RAISE EXCEPTION 'FAIL: anon EXECUTE mismatch for %, expected %',
        r.signature, expected_anon;
    END IF;

    IF expected_trigger AND has_function_privilege('service_role', resolved, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: service_role can directly execute trigger function %', r.signature;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.prokind = 'f'
      AND p.oid::regprocedure::text <> 'ci_security_definer_trigger()'
  ) <> 38 THEN
    RAISE EXCEPTION 'FAIL: expected 38 catalog entries (36 live routines, internal helper, and future-function fixture)';
  END IF;
END
$complete_acl_matrix$;

\echo 'PASS: growth function authorization regression tests'


-- Forward-migration regression: simulate the vulnerable production grants and
-- old unguarded function body after the legacy migration, then prove the new
-- forward-only migration repairs them. This is a disposable PostgreSQL test.
GRANT EXECUTE ON FUNCTION
  public.award_growth_points(uuid,integer,text,text,text,text,uuid)
  TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.check_growth_achievements(p_user_id uuid DEFAULT auth.uid())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $legacy_unguarded$
BEGIN
  IF p_user_id IS NULL THEN RETURN 0; END IF;
  RETURN 0;
END;
$legacy_unguarded$;
GRANT EXECUTE ON FUNCTION public.check_growth_achievements(uuid) TO anon;

-- Reintroduce unsafe default ACLs to model the production drift independently
-- of the earlier historical hardening migration.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Recreate the two additional live-production drifts after the legacy
-- hardening migration, so Stage A must independently repair them.
CREATE OR REPLACE FUNCTION public.admin_delete_growth_reward(p_reward_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $legacy_admin_delete$
DECLARE caller_role text;
BEGIN
  SELECT role INTO caller_role FROM public.profiles WHERE id=auth.uid();
  IF caller_role <> 'admin' THEN RAISE EXCEPTION '只有管理員可以刪除獎勵'; END IF;
  RETURN jsonb_build_object('success',true);
END;
$legacy_admin_delete$;
GRANT EXECUTE ON FUNCTION public.admin_delete_growth_reward(uuid) TO anon;

-- Recreate the vulnerable reward upsert role check as seen in production.
CREATE OR REPLACE FUNCTION public.admin_upsert_growth_reward(
 p_reward_id uuid,p_code text,p_title text,p_description text,p_icon text,p_category text,
 p_point_cost integer,p_min_level text,p_required_achievement_id uuid,p_user_limit integer,
 p_total_limit integer,p_coupon_title text,p_coupon_description text,p_coupon_discount text,
 p_coupon_expires_days integer,p_available_from timestamptz,p_available_until timestamptz,
 p_sort_order integer,p_enabled boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $legacy_admin_upsert$
DECLARE caller_role text;
BEGIN
 SELECT role INTO caller_role FROM public.profiles WHERE id=auth.uid();
 IF caller_role <> 'admin' THEN RAISE EXCEPTION '只有管理員可以管理獎勵'; END IF;
 RETURN jsonb_build_object('success',true,'action','legacy-bypass');
END;
$legacy_admin_upsert$;
GRANT EXECUTE ON FUNCTION public.admin_upsert_growth_reward(admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean)) TO anon;

CREATE OR REPLACE FUNCTION public.refresh_growth_level(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $legacy_refresh_level$
DECLARE lvl public.growth_levels%rowtype;
BEGIN
  SELECT * INTO lvl FROM public.growth_levels
  WHERE min_points <= coalesce((SELECT growth_points FROM public.profiles WHERE id=p_user_id),0)
  ORDER BY min_points DESC,sort_order DESC LIMIT 1;
  IF lvl.code IS NULL THEN lvl.code:='newbie'; END IF;
  UPDATE public.profiles SET growth_level=lvl.code WHERE id=p_user_id;
  RETURN lvl.code;
END;
$legacy_refresh_level$;
GRANT EXECUTE ON FUNCTION public.refresh_growth_level(uuid) TO anon;

\ir ../../migrations/20261122120000_growth_rpc_and_public_leaderboard_hardening.sql

DO $forward_acl$
BEGIN
  IF has_function_privilege('anon','public.award_growth_points(uuid,integer,text,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.award_growth_points(uuid,integer,text,text,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: forward migration left direct award helper EXECUTE';
  END IF;
  IF has_function_privilege('anon','public.check_growth_achievements(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: forward migration left anonymous achievement EXECUTE';
  END IF;
  IF NOT has_function_privilege('authenticated','public.check_growth_achievements(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: forward migration removed authenticated achievement RPC';
  END IF;
  IF position('auth.uid()' in (
    SELECT prosrc FROM pg_proc
    WHERE oid='public.check_growth_achievements(uuid)'::regprocedure
  ))=0 THEN
    RAISE EXCEPTION 'FAIL: forward migration did not restore the caller ownership guard';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='activity_public_leaderboard')<>5 THEN
    RAISE EXCEPTION 'FAIL: public leaderboard projection must expose exactly five columns';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='activity_public_leaderboard'
               AND column_name IN ('user_id','checkin_points','completion_points')) THEN
    RAISE EXCEPTION 'FAIL: public leaderboard projection exposes internal columns';
  END IF;
  IF NOT has_table_privilege('anon','public.activity_public_leaderboard','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anonymous public leaderboard SELECT missing';
  END IF;
  IF has_function_privilege('anon','public.admin_delete_growth_reward(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A left anonymous admin reward delete EXECUTE';
  END IF;
  IF has_function_privilege('anon','public.admin_upsert_growth_reward(admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean))','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A left anonymous admin reward upsert EXECUTE';
  END IF;
  IF NOT has_function_privilege('authenticated','public.admin_upsert_growth_reward(admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean))','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A removed authenticated admin reward upsert RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.admin_delete_growth_reward(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A removed authenticated admin reward delete RPC';
  END IF;
  IF has_function_privilege('anon','public.refresh_growth_level(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A left anonymous growth level refresh EXECUTE';
  END IF;
  IF NOT has_function_privilege('authenticated','public.refresh_growth_level(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A removed authenticated growth level RPC';
  END IF;
  IF has_function_privilege('authenticated','public._refresh_growth_level_internal(uuid)','EXECUTE')
     OR has_function_privilege('anon','public._refresh_growth_level_internal(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public._refresh_growth_level_internal(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: private growth level helper remains directly executable';
  END IF;
END
$forward_acl$;

-- SECURITY DEFINER growth routines must not inherit a caller-controlled search_path.
DO $search_path_hardening$
DECLARE award_config text[]; achievement_config text[];
BEGIN
  SELECT proconfig INTO award_config FROM pg_proc
  WHERE oid='public.award_growth_points(uuid,integer,text,text,text,text,uuid)'::regprocedure;
  SELECT proconfig INTO achievement_config FROM pg_proc
  WHERE oid='public.check_growth_achievements(uuid)'::regprocedure;
  IF NOT coalesce(award_config @> ARRAY['search_path=""'],false) THEN
    RAISE EXCEPTION 'FAIL: award_growth_points must use an empty search_path';
  END IF;
  IF NOT coalesce(achievement_config @> ARRAY['search_path=""'],false) THEN
    RAISE EXCEPTION 'FAIL: check_growth_achievements must use an empty search_path';
  END IF;
END
$search_path_hardening$;

-- Stage A must also repair unsafe defaults for future SECURITY DEFINER functions.
CREATE FUNCTION public.ci_forward_future_definer()
RETURNS integer LANGUAGE sql SECURITY DEFINER AS 'SELECT 1';
DO $forward_defaults$
BEGIN
  IF has_function_privilege('anon','public.ci_forward_future_definer()','EXECUTE')
     OR has_function_privilege('authenticated','public.ci_forward_future_definer()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Stage A left unsafe default EXECUTE grants on future functions';
  END IF;
END
$forward_defaults$;

-- A member still processes only their own achievements after the forward fix.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $forward_cross_account$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='沒有權限檢查此會員成就' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: forward migration allowed cross-account achievement processing'; END IF;
END
$forward_cross_account$;
RESET ROLE;

-- Stage A must restore the member/admin wrapper for growth level refresh.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $forward_level_cross_account$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.refresh_growth_level('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='沒有權限更新此會員等級' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: Stage A allowed cross-account level refresh'; END IF;
END
$forward_level_cross_account$;
RESET ROLE;

-- Missing identity must fail closed for the admin delete RPC.
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE authenticated;
DO $forward_admin_null_identity$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='只有管理員可以刪除獎勵' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: Stage A admin delete accepted NULL auth.uid()'; END IF;
END
$forward_admin_null_identity$;
RESET ROLE;

-- Missing identity must also fail closed for the admin reward upsert RPC.
SET ROLE authenticated;
DO $forward_admin_upsert_null_identity$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.admin_upsert_growth_reward(
      NULL,'stage-a-null-test','Stage A Null Test',NULL,'star','test',5,NULL,NULL,NULL,NULL,
      NULL,NULL,NULL,NULL,NULL,NULL,1,true
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='只有管理員可以管理獎勵' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: Stage A admin upsert accepted NULL auth.uid()'; END IF;
END
$forward_admin_upsert_null_identity$;
RESET ROLE;

-- Seed the reward as the database owner; the authenticated admin then
-- exercises only the RPC, not direct table INSERT privileges.
INSERT INTO public.growth_rewards(id,code,title,reward_type,point_cost,enabled)
VALUES('00000000-0000-4000-8000-000000000099','stage-a-delete-test','Stage A delete test','coupon',5,true);

-- After Stage A, an authenticated administrator can still delete a reward.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $forward_admin_positive$
DECLARE result jsonb;
BEGIN
  result := public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000099');
  IF result->>'action' <> 'deleted' THEN
    RAISE EXCEPTION 'FAIL: Stage A admin reward delete no longer works';
  END IF;
END
$forward_admin_positive$;
RESET ROLE;

-- The authenticated admin can still create a reward after Stage A.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $forward_admin_upsert_positive$
DECLARE result jsonb;
BEGIN
  result := public.admin_upsert_growth_reward(
    NULL,'stage-a-upsert-test','Stage A Upsert Test',NULL,'star','test',5,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,2,true
  );
  IF result->>'action' <> 'created' THEN
    RAISE EXCEPTION 'FAIL: Stage A admin reward upsert no longer works';
  END IF;
END
$forward_admin_upsert_positive$;
RESET ROLE;

-- A normal authenticated member still cannot use the admin reward upsert.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $forward_admin_upsert_member_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.admin_upsert_growth_reward(
      NULL,'stage-a-member-test','Stage A Member Test',NULL,'star','test',5,NULL,NULL,NULL,NULL,
      NULL,NULL,NULL,NULL,NULL,NULL,3,true
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='只有管理員可以管理獎勵' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: Stage A allowed a normal member to upsert rewards'; END IF;
END
$forward_admin_upsert_member_denied$;
RESET ROLE;

-- The member can still refresh their own level after Stage A.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
DO $forward_level_self$
DECLARE level_code text;
BEGIN
  level_code := public.refresh_growth_level(auth.uid());
  IF level_code <> 'sprout' THEN
    RAISE EXCEPTION 'FAIL: Stage A member could not refresh own growth level';
  END IF;
END
$forward_level_self$;
RESET ROLE;

-- Internal SECURITY DEFINER trigger paths continue to award points even though
-- browser roles cannot call the helper directly.
CREATE TABLE public.ci_forward_award_trigger_source(
  id integer PRIMARY KEY,
  user_id uuid NOT NULL
);
CREATE FUNCTION public.ci_forward_award_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $trigger$
BEGIN
  PERFORM public.award_growth_points(
    NEW.user_id, 3, 'CI trusted trigger award', 'test',
    NEW.id::text, 'ci-forward-trigger:'||NEW.id::text, NULL
  );
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER ci_forward_award_trigger
AFTER INSERT ON public.ci_forward_award_trigger_source
FOR EACH ROW EXECUTE FUNCTION public.ci_forward_award_trigger();
GRANT INSERT ON public.ci_forward_award_trigger_source TO authenticated;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
SET ROLE authenticated;
INSERT INTO public.ci_forward_award_trigger_source(id,user_id)
VALUES(1,'00000000-0000-4000-8000-000000000002');
RESET ROLE;
DO $trigger_still_works$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.growth_point_transactions
    WHERE source_key='ci-forward-trigger:1' AND amount=3
  ) THEN RAISE EXCEPTION 'FAIL: trusted trigger could not call revoked award helper'; END IF;
END
$trigger_still_works$;

\echo 'PASS: growth forward-migration authorization regression tests'
