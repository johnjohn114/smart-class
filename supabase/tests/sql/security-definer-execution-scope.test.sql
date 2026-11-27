-- Disposable PostgreSQL ACL regression test. Run as postgres in a fresh database.
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql STABLE
AS $uid$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$uid$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;
CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text NOT NULL);
DO $stub$
DECLARE nm text;
 trg text[]:=ARRAY['assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward'];
 alln text[]:=ARRAY['admin_activity_analytics','admin_adjust_growth_points','admin_apply_competition_rewards','admin_cancel_order','admin_complete_order','admin_delete_growth_reward','admin_delete_video','admin_grant_competition_reward','admin_mark_competition_attendance','admin_mark_competition_member_attendance','admin_mark_order_paid','admin_promote_competition_waitlist','admin_reset_growth_member','admin_settle_competition','admin_upsert_growth_reward','admin_upsert_video','check_activity_badges','check_growth_achievements','checkin_competition','close_my_support_ticket','complete_growth_task','create_cash_order','join_competition_waitlist','record_growth_activity','redeem_growth_reward','use_growth_coupon','assign_member_no_and_nickname','check_competition_registration_rules','ensure_visitor_profile','growth_registration_reward','growth_result_reward','award_growth_points','refresh_growth_level','is_admin','is_admin_user','increment_download_count'];
BEGIN
 FOREACH nm IN ARRAY alln LOOP
  IF nm=ANY(trg) THEN
   EXECUTE format('CREATE FUNCTION public.%I() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $body$ BEGIN RETURN NEW; END $body$',nm);
  ELSIF nm='is_admin' THEN
   EXECUTE 'CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '''' AS $body$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role=''admin'') $body$';
  ELSE
   EXECUTE format('CREATE FUNCTION public.%I() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $body$ SELECT true $body$',nm);
  END IF;
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
  IF oid_ IS NULL OR NOT has_function_privilege('authenticated',oid_,'EXECUTE') THEN RAISE EXCEPTION 'Helper ACL mismatch: %',nm; END IF;
  IF nm='is_admin' AND NOT has_function_privilege('anon',oid_,'EXECUTE') THEN RAISE EXCEPTION 'anon must execute is_admin for public RLS policies'; END IF;
  IF nm='is_admin_user' AND has_function_privilege('anon',oid_,'EXECUTE') THEN RAISE EXCEPTION 'anon must not execute is_admin_user'; END IF;
 END LOOP;
 oid_:=to_regprocedure('public.increment_download_count()');
 IF oid_ IS NULL OR NOT has_function_privilege('anon',oid_,'EXECUTE') OR NOT has_function_privilege('authenticated',oid_,'EXECUTE') OR has_function_privilege('service_role',oid_,'EXECUTE') THEN RAISE EXCEPTION 'Public counter ACL mismatch'; END IF;
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

-- Reproduce the six production policies that call is_admin() for PUBLIC.
CREATE TABLE public.competitions(id integer PRIMARY KEY, published boolean NOT NULL, published_at timestamptz);
CREATE TABLE public.competition_results(id integer PRIMARY KEY, competition_id integer REFERENCES public.competitions(id), user_id uuid);
CREATE TABLE public.forms(id integer PRIMARY KEY, published boolean NOT NULL);
CREATE TABLE public.form_questions(id integer PRIMARY KEY, form_id integer REFERENCES public.forms(id));
CREATE TABLE public.products(id integer PRIMARY KEY, active boolean NOT NULL);
CREATE TABLE public.quick_links(id integer PRIMARY KEY, label text NOT NULL);

INSERT INTO public.competitions VALUES (1,true,NULL),(2,false,NULL);
INSERT INTO public.competition_results VALUES (1,1,NULL),(2,2,NULL);
INSERT INTO public.forms VALUES (1,true),(2,false);
INSERT INTO public.form_questions VALUES (1,1),(2,2);
INSERT INTO public.products VALUES (1,true),(2,false);
INSERT INTO public.quick_links VALUES (1,'admin-only');

ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quick_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY competition_public_read ON public.competitions FOR SELECT TO PUBLIC
USING (is_admin() OR (published = true AND (published_at IS NULL OR published_at <= now())));
CREATE POLICY competition_result_public_read ON public.competition_results FOR SELECT TO PUBLIC
USING (is_admin() OR user_id = auth.uid() OR EXISTS (
  SELECT 1 FROM public.competitions c
  WHERE c.id = competition_results.competition_id
    AND c.published = true
    AND (c.published_at IS NULL OR c.published_at <= now())
));
CREATE POLICY forms_public_read ON public.forms FOR SELECT TO PUBLIC
USING (published = true OR is_admin());
CREATE POLICY form_questions_public_read ON public.form_questions FOR SELECT TO PUBLIC
USING (EXISTS (
  SELECT 1 FROM public.forms f
  WHERE f.id = form_questions.form_id AND (f.published = true OR is_admin())
));
CREATE POLICY product_public_read ON public.products FOR SELECT TO PUBLIC
USING (is_admin() OR active = true);
CREATE POLICY quick_links_admin_all ON public.quick_links FOR ALL TO PUBLIC
USING (is_admin()) WITH CHECK (is_admin());

GRANT SELECT ON public.competitions, public.competition_results, public.forms,
  public.form_questions, public.products, public.quick_links TO anon;

SET ROLE anon;
DO $anonymous_rls$
DECLARE n integer;
BEGIN
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Anonymous is_admin() must return false';
  END IF;
  SELECT count(*) INTO n FROM public.competitions;
  IF n <> 1 THEN RAISE EXCEPTION 'Anonymous competition visibility expected 1 row, got %',n; END IF;
  SELECT count(*) INTO n FROM public.competition_results;
  IF n <> 1 THEN RAISE EXCEPTION 'Anonymous competition result visibility expected 1 row, got %',n; END IF;
  SELECT count(*) INTO n FROM public.forms;
  IF n <> 1 THEN RAISE EXCEPTION 'Anonymous form visibility expected 1 row, got %',n; END IF;
  SELECT count(*) INTO n FROM public.form_questions;
  IF n <> 1 THEN RAISE EXCEPTION 'Anonymous form question visibility expected 1 row, got %',n; END IF;
  SELECT count(*) INTO n FROM public.products;
  IF n <> 1 THEN RAISE EXCEPTION 'Anonymous product visibility expected 1 row, got %',n; END IF;
  SELECT count(*) INTO n FROM public.quick_links;
  IF n <> 0 THEN RAISE EXCEPTION 'Anonymous quick_links visibility expected 0 rows, got %',n; END IF;
  BEGIN
    INSERT INTO public.quick_links(id,label) VALUES (2,'anonymous-write');
    RAISE EXCEPTION 'Anonymous unexpectedly inserted an admin quick link';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$anonymous_rls$;
RESET ROLE;

\echo 'PASS: SECURITY DEFINER ACL classes, trigger dispatch, and anonymous public RLS'
