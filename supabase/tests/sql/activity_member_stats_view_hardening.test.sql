-- Combined security + RLS + output regression assertions.
-- Run only in a disposable database after setup and candidate SQL.
DO $$
DECLARE opts text[]; n integer; a integer; l integer; ns integer; cp integer; xp integer; total integer;
BEGIN
 SELECT reloptions INTO opts FROM pg_class WHERE oid='public.activity_member_stats'::regclass;
 IF NOT coalesce(opts @> ARRAY['security_invoker=true'],false) THEN RAISE EXCEPTION 'security_invoker=true required'; END IF;
 IF has_table_privilege('anon','public.activity_member_stats','SELECT') THEN RAISE EXCEPTION 'anon must not SELECT the view'; END IF;
 IF NOT has_table_privilege('authenticated','public.activity_member_stats','SELECT') THEN RAISE EXCEPTION 'authenticated SELECT missing'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.profiles'::regclass)
 OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.competition_attendance'::regclass) THEN RAISE EXCEPTION 'source table RLS disabled'; END IF;
 IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='activity_member_stats')<>8 THEN RAISE EXCEPTION 'view output columns changed'; END IF;
END $$;
SET ROLE anon;
DO $$ BEGIN
 BEGIN EXECUTE 'SELECT count(*) FROM public.activity_member_stats'; RAISE EXCEPTION 'anonymous SELECT unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);
DO $$
DECLARE n integer; a integer; l integer; ns integer; cp integer; xp integer; total integer;
BEGIN
 SELECT count(*) INTO n FROM public.activity_member_stats;
 IF n<>1 THEN RAISE EXCEPTION 'member should see one row, got %',n; END IF;
 SELECT attended_count,late_count,no_show_count,checkin_points,completion_points,activity_points
 INTO a,l,ns,cp,xp,total FROM public.activity_member_stats
 WHERE user_id='00000000-0000-0000-0000-000000000001';
 IF (a,l,ns,cp,xp,total) IS DISTINCT FROM (2,1,0,12,8,20)
 THEN RAISE EXCEPTION 'member aggregate mismatch: %, %, %, %, %, %',a,l,ns,cp,xp,total; END IF;
 IF EXISTS(SELECT 1 FROM public.activity_member_stats WHERE user_id<>'00000000-0000-0000-0000-000000000001')
 THEN RAISE EXCEPTION 'member sees another member aggregate'; END IF;
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',false);
-- Admin status is derived from the synthetic profiles.role via is_admin().
DO $$
DECLARE n integer; a integer; l integer; ns integer; cp integer; xp integer; total integer;
BEGIN
 SELECT count(*) INTO n FROM public.activity_member_stats;
 IF n<>2 THEN RAISE EXCEPTION 'admin should see two rows, got %',n; END IF;
 SELECT sum(attended_count),sum(late_count),sum(no_show_count),sum(checkin_points),sum(completion_points),sum(activity_points)
 INTO a,l,ns,cp,xp,total FROM public.activity_member_stats;
 IF (a,l,ns,cp,xp,total) IS DISTINCT FROM (3,1,1,19,9,28)
 THEN RAISE EXCEPTION 'admin totals mismatch: %, %, %, %, %, %',a,l,ns,cp,xp,total; END IF;
END $$;
RESET ROLE;
-- Public leaderboard contract: anonymous access is intentional, but only the
-- five presentation fields are exposed; no account UUID or private totals.
DO $
DECLARE n integer; a integer; l integer; ns integer; total integer;
BEGIN
 IF NOT has_table_privilege('anon','public.activity_public_leaderboard','SELECT')
 THEN RAISE EXCEPTION 'anonymous leaderboard SELECT missing'; END IF;
 IF (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='public' AND table_name='activity_public_leaderboard')<>5
 THEN RAISE EXCEPTION 'public leaderboard must expose exactly five columns'; END IF;
 IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='activity_public_leaderboard'
              AND column_name IN ('user_id','checkin_points','completion_points'))
 THEN RAISE EXCEPTION 'public leaderboard exposes a private/internal column'; END IF;
END $;
SET ROLE anon;
DO $
DECLARE n integer; a integer; l integer; ns integer; total integer;
BEGIN
 SELECT count(*),sum(attended_count),sum(late_count),sum(no_show_count),sum(activity_points)
 INTO n,a,l,ns,total FROM public.activity_public_leaderboard;
 IF (n,a,l,ns,total) IS DISTINCT FROM (2,3,1,1,28)
 THEN RAISE EXCEPTION 'public leaderboard output mismatch: %, %, %, %, %',n,a,l,ns,total; END IF;
END $;
RESET ROLE;
SELECT 'activity_member_stats and public leaderboard integration tests passed' AS result;
