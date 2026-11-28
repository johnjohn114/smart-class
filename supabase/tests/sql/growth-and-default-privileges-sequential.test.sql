-- Sequential integration test: apply both real hardening migrations to one
-- coherent disposable PostgreSQL 17 fixture. Production is never contacted.
-- Run as postgres from the repository root.
\ir growth-function-authorization.test.sql

-- Extend the growth fixture with the minimum schema needed by the five
-- production trigger functions. Existing growth tables/functions are reused.
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS member_no integer;
CREATE TABLE public.member_no_counter(id boolean PRIMARY KEY DEFAULT true, next_no integer NOT NULL);
INSERT INTO public.member_no_counter(id,next_no) VALUES(true,100);
CREATE TABLE public.visitor_accounts(id uuid PRIMARY KEY);

CREATE TABLE public.competitions(
  id uuid PRIMARY KEY,
  registration_deadline timestamptz,
  registration_capacity integer,
  registration_approval boolean NOT NULL DEFAULT false,
  published boolean NOT NULL DEFAULT false
);
ALTER TABLE public.competition_registrations
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS competition_id uuid;
ALTER TABLE public.competition_registrations
  ALTER COLUMN id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ci_competition_registrations_id_uq
  ON public.competition_registrations(id);
ALTER TABLE public.competition_results
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS competition_id uuid;
ALTER TABLE public.competition_results
  ALTER COLUMN id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ci_competition_results_id_uq
  ON public.competition_results(id);
CREATE UNIQUE INDEX IF NOT EXISTS ci_growth_point_transactions_source_key_uq
  ON public.growth_point_transactions(source_key);

-- Preserve the Storage-specific defaults as a control while the public
-- defaults are tightened by the second migration.
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assign_member_no_and_nickname()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE mail text; assigned_no integer;
BEGIN
  IF NEW.role='visitor' THEN
    IF NEW.member_no IS NULL THEN
      UPDATE public.member_no_counter SET next_no=next_no+1
      WHERE id=true RETURNING next_no-1 INTO assigned_no;
      NEW.member_no:=coalesce(assigned_no,1);
    END IF;
    IF nullif(trim(coalesce(NEW.nickname,'')),'') IS NULL THEN
      SELECT email INTO mail FROM auth.users WHERE id=NEW.id;
      NEW.nickname:=coalesce(nullif(split_part(coalesce(mail,''),'@',1),''),'會員');
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.check_competition_registration_rules()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE c public.competitions%rowtype; active_count integer; next_status text;
BEGIN
  SELECT * INTO c FROM public.competitions WHERE id=NEW.competition_id;
  IF c.id IS NULL THEN RAISE EXCEPTION '找不到活動／比賽'; END IF;
  IF NEW.status IN ('cancelled','rejected') THEN RETURN NEW; END IF;
  IF c.registration_deadline IS NOT NULL AND now()>c.registration_deadline THEN RAISE EXCEPTION '報名已截止'; END IF;
  IF c.registration_capacity IS NOT NULL AND c.registration_capacity>0 THEN
    SELECT count(*) INTO active_count FROM public.competition_registrations
    WHERE competition_id=NEW.competition_id AND user_id<>NEW.user_id
      AND status IN ('active','pending','approved');
    IF active_count>=c.registration_capacity THEN RAISE EXCEPTION '報名名額已滿'; END IF;
  END IF;
  next_status:=CASE WHEN c.registration_approval THEN 'pending' ELSE 'approved' END;
  IF TG_OP='INSERT' THEN NEW.status:=next_status; END IF;
  IF TG_OP='UPDATE' AND NEW.status='active' THEN NEW.status:=next_status; END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.ensure_visitor_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
