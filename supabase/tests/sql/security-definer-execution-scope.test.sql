-- Disposable PostgreSQL ACL regression test. Run as postgres in a fresh database.
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role;
DO $stub$
DECLARE nm text;
 trg text[]:=ARRAY['assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward'];
 alln text[]:=ARRAY['admin_activity_analytics','admin_adjust_growth_points','admin_apply_competition_rewards','admin_cancel_order','admin_complete_order','admin_delete_growth_reward','admin_delete_video','admin_grant_competition_reward','admin_mark_competition_attendance','admin_mark_competition_member_attendance','admin_mark_order_paid','admin_promote_competition_waitlist','admin_reset_growth_member','admin_settle_competition','admin_upsert_growth_reward','admin_upsert_video','check_activity_badges','check_growth_achievements','checkin_competition','close_my_support_ticket','complete_growth_task','create_cash_order','join_competition_waitlist','record_growth_activity','redeem_growth_reward','use_growth_coupon','assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward','award_growth_points','refresh_growth_level','is_admin','is_admin_user','increment_download_count'];
BEGIN
 FOREACH nm IN ARRAY alln LOOP
  IF nm=ANY(trg) THEN EXECUTE format('CREATE FUNCTION public.%I() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $f$ BEGIN RETURN NEW; END $f$',nm);
  ELSE EXECUTE format('CREATE FUNCTION public.%I() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $f$ SELECT true $f$',nm); END IF;
 END LOOP;
END $stub$;
\ir ../../migrations/202611250004_security_definer_execution_scope_guard.sql
DO $check$
DECLARE nm text; oid_ regprocedure;
 adminn text[]:=ARRAY['admin_activity_analytics','admin_adjust_growth_points','admin_apply_competition_rewards','admin_cancel_order','admin_complete_order','admin_delete_growth_reward','admin_delete_video','admin_grant_competition_reward','admin_mark_competition_attendance','admin_mark_competition_member_attendance','admin_mark_order_paid','admin_promote_competition_waitlist','admin_reset_growth_member','admin_settle_competition','admin_upsert_growth_reward','admin_upsert_video'];
 membern text[]:=ARRAY['check_activity_badges','check_growth_achievements','checkin_competition','close_my_support_ticket','complete_growth_task','create_cash_order','join_competition_waitlist','record_growth_activity','redeem_growth_reward','use_growth_coupon'];
 restrictn text[]:=ARRAY['assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward','award_growth_points','refresh_growth_level'];
 helpern text[]:=ARRAY['is_admin','is_admin_user'];
BEGIN
 FOREACH nm IN ARRAY adminn||membern LOOP
  oid_:=to_regprocedure(format('public.%I()',nm));
  IF oid_ IS NULL OR has_function_privilege('anon',oid_,'EXECUTE') OR NOT has_function_privilege('authenticated',oid_,'EXECUTE') THEN RAISE EXCEPTION 'ACL mismatch for %',nm; END IF;
 END LOOP;
 FOREACH nm IN ARRAY restrictn LOOP
  oid_:=to_regprocedure(format('public.%I()',nm));
  IF oid_ IS NULL
     OR has_function_privilege('anon',oid_,'EXECUTE')
     OR has_function_privilege('authenticated',oid_,'EXECUTE')
     OR has_function_privilege('service_role',oid_,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Restricted function exposed to anon/authenticated/service_role: %',nm;
  END IF;
 END LOOP;
 FOREACH nm IN ARRAY adminn||membern||helpern LOOP
  oid_:=to_regprocedure(format('public.%I()',nm));
  IF oid_ IS NULL OR has_function_privilege('service_role',oid_,'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must not directly execute application RPC: %',nm;
  END IF;
 END LOOP;
 FOREACH nm IN ARRAY helpern LOOP
  oid_:=to_regprocedure(format('public.%I()',nm));
  IF oid_ IS NULL OR has_function_privilege('anon',oid_,'EXECUTE') OR NOT has_function_privilege('authenticated',oid_,'EXECUTE') THEN RAISE EXCEPTION 'Helper ACL mismatch: %',nm; END IF;
 END LOOP;
 oid_:=to_regprocedure('public.increment_download_count()');
 IF oid_ IS NULL OR NOT has_function_privilege('anon',oid_,'EXECUTE') OR NOT has_function_privilege('authenticated',oid_,'EXECUTE') THEN RAISE EXCEPTION 'Public counter ACL mismatch'; END IF;
END $check$;
CREATE TABLE public.trigger_probe(id integer);
CREATE TRIGGER trigger_probe_before_insert BEFORE INSERT ON public.trigger_probe FOR EACH ROW EXECUTE FUNCTION public.assign_member_no_and_nickname();
INSERT INTO public.trigger_probe VALUES(1);
SET ROLE anon;
DO $deny$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.assign_member_no_and_nickname(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'anon can directly execute trigger function'; END IF;
END $deny$;
RESET ROLE;
\echo 'PASS: SECURITY DEFINER ACL classes and trigger dispatch'
