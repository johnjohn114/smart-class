-- Candidate-only fix for registration reward rollback and overly broad RPC ACLs.
-- DO NOT apply to production until isolated tests pass and migration baseline/order is reviewed.
BEGIN;

-- Dedicated NOLOGIN owner for only the two growth-maintenance SECURITY DEFINER
-- functions. Its table privileges are deliberately column/table scoped.
DO $role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_points_executor') THEN
    CREATE ROLE growth_points_executor NOLOGIN BYPASSRLS;
  ELSE
    ALTER ROLE growth_points_executor NOLOGIN BYPASSRLS;
  END IF;
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

COMMIT;
