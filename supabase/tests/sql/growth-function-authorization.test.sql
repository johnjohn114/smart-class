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
  download_count bigint NOT NULL DEFAULT 0,
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
ALTER TABLE public.competition_results ADD COLUMN competition_id uuid;

-- Isolated schema fixtures reproduce live anonymous-read policy predicates
-- without leaking table names into the sequential migration test's public
-- schema. Policies call the same public.is_admin() helper used in production.
CREATE SCHEMA ci_anon_rls;
GRANT USAGE ON SCHEMA ci_anon_rls TO anon;
CREATE TABLE ci_anon_rls.competitions (
  id uuid PRIMARY KEY,
  published boolean NOT NULL,
  published_at timestamptz
);
CREATE TABLE ci_anon_rls.forms (
  id uuid PRIMARY KEY,
  published boolean NOT NULL
);
CREATE TABLE ci_anon_rls.form_questions (
  id uuid PRIMARY KEY,
  form_id uuid NOT NULL
);
CREATE TABLE ci_anon_rls.products (
  id uuid PRIMARY KEY,
  active boolean NOT NULL
);
CREATE TABLE ci_anon_rls.competition_results (
  user_id uuid NOT NULL,
  competition_id uuid
);

ALTER TABLE ci_anon_rls.competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ci_anon_rls.forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE ci_anon_rls.form_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ci_anon_rls.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE ci_anon_rls.competition_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY competition_public_read ON ci_anon_rls.competitions
  FOR SELECT TO PUBLIC
  USING (public.is_admin() OR (published = true AND (published_at IS NULL OR published_at <= now())));
CREATE POLICY forms_public_read ON ci_anon_rls.forms
  FOR SELECT TO PUBLIC
  USING (published = true OR public.is_admin());
CREATE POLICY form_questions_public_read ON ci_anon_rls.form_questions
  FOR SELECT TO PUBLIC
  USING (EXISTS (
    SELECT 1 FROM ci_anon_rls.forms f
    WHERE f.id = form_questions.form_id AND (f.published = true OR public.is_admin())
  ));
CREATE POLICY product_public_read ON ci_anon_rls.products
  FOR SELECT TO PUBLIC
  USING (public.is_admin() OR active = true);
CREATE POLICY competition_result_public_read ON ci_anon_rls.competition_results
  FOR SELECT TO PUBLIC
  USING (
    public.is_admin()
    OR user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM ci_anon_rls.competitions c
      WHERE c.id = competition_results.competition_id
        AND c.published = true
        AND (c.published_at IS NULL OR c.published_at <= now())
    )
  );

GRANT SELECT ON ci_anon_rls.competitions, ci_anon_rls.forms,
  ci_anon_rls.form_questions, ci_anon_rls.products,
  ci_anon_rls.competition_results TO anon;

INSERT INTO ci_anon_rls.competitions(id,published,published_at) VALUES
  ('00000000-0000-4000-8000-000000000070',true,NULL),
  ('00000000-0000-4000-8000-000000000071',true,now()+interval '1 day');
INSERT INTO ci_anon_rls.forms(id,published) VALUES
  ('00000000-0000-4000-8000-000000000072',true),
  ('00000000-0000-4000-8000-000000000073',false);
INSERT INTO ci_anon_rls.form_questions(id,form_id) VALUES
  ('00000000-0000-4000-8000-000000000074','00000000-0000-4000-8000-000000000072'),
  ('00000000-0000-4000-8000-000000000075','00000000-0000-4000-8000-000000000073');
INSERT INTO ci_anon_rls.products(id,active) VALUES
  ('00000000-0000-4000-8000-000000000076',true),
  ('00000000-0000-4000-8000-000000000077',false);
INSERT INTO ci_anon_rls.competition_results(user_id,competition_id) VALUES
  ('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000070'),
  ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000071');

SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE anon;
DO $anon_is_admin_result$
BEGIN
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: is_admin() did not return false for anon';
  END IF;

  -- These counts are evaluated through real RLS policy execution as anon.
  IF (SELECT count(*) FROM ci_anon_rls.competitions) <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon competition RLS read returned the wrong rows';
  END IF;
  IF (SELECT count(*) FROM ci_anon_rls.forms) <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon forms RLS read returned the wrong rows';
  END IF;
  IF (SELECT count(*) FROM ci_anon_rls.form_questions) <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon form_questions RLS read returned the wrong rows';
  END IF;
  IF (SELECT count(*) FROM ci_anon_rls.products) <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon products RLS read returned the wrong rows';
  END IF;
  IF (SELECT count(*) FROM ci_anon_rls.competition_results) <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon competition_results RLS read returned the wrong rows';
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

-- Prove that anonymous SQL callers are rejected at the EXECUTE boundary,
-- not merely by catalog inspection. These calls must fail before function bodies run.
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE anon;
DO $anon_direct_calls_denied$
DECLARE
  denied boolean;
BEGIN
  denied := false;
  BEGIN
    PERFORM public.award_growth_points(
      '00000000-0000-4000-8000-000000000003',50,'anon test','manual',NULL,NULL,NULL
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed award_growth_points'; END IF;

  denied := false;
  BEGIN
    PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed check_growth_achievements'; END IF;

  denied := false;
  BEGIN
    PERFORM public.check_activity_badges('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed check_activity_badges'; END IF;

  denied := false;
  BEGIN
    PERFORM public.refresh_growth_level('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed refresh_growth_level'; END IF;

  denied := false;
  BEGIN
    PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed admin_delete_growth_reward'; END IF;

  denied := false;
  BEGIN
    PERFORM public.admin_upsert_growth_reward(
      NULL,'anon-should-not-create','Anon should not create',NULL,'star','test',5,
      NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,1,true
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon directly executed admin_upsert_growth_reward'; END IF;
END
$anon_direct_calls_denied$;
RESET ROLE;

-- A JWT-less authenticated database role must also fail closed for every
-- user-targeted RPC, even when an explicit victim UUID is supplied.
SET ROLE authenticated;
DO $authenticated_missing_uid_denied$
DECLARE
  denied boolean;
BEGIN
  denied := false;
  BEGIN
    PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限檢查此會員成就' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: check_growth_achievements accepted missing auth.uid()'; END IF;

  denied := false;
  BEGIN
    PERFORM public.check_activity_badges('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: check_activity_badges accepted missing auth.uid()'; END IF;

  denied := false;
  BEGIN
    PERFORM public.refresh_growth_level('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = '沒有權限更新此會員等級' THEN denied := true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: refresh_growth_level accepted missing auth.uid()'; END IF;
END
$authenticated_missing_uid_denied$;
RESET ROLE;

DO $no_identity_side_effects$
BEGIN
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000003') <> 0 THEN
    RAISE EXCEPTION 'FAIL: JWT-less calls changed another member growth points';
  END IF;
  IF (SELECT growth_level FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000003') <> 'newbie' THEN
    RAISE EXCEPTION 'FAIL: JWT-less calls changed another member growth level';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_activity_badges WHERE user_id='00000000-0000-4000-8000-000000000003') THEN
    RAISE EXCEPTION 'FAIL: JWT-less calls created another member activity badges';
  END IF;
  IF EXISTS (SELECT 1 FROM public.growth_user_achievements WHERE user_id='00000000-0000-4000-8000-000000000003') THEN
    RAISE EXCEPTION 'FAIL: JWT-less calls created another member achievements';
  END IF;
END
$no_identity_side_effects$;

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
