-- Expected-failure regression: the ACL migration must reject an unreviewed
-- public SECURITY DEFINER function before changing any grants.
-- Run only in a fresh disposable PostgreSQL database as postgres.
CREATE FUNCTION public.unexpected_public_security_definer()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $function$
  SELECT true
$function$;

\ir ../../migrations/202611250004_security_definer_execution_scope_guard.sql
