-- Candidate-only SECURITY DEFINER ACL hardening. Do not apply to production
-- until the live migration baseline and all function call sites are reconciled.
-- This is the final ACL layer and intentionally supersedes the temporary
-- service_role grants in migrations 002/003: application RPCs must run with
-- the signed-in user's authenticated JWT so auth.uid() and in-function
-- authorization checks identify the real caller. No in-repository
-- service_role Edge Function call sites were found in the audited source set;
-- external integrations remain outside that inventory.
BEGIN;
DO $acl$
DECLARE
  nm text;
  oid_ regprocedure;
  admin_names text[] := ARRAY['admin_activity_analytics','admin_adjust_growth_points','admin_apply_competition_rewards','admin_cancel_order','admin_complete_order','admin_delete_growth_reward','admin_delete_video','admin_grant_competition_reward','admin_mark_competition_attendance','admin_mark_competition_member_attendance','admin_mark_order_paid','admin_promote_competition_waitlist','admin_reset_growth_member','admin_settle_competition','admin_upsert_growth_reward','admin_upsert_video'];
  member_names text[] := ARRAY['check_activity_badges','check_growth_achievements','checkin_competition','close_my_support_ticket','complete_growth_task','create_cash_order','join_competition_waitlist','record_growth_activity','redeem_growth_reward','use_growth_coupon'];
  trigger_names text[] := ARRAY['assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward'];
  internal_names text[] := ARRAY['award_growth_points','refresh_growth_level'];
  helper_names text[] := ARRAY['is_admin','is_admin_user'];
  found integer;
  unexpected_names text[];
  expected_names text[];
BEGIN
  expected_names := admin_names || member_names || trigger_names || internal_names || helper_names || ARRAY['increment_download_count'];

  -- Fail closed if the public SECURITY DEFINER inventory contains any
  -- function outside this reviewed allowlist. The per-name count below also
  -- rejects missing routines and unexpected overloads.
  SELECT array_agg(actual.proname ORDER BY actual.proname)
    INTO unexpected_names
  FROM (
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.prokind = 'f'
    EXCEPT
    SELECT unnest(expected_names)
  ) AS actual;

  IF unexpected_names IS NOT NULL THEN
    RAISE EXCEPTION 'Unexpected public SECURITY DEFINER functions: %',
      array_to_string(unexpected_names, ', ');
  END IF;

  FOREACH nm IN ARRAY expected_names LOOP
    SELECT count(*) INTO found FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prosecdef AND p.proname=nm;
    IF found <> 1 THEN RAISE EXCEPTION 'SECURITY DEFINER inventory mismatch for %: found %',nm,found; END IF;
  END LOOP;
  FOREACH nm IN ARRAY admin_names || member_names LOOP
    FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND p.proname=nm LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, service_role',oid_);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',oid_);
    END LOOP;
  END LOOP;
  FOREACH nm IN ARRAY trigger_names LOOP
    FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND p.proname=nm LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',oid_);
    END LOOP;
  END LOOP;
  FOREACH nm IN ARRAY internal_names LOOP
    FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND p.proname=nm LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',oid_);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres',oid_);
    END LOOP;
  END LOOP;
  FOREACH nm IN ARRAY helper_names LOOP
    FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND p.proname=nm LOOP
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, service_role',oid_);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',oid_);
    END LOOP;
  END LOOP;

  -- Public-facing RLS policies call is_admin() even for anon requests.
  -- The helper returns only a boolean and evaluates auth.uid() as NULL for anon.
  GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
  FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND p.proname='increment_download_count' LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, service_role',oid_);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated',oid_);
  END LOOP;
  FOR oid_ IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef
    AND p.proname = ANY(admin_names || member_names || trigger_names || helper_names || ARRAY['increment_download_count'])
  LOOP
    -- Put pg_temp last: PostgreSQL otherwise searches it before ordinary
    -- schemas for relation/type names inside SECURITY DEFINER functions.
    -- pg_catalog first, followed by the only trusted application schemas.
    -- Internal growth functions are excluded here because migration 001
    -- hardens them before transferring ownership to growth_points_executor.
    EXECUTE format('ALTER FUNCTION %s SET search_path TO pg_catalog, public, auth, pg_temp', oid_);
  END LOOP;
END $acl$;
COMMIT;
