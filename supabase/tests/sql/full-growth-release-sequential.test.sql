-- Full candidate release-chain integration test.
-- Run only in a fresh disposable PostgreSQL 17 database as postgres.
-- This composes the already-tested 202611160001 -> 202611170001 fixture,
-- extends that SAME database to the minimum application schema, then applies
-- the remaining candidate migrations in order (250001, 250003, 250004, 250005). Production is never contacted.

\ir growth-and-default-privileges-sequential.test.sql

-- The prerequisite sequential fixture creates a two-argument overload only
-- to probe default EXECUTE behavior. Remove that test-only overload before
-- applying migration 004, whose production inventory intentionally expects
-- exactly one SECURITY DEFINER complete_growth_task(text) RPC.
DROP FUNCTION public.complete_growth_task(text,text);

-- Remove SECURITY DEFINER routines that exist only to test default grants in
-- the prerequisite fixture. They are not part of the production inventory.
DROP TRIGGER ci_security_definer_trigger ON public.ci_trigger_source;
DROP FUNCTION public.ci_security_definer_trigger();
DROP TABLE public.ci_trigger_source;
DROP TABLE public.ci_trigger_log;
DROP FUNCTION public.ci_future_security_definer();

-- Complete the application baseline needed by the five candidate migrations.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS member_no integer,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.competitions
  ADD COLUMN IF NOT EXISTS name text NOT NULL DEFAULT 'CI 活動',
  ADD COLUMN IF NOT EXISTS checkin_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS checkin_code text,
  ADD COLUMN IF NOT EXISTS checkin_start_at timestamptz,
  ADD COLUMN IF NOT EXISTS checkin_end_at timestamptz,
  ADD COLUMN IF NOT EXISTS checkin_points integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS completion_points integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz;
ALTER TABLE public.competition_registrations
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.competition_attendance
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS competition_id uuid,
  ADD COLUMN IF NOT EXISTS registration_id uuid,
  ADD COLUMN IF NOT EXISTS checked_in_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS note text;
CREATE UNIQUE INDEX IF NOT EXISTS ci_full_attendance_id_uq
  ON public.competition_attendance(id);
ALTER TABLE public.growth_user_achievements
  ADD COLUMN IF NOT EXISTS unlocked_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE public.competition_reward_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id uuid NOT NULL,
  reward_type text NOT NULL,
  reward_value integer,
  badge_id uuid,
  title text NOT NULL,
  enabled boolean NOT NULL DEFAULT true
);
CREATE TABLE public.competition_reward_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id uuid NOT NULL,
  reward_rule_id uuid NOT NULL,
  user_id uuid NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(competition_id,reward_rule_id,user_id)
);
CREATE TABLE public.growth_reset_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  reset_by uuid,
  reset_no integer NOT NULL,
  reason text NOT NULL DEFAULT '管理員手動重置',
  before_points integer NOT NULL DEFAULT 0,
  after_points integer NOT NULL DEFAULT 0,
  before_level text NOT NULL DEFAULT 'newbie',
  after_level text NOT NULL DEFAULT 'newbie',
  before_active_days integer NOT NULL DEFAULT 0,
  before_login_streak integer NOT NULL DEFAULT 0,
  before_completed_tasks integer NOT NULL DEFAULT 0,
  before_achievements integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id,reset_no)
);
CREATE TABLE public.growth_achievement_unlock_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  achievement_id uuid NOT NULL,
  unlocked_at timestamptz NOT NULL,
  archived_at timestamptz NOT NULL DEFAULT now(),
  reset_history_id uuid,
  snapshot_title text,
  snapshot_reward_points integer NOT NULL DEFAULT 0
);

