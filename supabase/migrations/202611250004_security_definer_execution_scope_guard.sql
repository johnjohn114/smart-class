-- Candidate-only SECURITY DEFINER ACL hardening. Do not apply to production
-- until the live migration baseline and all function call sites are reconciled.
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
  arr text[];
  expected integer;
  found integer;
BEGIN
  FOREACH nm IN ARRAY admin_names || member_names || trigger_names || internal_names || helper_names LOOP
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
END $acl$;
COMMIT;
