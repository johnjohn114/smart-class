-- Read-only catalog assertions for activity_member_stats view hardening.
-- Run only in a disposable CI database after applying the candidate SQL.
-- Does not inspect or print user attendance/profile rows.

DO $$
DECLARE
  v_oid oid;
  v_options text[];
BEGIN
  SELECT c.oid, c.reloptions
    INTO v_oid, v_options
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'activity_member_stats'
    AND c.relkind = 'v';

  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'public.activity_member_stats view is missing';
  END IF;

  IF NOT coalesce(v_options @> ARRAY['security_invoker=true'], false) THEN
    RAISE EXCEPTION 'activity_member_stats must set security_invoker=true';
  END IF;

  IF has_table_privilege('anon', 'public.activity_member_stats', 'SELECT') THEN
    RAISE EXCEPTION 'anon must not have SELECT on activity_member_stats';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.activity_member_stats', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated must retain SELECT on activity_member_stats';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.activity_member_stats', 'SELECT') THEN
    RAISE EXCEPTION 'service_role must retain SELECT on activity_member_stats';
  END IF;

  IF NOT (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'public.competition_attendance'::regclass
  ) THEN
    RAISE EXCEPTION 'competition_attendance RLS must remain enabled';
  END IF;

  IF NOT (
    SELECT relrowsecurity
    FROM pg_class
    WHERE oid = 'public.profiles'::regclass
  ) THEN
    RAISE EXCEPTION 'profiles RLS must remain enabled';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('competition_attendance', 'profiles')
      AND ('anon' = ANY (roles) OR 'public' = ANY (roles))
      AND cmd IN ('SELECT', 'ALL')
  ) THEN
    RAISE EXCEPTION 'unexpected anon/PUBLIC SELECT policy on underlying tables';
  END IF;
END;
$$;