BEGIN
  INSERT INTO public.profiles(id,role) VALUES(NEW.id,'visitor')
  ON CONFLICT(id) DO UPDATE SET role='visitor';
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.growth_registration_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status IN ('active','pending','approved') THEN
    PERFORM public.award_growth_points(NEW.user_id,5,'完成活動／比賽報名',
      'registration',NEW.id::text,'registration:'||NEW.id::text,NULL);
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.growth_result_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE pts integer:=10; is_published boolean;
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  SELECT c.published INTO is_published FROM public.competitions c WHERE c.id=NEW.competition_id;
  IF coalesce(is_published,false) THEN
    pts:=CASE WHEN NEW.place=1 THEN 50 WHEN NEW.place=2 THEN 30 WHEN NEW.place=3 THEN 20 ELSE 10 END;
    PERFORM public.award_growth_points(NEW.user_id,pts,'比賽成績：第 '||NEW.place||' 名',
      'result',NEW.id::text,'result:'||NEW.id::text,NULL);
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER ci_profiles_assign_member_no
BEFORE INSERT ON public.profiles FOR EACH ROW
EXECUTE FUNCTION public.assign_member_no_and_nickname();
CREATE TRIGGER ci_visitor_accounts_ensure_profile
AFTER INSERT ON public.visitor_accounts FOR EACH ROW
EXECUTE FUNCTION public.ensure_visitor_profile();
CREATE TRIGGER ci_competition_registration_rules
BEFORE INSERT OR UPDATE ON public.competition_registrations FOR EACH ROW
EXECUTE FUNCTION public.check_competition_registration_rules();
CREATE TRIGGER ci_growth_registration_reward
AFTER INSERT ON public.competition_registrations FOR EACH ROW
EXECUTE FUNCTION public.growth_registration_reward();
CREATE TRIGGER ci_growth_result_reward
AFTER INSERT ON public.competition_results FOR EACH ROW
EXECUTE FUNCTION public.growth_result_reward();

-- The second migration must compose after the first, without rebuilding or
-- replacing the shared fixture.
\ir ../../migrations/202611170001_default_privileges_and_trigger_hardening.sql

CREATE TABLE public.sequential_default_table(id integer);
CREATE SEQUENCE public.sequential_default_sequence;
CREATE FUNCTION public.sequential_default_function() RETURNS integer
LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION auth.sequential_default_function() RETURNS integer
LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION storage.sequential_default_function() RETURNS integer
LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION extensions.sequential_default_function() RETURNS integer
LANGUAGE sql AS 'SELECT 1';