-- The older authorization fixture intentionally uses void-returning catalog
-- stubs. Replace only the four functions whose production signatures return
-- jsonb, so CREATE OR REPLACE in migration 001 is tested with real signatures.
DROP FUNCTION public.checkin_competition(uuid,text);
DROP FUNCTION public.admin_apply_competition_rewards(uuid);
DROP FUNCTION public.admin_mark_competition_member_attendance(uuid,uuid,text,text);
DROP FUNCTION public.admin_reset_growth_member(uuid,text);
DROP FUNCTION public.admin_settle_competition(uuid);
CREATE FUNCTION public.checkin_competition(uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.admin_apply_competition_rewards(uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.admin_mark_competition_member_attendance(uuid,uuid,text,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.admin_reset_growth_member(uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.admin_settle_competition(uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;

-- Existing production profile protection is part of the baseline; migration
-- 001 replaces this trigger function and retains the trigger binding.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $protect$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.member_no IS DISTINCT FROM OLD.member_no
     OR NEW.growth_points IS DISTINCT FROM OLD.growth_points
     OR NEW.growth_level IS DISTINCT FROM OLD.growth_level
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN RAISE EXCEPTION 'protected profile field'; END IF;
  RETURN NEW;
END;
$protect$;
CREATE TRIGGER ci_protect_profile_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_fields();

-- Build the existing member/admin view before hardening it in migration 005.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY ci_profiles_self_or_admin ON public.profiles
FOR SELECT TO authenticated
USING (id=auth.uid() OR public.is_admin());
CREATE POLICY ci_attendance_self_or_admin ON public.competition_attendance
FOR SELECT TO authenticated
USING (user_id=auth.uid() OR public.is_admin());
GRANT SELECT ON public.profiles,public.competition_attendance TO authenticated,service_role;
CREATE VIEW public.activity_member_stats AS
SELECT
  a.user_id,
  COALESCE(NULLIF(btrim(p.nickname),''),'會員') AS nickname,
  count(*) FILTER (WHERE a.status IN ('checked_in','late'))::integer AS attended_count,
  count(*) FILTER (WHERE a.status='late')::integer AS late_count,
  count(*) FILTER (WHERE a.status='no_show')::integer AS no_show_count,
  COALESCE(sum(a.points_awarded),0)::integer AS checkin_points,
  COALESCE(sum(a.completion_points_awarded),0)::integer AS completion_points,
  (COALESCE(sum(a.points_awarded),0)+COALESCE(sum(a.completion_points_awarded),0))::integer AS activity_points
FROM public.competition_attendance a
LEFT JOIN public.profiles p ON p.id=a.user_id
GROUP BY a.user_id,p.nickname;

-- Apply the complete remaining candidate release chain in one database, in order.
\ir ../../migrations/202611250001_protect_profile_fields_growth_system_updates.sql
\ir ../../migrations/202611250003_growth_achievement_user_scope_guard.sql
\ir ../../migrations/202611250004_security_definer_execution_scope_guard.sql
\ir ../../migrations/202611250005_activity_member_stats_and_public_leaderboard.sql

-- Final ownership and ACL assertions.
DO $final_acl$
DECLARE
  n integer;
  award_oid oid := 'public.award_growth_points(uuid,integer,text,text,text,text,uuid)'::regprocedure;
  refresh_oid oid := 'public.refresh_growth_level(uuid)'::regprocedure;
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proowner=(SELECT oid FROM pg_roles WHERE rolname='growth_points_executor'))<>3 THEN
    RAISE EXCEPTION 'growth executor must own exactly three functions';
  END IF;
  IF NOT has_schema_privilege('growth_points_executor','auth','USAGE')
     OR NOT has_function_privilege('growth_points_executor','auth.uid()','EXECUTE') THEN
    RAISE EXCEPTION 'growth executor is missing minimal auth.uid access';
  END IF;
  IF NOT has_function_privilege('growth_points_executor','public._refresh_growth_level_internal(uuid)','EXECUTE')
     OR has_function_privilege('anon','public._refresh_growth_level_internal(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public._refresh_growth_level_internal(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public._refresh_growth_level_internal(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'internal growth-level helper ACL mismatch';
  END IF;
  IF has_function_privilege('anon',award_oid,'EXECUTE')
     OR has_function_privilege('authenticated',award_oid,'EXECUTE')
     OR has_function_privilege('service_role',award_oid,'EXECUTE')
     OR NOT has_function_privilege('postgres',award_oid,'EXECUTE')
     OR has_function_privilege('anon',refresh_oid,'EXECUTE')
     OR has_function_privilege('authenticated',refresh_oid,'EXECUTE')
     OR has_function_privilege('service_role',refresh_oid,'EXECUTE')
     OR NOT has_function_privilege('postgres',refresh_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'growth internal RPC ACL mismatch after full chain';
  END IF;
  IF NOT has_function_privilege('anon','public.is_admin()','EXECUTE')
     OR has_function_privilege('service_role','public.is_admin()','EXECUTE') THEN
    RAISE EXCEPTION 'is_admin narrow public policy helper ACL mismatch';
  END IF;
  IF has_table_privilege('anon','public.activity_member_stats','SELECT')
     OR NOT has_table_privilege('authenticated','public.activity_member_stats','SELECT')
     OR NOT has_table_privilege('anon','public.activity_public_leaderboard','SELECT') THEN
    RAISE EXCEPTION 'view ACL mismatch after full chain';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.activity_member_stats'::regclass AND reloptions @> ARRAY['security_invoker=true']) THEN
    RAISE EXCEPTION 'activity_member_stats must be security_invoker';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='activity_public_leaderboard')<>5 THEN
    RAISE EXCEPTION 'public leaderboard must expose exactly five columns';
  END IF;
  IF has_function_privilege('anon','public.admin_delete_growth_reward(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.admin_delete_growth_reward(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.admin_delete_growth_reward(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'admin reward RPC ACL mismatch';
  END IF;
  IF has_function_privilege('anon','public.growth_registration_reward()','EXECUTE')
     OR has_function_privilege('authenticated','public.growth_registration_reward()','EXECUTE')
     OR has_function_privilege('service_role','public.growth_registration_reward()','EXECUTE') THEN
    RAISE EXCEPTION 'trigger function must not be directly executable by API roles';
  END IF;
END
$final_acl$;

-- Trigger dispatch must continue to work after direct EXECUTE is revoked.
INSERT INTO auth.users(id,email)
VALUES('00000000-0000-4000-8000-000000000070','full.chain.visitor@example.test')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.visitor_accounts(id)
VALUES('00000000-0000-4000-8000-000000000070');
DO $visitor_trigger$
BEGIN
  IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000070')<>'visitor' THEN
    RAISE EXCEPTION 'visitor profile trigger failed after ACL hardening';
  END IF;
  IF (SELECT member_no FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000070') IS NULL THEN
    RAISE EXCEPTION 'member number trigger failed after ACL hardening';
  END IF;
END
$visitor_trigger$;

-- Registration reward, member check-in, and settlement must all route through
-- the dedicated growth executor without duplicate point awards.
INSERT INTO public.competitions(
  id,name,published,checkin_enabled,checkin_code,checkin_points,completion_points,
  registration_deadline,registration_capacity,registration_approval
) VALUES(
  '00000000-0000-4000-8000-000000000061','Full chain activity',true,true,'FULL-CI',3,2,
  now()+interval '1 day',10,false
);
INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
VALUES(
  '00000000-0000-4000-8000-000000000071',
  '00000000-0000-4000-8000-000000000061',
  '00000000-0000-4000-8000-000000000070','active'
);
DO $registration_reward$
BEGIN
  IF (SELECT status FROM public.competition_registrations WHERE id='00000000-0000-4000-8000-000000000071')<>'approved' THEN
    RAISE EXCEPTION 'registration rules trigger did not approve registration';
  END IF;
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000070')<>5 THEN
    RAISE EXCEPTION 'registration reward did not add exactly five points';
  END IF;
  IF (SELECT count(*) FROM public.growth_point_transactions WHERE source_key='registration:00000000-0000-4000-8000-000000000071')<>1 THEN
    RAISE EXCEPTION 'registration reward ledger is missing or duplicated';
  END IF;
END
$registration_reward$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000070',false);
SET ROLE authenticated;
SELECT public.checkin_competition('00000000-0000-4000-8000-000000000061','FULL-CI');
SELECT public.checkin_competition('00000000-0000-4000-8000-000000000061','FULL-CI');
RESET ROLE;
DO $checkin_reward$
BEGIN
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000070')<>8 THEN
    RAISE EXCEPTION 'check-in retry awarded points more than once or failed';
  END IF;
  IF (SELECT count(*) FROM public.growth_point_transactions WHERE source_key='checkin:00000000-0000-4000-8000-000000000061:00000000-0000-4000-8000-000000000070')<>1 THEN
    RAISE EXCEPTION 'check-in idempotency ledger missing or duplicated';
  END IF;
END
$checkin_reward$;

-- Member can see only their own invoker-view row and cannot inspect another
-- member's achievements or call an admin reward RPC without admin identity.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000070',false);
SET ROLE authenticated;
DO $member_denials$
DECLARE denied boolean:=false; n integer;
BEGIN
  SELECT count(*) INTO n FROM public.activity_member_stats;
  IF n<>1 THEN RAISE EXCEPTION 'member invoker view expected one row, got %',n; END IF;
  denied:=false;
  BEGIN
    PERFORM public.check_growth_achievements('00000000-0000-4000-8000-000000000003');
  EXCEPTION WHEN OTHERS THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'member could check another member achievements'; END IF;
  denied:=false;
  BEGIN
    PERFORM public.admin_delete_growth_reward(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'member could execute admin reward action'; END IF;
END
$member_denials$;
RESET ROLE;

-- Admin can settle once; the second settlement is idempotent.
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
SELECT public.admin_settle_competition('00000000-0000-4000-8000-000000000061');
SELECT public.admin_settle_competition('00000000-0000-4000-8000-000000000061');
RESET ROLE;
DO $settlement$
BEGIN
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000070')<>10 THEN
    RAISE EXCEPTION 'settlement completion reward missing or duplicated';
  END IF;
  IF (SELECT count(*) FROM public.growth_point_transactions WHERE source_key='completion:00000000-0000-4000-8000-000000000061:00000000-0000-4000-8000-000000000070')<>1 THEN
    RAISE EXCEPTION 'completion reward ledger missing or duplicated';
  END IF;
END
$settlement$;

-- Admin sees the aggregate view; anonymous users see only the public
-- projection and never the member-history view.
SET ROLE anon;
DO $public_views$
DECLARE n integer;
BEGIN
  IF has_table_privilege('anon','public.activity_member_stats','SELECT') THEN
    RAISE EXCEPTION 'anonymous access to member-history view remains';
  END IF;
  SELECT count(*) INTO n FROM public.activity_public_leaderboard;
  IF n<1 THEN RAISE EXCEPTION 'public leaderboard has no aggregate rows'; END IF;
END
$public_views$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $admin_view$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM public.activity_member_stats;
  IF n<2 THEN RAISE EXCEPTION 'admin should see multiple member-history rows'; END IF;
END
$admin_view$;
RESET ROLE;

\echo 'PASS: complete 202611160001 -> 202611170001 -> 202611250001, 250003..005 release chain in one PostgreSQL 17 database'
