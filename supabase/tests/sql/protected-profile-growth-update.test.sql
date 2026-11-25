-- Isolated PostgreSQL 17 regression test for the registration reward fix.
-- Run in a fresh disposable database as postgres:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f this-file.sql

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth, public TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY,
  role text NOT NULL,
  member_no integer NOT NULL,
  growth_points integer NOT NULL DEFAULT 0,
  growth_level text NOT NULL DEFAULT 'newbie',
  created_at timestamptz NOT NULL DEFAULT now(),
  nickname text
);

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$function$;

-- Production-equivalent guard before the candidate migration is applied.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
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

CREATE TRIGGER protect_profile_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_fields();

CREATE TABLE public.growth_point_transactions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  source_key text UNIQUE NOT NULL
);

CREATE OR REPLACE FUNCTION public.award_growth_points(
  p_user_id uuid, p_amount integer, p_source_key text
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE new_points integer;
BEGIN
  UPDATE public.profiles
  SET growth_points = growth_points + p_amount
  WHERE id = p_user_id
  RETURNING growth_points INTO new_points;

  IF new_points IS NULL THEN RAISE EXCEPTION 'member not found'; END IF;

  INSERT INTO public.growth_point_transactions(user_id, amount, source_key)
  VALUES (p_user_id, p_amount, p_source_key);

  RETURN new_points;
END;
$function$;

CREATE TABLE public.competition_registrations (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  status text NOT NULL
);

CREATE OR REPLACE FUNCTION public.growth_registration_reward()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  IF NEW.status IN ('active','pending','approved') THEN
    PERFORM public.award_growth_points(
      NEW.user_id, 5, 'registration:' || NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER growth_registration_reward
AFTER INSERT ON public.competition_registrations
FOR EACH ROW EXECUTE FUNCTION public.growth_registration_reward();

INSERT INTO public.profiles(id, role, member_no, growth_points, growth_level)
VALUES ('00000000-0000-4000-8000-000000000001','visitor',100,0,'newbie');

GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT INSERT ON public.competition_registrations TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Apply the candidate patch only to this disposable test database.
\ir ../../migrations/202611250001_protect_profile_fields_growth_system_updates.sql

-- A real authenticated registration must commit and award exactly five points.
SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
INSERT INTO public.competition_registrations(id,user_id,status)
VALUES (
  '00000000-0000-4000-8000-000000000010',
  '00000000-0000-4000-8000-000000000001',
  'approved'
);
RESET ROLE;

DO $registration_success$
BEGIN
  IF (SELECT growth_points FROM public.profiles
      WHERE id='00000000-0000-4000-8000-000000000001') <> 5 THEN
    RAISE EXCEPTION 'FAIL: registration did not award exactly five points';
  END IF;
  IF (SELECT count(*) FROM public.growth_point_transactions
      WHERE source_key='registration:00000000-0000-4000-8000-000000000010') <> 1 THEN
    RAISE EXCEPTION 'FAIL: registration reward transaction missing or duplicated';
  END IF;
END
$registration_success$;

-- Direct member attempts to alter protected fields must still be rejected.
SET ROLE authenticated;
DO $member_protection$
DECLARE denied boolean;
BEGIN
  denied := false;
  BEGIN
    UPDATE public.profiles SET growth_points=999
    WHERE id='00000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'You are not allowed to modify protected profile fields.' THEN
      denied := true;
    ELSE RAISE;
    END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed growth_points directly'; END IF;

  denied := false;
  BEGIN
    UPDATE public.profiles SET role='admin'
    WHERE id='00000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'You are not allowed to modify protected profile fields.' THEN
      denied := true;
    ELSE RAISE;
    END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed role directly'; END IF;

  denied := false;
  BEGIN
    UPDATE public.profiles SET member_no=1
    WHERE id='00000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'You are not allowed to modify protected profile fields.' THEN
      denied := true;
    ELSE RAISE;
    END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed member_no directly'; END IF;
END
$member_protection$;
RESET ROLE;

-- Non-protected profile edits remain available to the owning member.
SET ROLE authenticated;
UPDATE public.profiles SET nickname='Member nickname'
WHERE id='00000000-0000-4000-8000-000000000001';
RESET ROLE;

DO $final$
BEGIN
  IF (SELECT nickname FROM public.profiles
      WHERE id='00000000-0000-4000-8000-000000000001') <> 'Member nickname' THEN
    RAISE EXCEPTION 'FAIL: ordinary nickname update stopped working';
  END IF;
  IF (SELECT growth_points FROM public.profiles
      WHERE id='00000000-0000-4000-8000-000000000001') <> 5 THEN
    RAISE EXCEPTION 'FAIL: direct update changed growth points';
  END IF;
  IF (SELECT role FROM public.profiles
      WHERE id='00000000-0000-4000-8000-000000000001') <> 'visitor' THEN
    RAISE EXCEPTION 'FAIL: direct update changed member role';
  END IF;
END
$final$;

\echo 'PASS: registration reward succeeds while protected profile fields remain protected'