DO $combined_defaults$
BEGIN
  IF has_table_privilege('anon','public.sequential_default_table','SELECT')
     OR has_table_privilege('authenticated','public.sequential_default_table','SELECT')
     OR has_table_privilege('service_role','public.sequential_default_table','SELECT') THEN
    RAISE EXCEPTION 'FAIL: sequential public table defaults remain open';
  END IF;
  IF has_sequence_privilege('anon','public.sequential_default_sequence','USAGE')
     OR has_sequence_privilege('authenticated','public.sequential_default_sequence','USAGE')
     OR has_sequence_privilege('service_role','public.sequential_default_sequence','USAGE') THEN
    RAISE EXCEPTION 'FAIL: sequential public sequence defaults remain open';
  END IF;
  IF has_function_privilege('anon','public.sequential_default_function()','EXECUTE')
     OR has_function_privilege('authenticated','public.sequential_default_function()','EXECUTE')
     OR has_function_privilege('service_role','public.sequential_default_function()','EXECUTE')
     OR has_function_privilege('anon','auth.sequential_default_function()','EXECUTE')
     OR has_function_privilege('anon','extensions.sequential_default_function()','EXECUTE')
     OR has_function_privilege('authenticated','extensions.sequential_default_function()','EXECUTE')
     OR has_function_privilege('service_role','extensions.sequential_default_function()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: PUBLIC/API function defaults remain open';
  END IF;
  IF NOT has_function_privilege('anon','storage.sequential_default_function()','EXECUTE')
     OR NOT has_function_privilege('authenticated','storage.sequential_default_function()','EXECUTE')
     OR NOT has_function_privilege('service_role','storage.sequential_default_function()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: Storage-specific function defaults changed unexpectedly';
  END IF;
END
$combined_defaults$;

-- A new overloaded SECURITY DEFINER routine must not inherit API EXECUTE.
CREATE FUNCTION public.complete_growth_task(p_task_code text, p_extra text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS 'SELECT true';
DO $overload_acl$
BEGIN
  IF has_function_privilege('anon','public.complete_growth_task(text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.complete_growth_task(text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: newly added SECURITY DEFINER overload became a public RPC';
  END IF;
END
$overload_acl$;

-- Existing admin must remain admin and a conflict must not consume a number.
INSERT INTO public.visitor_accounts(id)
VALUES('00000000-0000-4000-8000-000000000001');
DO $profile_conflict$
BEGIN
  IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 'admin' THEN
    RAISE EXCEPTION 'FAIL: existing admin profile was downgraded';
  END IF;
  IF (SELECT next_no FROM public.member_no_counter WHERE id=true) <> 100 THEN
    RAISE EXCEPTION 'FAIL: profile conflict consumed a member number';
  END IF;
END
$profile_conflict$;

-- New visitor profile and member-number/nickname triggers still work.
INSERT INTO auth.users(id,email) VALUES
('00000000-0000-4000-8000-000000000050','sequential.visitor@example.test');
INSERT INTO public.visitor_accounts(id)
VALUES('00000000-0000-4000-8000-000000000050');
DO $visitor_create$
BEGIN
  IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000050') <> 'visitor'
     OR (SELECT member_no FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000050') <> 100 THEN
    RAISE EXCEPTION 'FAIL: visitor-account trigger did not create/number the profile';
  END IF;
END
$visitor_create$;

-- Registration validation, approval state, and reward trigger remain active.
INSERT INTO public.competitions(id,registration_deadline,registration_capacity,registration_approval,published)
VALUES('00000000-0000-4000-8000-000000000060',now()+interval '1 day',2,true,true);
INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
VALUES('00000000-0000-4000-8000-000000000061',
       '00000000-0000-4000-8000-000000000060',
       '00000000-0000-4000-8000-000000000050','active');
DO $registration_check$
BEGIN
  IF (SELECT status FROM public.competition_registrations WHERE id='00000000-0000-4000-8000-000000000061') <> 'pending' THEN
    RAISE EXCEPTION 'FAIL: approval-required registration was not converted to pending';
  END IF;
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000050') <> 5 THEN
    RAISE EXCEPTION 'FAIL: registration reward trigger did not award points';
  END IF;
END
$registration_check$;

INSERT INTO public.competition_results(id,competition_id,user_id,place)
VALUES('00000000-0000-4000-8000-000000000062',
       '00000000-0000-4000-8000-000000000060',
       '00000000-0000-4000-8000-000000000050',1);
DO $result_check$
BEGIN
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000050') <> 55 THEN
    RAISE EXCEPTION 'FAIL: published-result reward trigger did not award points';
  END IF;
END
$result_check$;

DO $five_trigger_acl$
DECLARE trigger_count integer;
BEGIN
  SELECT count(*) INTO trigger_count
  FROM pg_trigger
  WHERE NOT tgisinternal
    AND tgname IN (
      'ci_profiles_assign_member_no',
      'ci_visitor_accounts_ensure_profile',
      'ci_competition_registration_rules',
      'ci_growth_registration_reward',
      'ci_growth_result_reward'
    );
  IF trigger_count <> 5 THEN
    RAISE EXCEPTION 'FAIL: expected five live trigger bindings, found %', trigger_count;
  END IF;
  IF has_function_privilege('anon','public.assign_member_no_and_nickname()','EXECUTE')
     OR has_function_privilege('authenticated','public.assign_member_no_and_nickname()','EXECUTE')
     OR has_function_privilege('service_role','public.assign_member_no_and_nickname()','EXECUTE')
     OR has_function_privilege('anon','public.check_competition_registration_rules()','EXECUTE')
     OR has_function_privilege('authenticated','public.check_competition_registration_rules()','EXECUTE')
     OR has_function_privilege('service_role','public.check_competition_registration_rules()','EXECUTE')
     OR has_function_privilege('anon','public.ensure_visitor_profile()','EXECUTE')
     OR has_function_privilege('authenticated','public.ensure_visitor_profile()','EXECUTE')
     OR has_function_privilege('service_role','public.ensure_visitor_profile()','EXECUTE')
     OR has_function_privilege('anon','public.growth_registration_reward()','EXECUTE')
     OR has_function_privilege('authenticated','public.growth_registration_reward()','EXECUTE')
     OR has_function_privilege('service_role','public.growth_registration_reward()','EXECUTE')
     OR has_function_privilege('anon','public.growth_result_reward()','EXECUTE')
     OR has_function_privilege('authenticated','public.growth_result_reward()','EXECUTE')
     OR has_function_privilege('service_role','public.growth_result_reward()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: direct API-role EXECUTE remains on a trigger function';
  END IF;
END
$five_trigger_acl$;

\echo 'PASS: both hardening migrations applied sequentially; ACLs, defaults, overload denial, and five trigger behaviors verified'
