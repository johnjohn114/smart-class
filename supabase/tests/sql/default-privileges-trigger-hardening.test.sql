-- Disposable PostgreSQL 17 regression test for default privileges and
-- the five live SECURITY DEFINER trigger side effects.
-- Run as postgres in a fresh database:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f this-file.sql

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE TABLE public.profiles(
  id uuid PRIMARY KEY,
  role text NOT NULL,
  member_no integer,
  nickname text,
  growth_points integer NOT NULL DEFAULT 0
);
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
CREATE TABLE public.competition_registrations(
  id uuid PRIMARY KEY,
  competition_id uuid NOT NULL REFERENCES public.competitions(id),
  user_id uuid NOT NULL,
  status text NOT NULL
);
CREATE TABLE public.competition_results(
  id uuid PRIMARY KEY,
  competition_id uuid NOT NULL REFERENCES public.competitions(id),
  user_id uuid,
  place integer
);
CREATE TABLE public.growth_point_transactions(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  source_key text UNIQUE
);

-- Small deterministic stand-in for the production points writer. Its unique
-- source_key models the idempotency behavior relied on by the two reward triggers.
CREATE OR REPLACE FUNCTION public.award_growth_points(
  p_user_id uuid, p_amount integer, p_reason text,
  p_source_type text DEFAULT NULL, p_source_id text DEFAULT NULL,
  p_source_key text DEFAULT NULL, p_admin_user_id uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.growth_point_transactions(user_id,amount,source_key)
  VALUES(p_user_id,p_amount,p_source_key)
  ON CONFLICT(source_key) DO NOTHING;
  IF FOUND THEN
    UPDATE public.profiles SET growth_points=growth_points+p_amount WHERE id=p_user_id;
  END IF;
  RETURN (SELECT growth_points FROM public.profiles WHERE id=p_user_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_member_no_and_nickname()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.check_competition_registration_rules()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.ensure_visitor_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $function$
BEGIN
  INSERT INTO public.profiles(id,role) VALUES(NEW.id,'visitor')
  ON CONFLICT(id) DO UPDATE SET role='visitor';
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.growth_registration_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('active','pending','approved') THEN
    PERFORM public.award_growth_points(NEW.user_id,5,'完成活動／比賽報名',
      'registration',NEW.id::text,'registration:'||NEW.id::text,NULL);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.growth_result_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE pts integer:=10; published boolean;
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  SELECT c.published INTO published FROM public.competitions c WHERE c.id=NEW.competition_id;
  IF coalesce(published,false) THEN
    pts:=CASE WHEN NEW.place=1 THEN 50 WHEN NEW.place=2 THEN 30 WHEN NEW.place=3 THEN 20 ELSE 10 END;
    PERFORM public.award_growth_points(NEW.user_id,pts,'比賽成績：第 '||NEW.place||' 名',
      'result',NEW.id::text,'result:'||NEW.id::text,NULL);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER profiles_assign_member_no
BEFORE INSERT ON public.profiles FOR EACH ROW
EXECUTE FUNCTION public.assign_member_no_and_nickname();
CREATE TRIGGER visitor_accounts_ensure_profile
AFTER INSERT ON public.visitor_accounts FOR EACH ROW
EXECUTE FUNCTION public.ensure_visitor_profile();
CREATE TRIGGER competition_registration_rules
BEFORE INSERT OR UPDATE ON public.competition_registrations FOR EACH ROW
EXECUTE FUNCTION public.check_competition_registration_rules();
CREATE TRIGGER growth_registration_reward
AFTER INSERT ON public.competition_registrations FOR EACH ROW
EXECUTE FUNCTION public.growth_registration_reward();
CREATE TRIGGER growth_result_reward
AFTER INSERT ON public.competition_results FOR EACH ROW
EXECUTE FUNCTION public.growth_result_reward();

-- Simulate the existing overly broad defaults for the application owner.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Simulate pre-existing direct EXECUTE grants on trigger functions.
GRANT EXECUTE ON FUNCTION public.assign_member_no_and_nickname() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_competition_registration_rules() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_visitor_profile() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.growth_registration_reward() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.growth_result_reward() TO anon, authenticated, service_role;

\ir ../../migrations/202611170001_default_privileges_and_trigger_hardening.sql

-- Newly created objects as postgres must not inherit API-role privileges.
CREATE TABLE public.default_acl_probe(id integer);
CREATE SEQUENCE public.default_acl_probe_seq;
CREATE FUNCTION public.default_acl_probe_fn() RETURNS integer LANGUAGE sql AS 'SELECT 1';
-- The PUBLIC EXECUTE default is global, so verify it is closed outside public too.
CREATE FUNCTION auth.default_acl_probe_fn() RETURNS integer LANGUAGE sql AS 'SELECT 1';
DO $default_acl$
BEGIN
  IF has_table_privilege('anon','public.default_acl_probe','SELECT')
     OR has_table_privilege('authenticated','public.default_acl_probe','SELECT')
     OR has_table_privilege('service_role','public.default_acl_probe','SELECT') THEN
    RAISE EXCEPTION 'FAIL: new table inherited API-role access';
  END IF;
  IF has_sequence_privilege('anon','public.default_acl_probe_seq','USAGE')
     OR has_sequence_privilege('authenticated','public.default_acl_probe_seq','USAGE')
     OR has_sequence_privilege('service_role','public.default_acl_probe_seq','USAGE') THEN
    RAISE EXCEPTION 'FAIL: new sequence inherited API-role access';
  END IF;
  IF has_function_privilege('anon','public.default_acl_probe_fn()','EXECUTE')
     OR has_function_privilege('authenticated','public.default_acl_probe_fn()','EXECUTE')
     OR has_function_privilege('service_role','public.default_acl_probe_fn()','EXECUTE')
     OR has_function_privilege('anon','auth.default_acl_probe_fn()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: new function inherited PUBLIC/API-role EXECUTE';
  END IF;
END
$default_acl$;

-- Existing admin profile must not be downgraded by a visitor-account event.
INSERT INTO public.profiles(id,role) VALUES('00000000-0000-4000-8000-000000000001','admin');
INSERT INTO public.visitor_accounts(id) VALUES('00000000-0000-4000-8000-000000000001');
DO $profile_conflict$
BEGIN
  IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 'admin' THEN
    RAISE EXCEPTION 'FAIL: visitor account insert downgraded existing admin profile';
  END IF;
  IF (SELECT next_no FROM public.member_no_counter WHERE id=true) <> 100 THEN
    RAISE EXCEPTION 'FAIL: conflicting profile insert consumed a member number';
  END IF;
END
$profile_conflict$;

-- New visitor account still creates a visitor profile.
INSERT INTO auth.users(id,email) VALUES
('00000000-0000-4000-8000-000000000002','new.member@example.test'),
('00000000-0000-4000-8000-000000000003','member.three@example.test');
INSERT INTO public.visitor_accounts(id) VALUES('00000000-0000-4000-8000-000000000002');
DO $profile_create$
BEGIN
  IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000002') <> 'visitor' THEN
    RAISE EXCEPTION 'FAIL: visitor profile was not created';
  END IF;
  IF (SELECT member_no FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000002') <> 100 THEN
    RAISE EXCEPTION 'FAIL: visitor-account trigger did not allocate the first member number';
  END IF;
END
$profile_create$;

-- Member-number trigger still assigns a number and email-derived nickname.
INSERT INTO public.profiles(id,role) VALUES('00000000-0000-4000-8000-000000000003','visitor');
DO $member_number$
BEGIN
  IF (SELECT member_no FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000003') <> 101 THEN
    RAISE EXCEPTION 'FAIL: member number trigger did not assign expected number';
  END IF;
  IF (SELECT nickname FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000003') <> 'member.three' THEN
    RAISE EXCEPTION 'FAIL: member nickname was not derived from Auth email';
  END IF;
END
$member_number$;

INSERT INTO public.profiles(id,role) VALUES('00000000-0000-4000-8000-000000000004','visitor');
DO $member_number_second$
BEGIN
  IF (SELECT member_no FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000004') <> 102 THEN
    RAISE EXCEPTION 'FAIL: member number counter did not increment';
  END IF;
END
$member_number_second$;

-- Registration deadline, capacity and approval state remain enforced.
INSERT INTO public.competitions(id,registration_deadline,registration_capacity,registration_approval)
VALUES('00000000-0000-4000-8000-000000000010',now()+interval '1 day',1,true);
INSERT INTO public.profiles(id,role) VALUES('00000000-0000-4000-8000-000000000011','visitor');
INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
VALUES('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000011','active');
DO $registration_state$
BEGIN
  IF (SELECT status FROM public.competition_registrations WHERE id='00000000-0000-4000-8000-000000000012') <> 'pending' THEN
    RAISE EXCEPTION 'FAIL: approval-required registration was not pending';
  END IF;
END
$registration_state$;

-- Expired registration windows must also be rejected.
INSERT INTO public.competitions(id,registration_deadline,registration_capacity,registration_approval)
VALUES('00000000-0000-4000-8000-000000000015',now()-interval '1 day',5,false);
DO $registration_deadline$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
    VALUES('00000000-0000-4000-8000-000000000016','00000000-0000-4000-8000-000000000015','00000000-0000-4000-8000-000000000017','active');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='報名已截止' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: expired registration deadline was not enforced'; END IF;
END
$registration_deadline$;

DO $registration_capacity$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
    VALUES('00000000-0000-4000-8000-000000000013','00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000014','active');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='報名名額已滿' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: registration capacity was not enforced'; END IF;
END
$registration_capacity$;

INSERT INTO public.competitions(id,published) VALUES
('00000000-0000-4000-8000-000000000020',false),
('00000000-0000-4000-8000-000000000021',true);
INSERT INTO public.profiles(id,role) VALUES('00000000-0000-4000-8000-000000000022','visitor');
INSERT INTO public.competition_results(id,competition_id,user_id,place)
VALUES('00000000-0000-4000-8000-000000000023','00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000022',1);
INSERT INTO public.competition_results(id,competition_id,user_id,place)
VALUES('00000000-0000-4000-8000-000000000024','00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000022',1);
-- Duplicate invocation must be idempotent because the source key is unique.
SELECT public.award_growth_points('00000000-0000-4000-8000-000000000022',50,'duplicate test','result','00000000-0000-4000-8000-000000000024','result:00000000-0000-4000-8000-000000000024',NULL);

DO $rewards$
BEGIN
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000022') <> 50 THEN
    RAISE EXCEPTION 'FAIL: published-result reward missing or unpublished result awarded points';
  END IF;
  IF (SELECT count(*) FROM public.growth_point_transactions WHERE user_id='00000000-0000-4000-8000-000000000022') <> 1 THEN
    RAISE EXCEPTION 'FAIL: result reward was not idempotent';
  END IF;
  IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000011') <> 5 THEN
    RAISE EXCEPTION 'FAIL: registration reward was not awarded';
  END IF;
END
$rewards$;

-- API roles cannot directly execute trigger functions, but triggers still fire.
DO $trigger_acl$
BEGIN
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
    RAISE EXCEPTION 'FAIL: API role retains direct EXECUTE on trigger functions';
  END IF;
END
$trigger_acl$;

\echo 'PASS: default privileges and five trigger side-effect regression tests'
