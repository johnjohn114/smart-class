-- Standalone regression test for member-scoped growth achievement/badge RPCs.
-- Run only in a fresh disposable PostgreSQL database as postgres.
DO $roles$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text NOT NULL, growth_points integer NOT NULL DEFAULT 0);
CREATE TABLE public.growth_achievements(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, reward_points integer NOT NULL DEFAULT 0, active boolean NOT NULL DEFAULT true, achievement_type text NOT NULL, requirement_count integer NOT NULL DEFAULT 999);
CREATE TABLE public.growth_user_achievements(user_id uuid NOT NULL, achievement_id uuid NOT NULL, PRIMARY KEY(user_id,achievement_id));
CREATE TABLE public.growth_activity_days(user_id uuid NOT NULL, activity_date date NOT NULL, source text DEFAULT 'visit');
CREATE TABLE public.competition_registrations(user_id uuid NOT NULL,status text,place integer);
CREATE TABLE public.competition_results(user_id uuid NOT NULL,place integer);
CREATE TABLE public.competition_attendance(user_id uuid NOT NULL,status text,points_awarded integer DEFAULT 0,completion_points_awarded integer DEFAULT 0);
CREATE TABLE public.activity_badges(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),active boolean DEFAULT true,requirement_type text NOT NULL,requirement_value integer NOT NULL);
CREATE TABLE public.user_activity_badges(user_id uuid NOT NULL,badge_id uuid NOT NULL,UNIQUE(user_id,badge_id));
CREATE TABLE public.notifications(user_id uuid,title text,content text,type text);
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$ SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role='admin') $$;
INSERT INTO public.growth_achievements(id,title,reward_points,active,achievement_type,requirement_count)
VALUES ('00000000-0000-4000-8000-000000000090','NULL target self scope',0,true,'active_days',0);
INSERT INTO public.activity_badges(id,active,requirement_type,requirement_value)
VALUES ('00000000-0000-4000-8000-000000000091',true,'activity_count',0);
INSERT INTO public.profiles(id,role,growth_points) VALUES
 ('00000000-0000-4000-8000-000000000001','member',0),
 ('00000000-0000-4000-8000-000000000002','member',0),
 ('00000000-0000-4000-8000-000000000003','admin',0);
GRANT SELECT ON public.profiles TO authenticated;
\ir ../../migrations/202611250003_growth_achievement_user_scope_guard.sql

-- Anonymous callers cannot invoke either SECURITY DEFINER RPC.
SET ROLE anon;
DO $anon$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon can execute check_growth_achievements'; END IF;
 denied:=false;
 BEGIN PERFORM public.check_growth_achievements(NULL); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon can execute check_growth_achievements with NULL target'; END IF;
 denied:=false;
 BEGIN PERFORM public.check_activity_badges('00000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon can execute check_activity_badges'; END IF;
 denied:=false;
 BEGIN PERFORM public.check_activity_badges(NULL); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon can execute check_activity_badges with NULL target'; END IF;
END $anon$;
RESET ROLE;

-- A logged-in member can check only their own progress.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $null_target_self$
DECLARE unlocked integer;
BEGIN
 unlocked := public.check_growth_achievements(NULL);
 IF unlocked <> 1 THEN RAISE EXCEPTION 'FAIL: explicit NULL achievement target did not resolve to the signed-in member'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.growth_user_achievements
   WHERE user_id='00000000-0000-4000-8000-000000000001'
     AND achievement_id='00000000-0000-4000-8000-000000000090'
 ) THEN RAISE EXCEPTION 'FAIL: explicit NULL achievement target did not write the member own achievement'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.growth_user_achievements
   WHERE user_id='00000000-0000-4000-8000-000000000002'
     AND achievement_id='00000000-0000-4000-8000-000000000090'
 ) THEN RAISE EXCEPTION 'FAIL: explicit NULL achievement target crossed user scope'; END IF;
 IF (public.check_activity_badges(NULL)->>'success')::boolean IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'FAIL: explicit NULL badge target did not resolve to the signed-in member';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.user_activity_badges
   WHERE user_id='00000000-0000-4000-8000-000000000001'
     AND badge_id='00000000-0000-4000-8000-000000000091'
 ) THEN RAISE EXCEPTION 'FAIL: explicit NULL badge target did not write the member own badge'; END IF;
END
$null_target_self$;
SELECT public.check_growth_achievements();
SELECT public.check_activity_badges();
DO $member_scope$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000002'); EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM='沒有權限' THEN denied:=true; ELSE RAISE; END IF; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: member can check another member achievements'; END IF;
 denied:=false;
 BEGIN PERFORM public.check_activity_badges('00000000-0000-4000-8000-000000000002'); EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM='沒有權限' THEN denied:=true; ELSE RAISE; END IF; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: member can check another member badges'; END IF;
END $member_scope$;
RESET ROLE;

-- Admin can legitimately run checks for a member.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
SET ROLE authenticated;
DO $admin_null_target$
DECLARE unlocked integer;
BEGIN
 unlocked := public.check_growth_achievements(NULL);
 IF unlocked <> 1 THEN RAISE EXCEPTION 'FAIL: admin explicit NULL target did not resolve to the admin own account'; END IF;
 IF (public.check_activity_badges(NULL)->>'success')::boolean IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'FAIL: admin explicit NULL badge target failed';
 END IF;
END
$admin_null_target$;
SELECT public.check_growth_achievements('00000000-0000-4000-8000-000000000001');
SELECT public.check_activity_badges('00000000-0000-4000-8000-000000000001');
RESET ROLE;
\echo 'PASS: achievement and badge RPCs enforce authenticated self/admin scope and deny anon execution'
