-- Default privilege and trigger-side-effect hardening.
-- Apply only after isolated PostgreSQL 17 regression tests pass.
-- This migration intentionally changes defaults for the application migration
-- owner (postgres) in public only. Supabase-managed supabase_admin defaults
-- are deliberately untouched pending platform-owner review.
BEGIN;

-- Make future application-owned objects opt-in for API roles.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- Preserve existing visitor/admin profiles on auth-account insert conflicts.
CREATE OR REPLACE FUNCTION public.ensure_visitor_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.profiles(id, role)
  VALUES (NEW.id, 'visitor')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;

-- Trigger invocation does not require API roles to have direct EXECUTE.
REVOKE ALL ON FUNCTION public.assign_member_no_and_nickname()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.check_competition_registration_rules()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ensure_visitor_profile()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.growth_registration_reward()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.growth_result_reward()
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
