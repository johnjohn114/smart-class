-- Candidate-only fix for registration reward rollback and overly broad RPC ACLs.
-- DO NOT apply to production until isolated tests pass and migration baseline/order is reviewed.
BEGIN;

-- Dedicated NOLOGIN owner for only the two growth-maintenance SECURITY DEFINER
-- functions. Its table privileges are deliberately column/table scoped.
DO $role$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_points_executor') THEN
    RAISE EXCEPTION 'growth_points_executor already exists; review the role before applying this migration';
  END IF;
  CREATE ROLE growth_points_executor NOLOGIN BYPASSRLS;
END
$role$;

GRANT USAGE ON SCHEMA public TO growth_points_executor;
-- PostgreSQL requires CREATE on the target schema while transferring ownership.
GRANT CREATE ON SCHEMA public TO growth_points_executor;
GRANT EXECUTE ON FUNCTION public.is_admin() TO growth_points_executor;
GRANT SELECT ON public.profiles, public.growth_levels,
                public.growth_point_transactions
TO growth_points_executor;
GRANT UPDATE (growth_points, growth_level)
ON public.profiles TO growth_points_executor;
GRANT INSERT ON public.growth_point_transactions, public.notifications
TO growth_points_executor;

-- These functions are the only functions owned by this restricted executor.
ALTER FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) OWNER TO growth_points_executor;
ALTER FUNCTION public.refresh_growth_level(uuid)
  OWNER TO growth_points_executor;
REVOKE CREATE ON SCHEMA public FROM growth_points_executor;

CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
    IF public.is_admin() THEN
        RETURN NEW;
    END IF;

    -- Only the dedicated function owner may update these two system fields.
    -- The other protected identity/authorization fields remain immutable.
    IF current_user = 'growth_points_executor'
       AND (NEW.growth_points IS DISTINCT FROM OLD.growth_points
            OR NEW.growth_level IS DISTINCT FROM OLD.growth_level)
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.role IS NOT DISTINCT FROM OLD.role
       AND NEW.member_no IS NOT DISTINCT FROM OLD.member_no
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
    THEN
        RETURN NEW;
    END IF;

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

-- These routines must not be callable directly by public/ordinary members.
-- Trusted SECURITY DEFINER admin routines and the postgres-owned trigger
-- function continue to invoke them through their existing trusted context.
REVOKE EXECUTE ON FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_growth_points(
  uuid, integer, text, text, text, text, uuid
) TO service_role;

REVOKE EXECUTE ON FUNCTION public.refresh_growth_level(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_growth_level(uuid)
  TO service_role;

-- Route member check-in rewards through the restricted growth executor.
-- Previously this SECURITY DEFINER function updated profiles directly as
-- postgres, which the protected-field trigger correctly rejects for members.
-- Preserve production check-in behavior while routing protected profile
-- updates through the narrowly-owned growth RPC.
CREATE OR REPLACE FUNCTION public.checkin_competition(p_competition_id uuid, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_comp public.competitions%rowtype;
  v_reg public.competition_registrations%rowtype;
  v_att public.competition_attendance%rowtype;
  v_points integer := 0;
  v_status text := 'checked_in';
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '請先登入會員帳號'; END IF;
  SELECT * INTO v_comp FROM public.competitions WHERE id=p_competition_id AND published=true;
  IF NOT FOUND THEN RAISE EXCEPTION '找不到已公布的活動'; END IF;
  IF NOT coalesce(v_comp.checkin_enabled,false) THEN RAISE EXCEPTION '此活動尚未開放簽到'; END IF;
  IF coalesce(v_comp.checkin_code,'') <> coalesce(trim(p_code),'') THEN RAISE EXCEPTION '簽到碼錯誤'; END IF;
  IF v_comp.checkin_start_at IS NOT NULL AND now() < v_comp.checkin_start_at THEN RAISE EXCEPTION '尚未到簽到時間'; END IF;
  IF v_comp.checkin_end_at IS NOT NULL AND now() > v_comp.checkin_end_at THEN RAISE EXCEPTION '簽到時間已結束'; END IF;

  SELECT * INTO v_reg FROM public.competition_registrations
  WHERE competition_id=p_competition_id AND user_id=v_user AND status IN ('active','approved')
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION '請先完成活動報名'; END IF;

  SELECT * INTO v_att FROM public.competition_attendance WHERE competition_id=p_competition_id AND user_id=v_user;
  IF FOUND AND v_att.status IN ('checked_in','late') THEN
    RETURN jsonb_build_object('success',true,'already',true,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_att.points_awarded);
  END IF;

  v_points := greatest(coalesce(v_comp.checkin_points,0),0);
  IF v_att.id IS NULL THEN
    INSERT INTO public.competition_attendance(competition_id,registration_id,user_id,status,checked_in_at,points_awarded)
    VALUES(v_comp.id,v_reg.id,v_user,v_status,now(),v_points)
    RETURNING * INTO v_att;
  ELSE
    UPDATE public.competition_attendance
    SET registration_id=v_reg.id,status=v_status,checked_in_at=now(),points_awarded=v_points,updated_at=now()
    WHERE id=v_att.id RETURNING * INTO v_att;
  END IF;

  IF v_points > 0 THEN
    PERFORM public.award_growth_points(
      v_user, v_points, '活動簽到：' || v_comp.name,
      'activity_checkin', v_comp.id::text,
      'checkin:' || v_comp.id::text || ':' || v_user::text, NULL
    );
  END IF;

  BEGIN
    PERFORM public.record_growth_activity();
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success',true,'already',false,'attendance_id',v_att.id,'status',v_att.status,'points_awarded',v_points);
END;
$function$;

COMMIT;
