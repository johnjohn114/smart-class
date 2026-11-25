-- Isolated PostgreSQL 17 regression test for registration reward and RPC ACLs.
-- Run only in a fresh disposable database as postgres.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth, public TO anon, authenticated, service_role;
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
CREATE TABLE public.growth_levels (
  code text PRIMARY KEY, name text NOT NULL, min_points integer NOT NULL, sort_order integer NOT NULL DEFAULT 0
);
INSERT INTO public.growth_levels(code,name,min_points,sort_order)
VALUES ('newbie','新手',0,0),('active','活躍',5,1);
CREATE TABLE public.growth_point_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL, amount integer NOT NULL, reason text NOT NULL,
  source_type text NOT NULL DEFAULT 'manual', source_id text, source_key text UNIQUE,
  admin_user_id uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL, title text NOT NULL, content text NOT NULL,
  type text NOT NULL DEFAULT '一般', created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role='admin');
$function$;

CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.member_no IS DISTINCT FROM OLD.member_no
     OR NEW.growth_points IS DISTINCT FROM OLD.growth_points
     OR NEW.growth_level IS DISTINCT FROM OLD.growth_level
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN RAISE EXCEPTION 'You are not allowed to modify protected profile fields.'; END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER protect_profile_fields BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_fields();

CREATE OR REPLACE FUNCTION public.refresh_growth_level(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE lvl public.growth_levels%rowtype;
BEGIN
  SELECT * INTO lvl FROM public.growth_levels
  WHERE min_points <= coalesce((SELECT growth_points FROM public.profiles WHERE id=p_user_id),0)
  ORDER BY min_points DESC,sort_order DESC LIMIT 1;
  IF lvl.code IS NULL THEN lvl.code := 'newbie'; END IF;
  UPDATE public.profiles SET growth_level=lvl.code WHERE id=p_user_id;
  RETURN lvl.code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.award_growth_points(
 p_user_id uuid,p_amount integer,p_reason text,p_source_type text DEFAULT 'manual',
 p_source_id text DEFAULT NULL,p_source_key text DEFAULT NULL,p_admin_user_id uuid DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE new_points integer; old_points integer; old_level text; new_level text; level_name text;
BEGIN
  IF p_user_id IS NULL OR p_amount=0 THEN RAISE EXCEPTION '積分資料無效'; END IF;
  IF p_source_key IS NOT NULL AND EXISTS(SELECT 1 FROM public.growth_point_transactions WHERE source_key=p_source_key) THEN
    RETURN coalesce((SELECT growth_points FROM public.profiles WHERE id=p_user_id),0);
  END IF;
  SELECT growth_points,growth_level INTO old_points,old_level
  FROM public.profiles WHERE id=p_user_id FOR UPDATE;
  IF old_points IS NULL THEN RAISE EXCEPTION '找不到會員'; END IF;
  new_points:=old_points+p_amount;
  IF new_points<0 THEN RAISE EXCEPTION '積分不足，無法扣除'; END IF;
  UPDATE public.profiles SET growth_points=new_points WHERE id=p_user_id;
  INSERT INTO public.growth_point_transactions(user_id,amount,reason,source_type,source_id,source_key,admin_user_id)
  VALUES(p_user_id,p_amount,p_reason,p_source_type,p_source_id,p_source_key,p_admin_user_id);
  new_level:=public.refresh_growth_level(p_user_id);
  IF p_source_type <> 'reward' THEN
    INSERT INTO public.notifications(user_id,title,content,type)
    VALUES(p_user_id,CASE WHEN p_amount>0 THEN '💎 獲得成長積分' ELSE '💎 使用成長積分' END,
      CASE WHEN p_amount>0 THEN '你獲得 +'||p_amount||' 積分：'||coalesce(p_reason,'')
           ELSE '你使用 '||abs(p_amount)||' 積分：'||coalesce(p_reason,'') END,'成長');
  END IF;
  IF coalesce(old_level,'newbie') IS DISTINCT FROM new_level THEN
    SELECT name INTO level_name FROM public.growth_levels WHERE code=new_level;
    INSERT INTO public.notifications(user_id,title,content,type)
    VALUES(p_user_id,'🎉 會員等級升級！','恭喜你升級為「'||coalesce(level_name,new_level)||'」！','成長');
  END IF;
  RETURN new_points;
END;
$function$;

CREATE TABLE public.competitions(
 id uuid PRIMARY KEY, name text NOT NULL, published boolean NOT NULL DEFAULT false,
 checkin_enabled boolean NOT NULL DEFAULT false, checkin_code text,
 checkin_start_at timestamptz, checkin_end_at timestamptz, checkin_points integer DEFAULT 0
);
CREATE TABLE public.competition_registrations(
 id uuid PRIMARY KEY, competition_id uuid NOT NULL, user_id uuid NOT NULL,
 status text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.competition_attendance(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), competition_id uuid NOT NULL,
 registration_id uuid NOT NULL, user_id uuid NOT NULL, status text NOT NULL,
 checked_in_at timestamptz, points_awarded integer DEFAULT 0, updated_at timestamptz DEFAULT now()
);
CREATE OR REPLACE FUNCTION public.growth_registration_reward()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
 IF NEW.status IN ('active','pending','approved') THEN
   PERFORM public.award_growth_points(NEW.user_id,5,'完成活動／比賽報名','registration',NEW.id::text,'registration:'||NEW.id::text,NULL);
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER growth_registration_reward AFTER INSERT ON public.competition_registrations
FOR EACH ROW EXECUTE FUNCTION public.growth_registration_reward();
GRANT EXECUTE ON FUNCTION public.checkin_competition(uuid,text) TO authenticated;

INSERT INTO public.profiles(id,role,member_no,growth_points,growth_level)
VALUES('00000000-0000-4000-8000-000000000001','visitor',100,0,'newbie');

GRANT SELECT,UPDATE ON public.profiles TO authenticated;
GRANT INSERT ON public.competition_registrations TO authenticated;
GRANT SELECT,UPDATE ON public.profiles TO anon;
GRANT EXECUTE ON FUNCTION public.award_growth_points(uuid,integer,text,text,text,text,uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.refresh_growth_level(uuid) TO authenticated,anon;

\ir ../../migrations/202611250001_protect_profile_fields_growth_system_updates.sql

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
INSERT INTO public.competition_registrations(id,competition_id,user_id,status)
VALUES('00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000001','approved');
RESET ROLE;

DO $registration_success$
BEGIN
 IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 5 THEN
   RAISE EXCEPTION 'FAIL: registration did not award exactly five points';
 END IF;
 IF (SELECT count(*) FROM public.growth_point_transactions WHERE source_key='registration:00000000-0000-4000-8000-000000000010') <> 1 THEN
   RAISE EXCEPTION 'FAIL: registration reward transaction missing or duplicated';
 END IF;
 IF (SELECT count(*) FROM public.notifications WHERE user_id='00000000-0000-4000-8000-000000000001') < 1 THEN
   RAISE EXCEPTION 'FAIL: expected growth notification missing';
 END IF;
END
$registration_success$;

-- Ordinary members still cannot edit protected columns.
SET ROLE authenticated;
DO $member_protection$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN UPDATE public.profiles SET growth_points=999 WHERE id='00000000-0000-4000-8000-000000000001';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='You are not allowed to modify protected profile fields.' THEN denied:=true; ELSE RAISE; END IF; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed growth_points'; END IF;
 denied:=false;
 BEGIN UPDATE public.profiles SET role='admin' WHERE id='00000000-0000-4000-8000-000000000001';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='You are not allowed to modify protected profile fields.' THEN denied:=true; ELSE RAISE; END IF; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed role'; END IF;
 denied:=false;
 BEGIN UPDATE public.profiles SET member_no=1 WHERE id='00000000-0000-4000-8000-000000000001';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='You are not allowed to modify protected profile fields.' THEN denied:=true; ELSE RAISE; END IF; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: member changed member_no'; END IF;
END
$member_protection$;
RESET ROLE;

-- The previously exposed RPCs are no longer directly callable by anon/member.
SET ROLE anon;
DO $anon_denied$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.award_growth_points('00000000-0000-4000-8000-000000000001',100,'test'); 
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anon can execute award_growth_points'; END IF;
END
$anon_denied$;
RESET ROLE;

SET ROLE authenticated;
DO $refresh_denied$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.refresh_growth_level('00000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: authenticated can execute refresh_growth_level'; END IF;
END
$refresh_denied$;
RESET ROLE;

SET ROLE authenticated;
UPDATE public.profiles SET nickname='Member nickname'
WHERE id='00000000-0000-4000-8000-000000000001';
RESET ROLE;

DO $final$
BEGIN
 IF (SELECT nickname FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 'Member nickname' THEN
   RAISE EXCEPTION 'FAIL: ordinary nickname update stopped working';
 END IF;
 IF (SELECT growth_points FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 5 THEN
   RAISE EXCEPTION 'FAIL: points changed unexpectedly';
 END IF;
 IF (SELECT role FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000001') <> 'visitor' THEN
   RAISE EXCEPTION 'FAIL: role changed unexpectedly';
 END IF;
END
$final$;

\echo 'PASS: registration reward succeeds; member protections and growth RPC ACLs remain enforced'
