-- Candidate-only fix for registration reward rollback.
-- Verified against the production error path on 2026-11-25.
-- DO NOT apply to production until the isolated regression workflow passes
-- and the migration baseline / deployment order has been reviewed.
BEGIN;

CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
    -- Administrators retain the existing management behavior.
    IF public.is_admin() THEN
        RETURN NEW;
    END IF;

    -- Trusted postgres-owned SECURITY DEFINER routines may update only the
    -- system-maintained growth fields. Identity, role, member number, and
    -- creation timestamp remain protected even in this trusted path.
    --
    -- The effective current_user becomes the SECURITY DEFINER owner while
    -- its UPDATE runs. Ordinary PostgREST member updates remain
    -- current_user='authenticated' and cannot enter this branch.
    IF current_user = 'postgres'
       AND (NEW.growth_points IS DISTINCT FROM OLD.growth_points
            OR NEW.growth_level IS DISTINCT FROM OLD.growth_level)
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.role IS NOT DISTINCT FROM OLD.role
       AND NEW.member_no IS NOT DISTINCT FROM OLD.member_no
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
    THEN
        RETURN NEW;
    END IF;

    -- Ordinary users cannot modify any protected field.
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

COMMIT;
