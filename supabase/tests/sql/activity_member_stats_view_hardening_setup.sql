-- Disposable PostgreSQL fixture for activity_member_stats security integration tests.
-- Synthetic data only. Never run against production.
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated,service_role;
-- Reproduce the broad production default ACL so the regression test proves
-- both candidate views explicitly remove inherited non-SELECT privileges.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
CREATE TABLE public.profiles(id uuid PRIMARY KEY,nickname text,role text NOT NULL DEFAULT 'visitor');
CREATE TABLE public.competition_attendance(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,user_id uuid NOT NULL REFERENCES public.profiles(id),status text NOT NULL,points_awarded integer NOT NULL DEFAULT 0,completion_points_awarded integer NOT NULL DEFAULT 0);
INSERT INTO public.profiles VALUES
('00000000-0000-0000-0000-000000000001','Synthetic Member A','visitor'),
('00000000-0000-0000-0000-000000000002',NULL,'visitor'),
('00000000-0000-0000-0000-000000000099','Synthetic Admin','admin');
INSERT INTO public.competition_attendance(user_id,status,points_awarded,completion_points_awarded) VALUES
('00000000-0000-0000-0000-000000000001','checked_in',10,5),
('00000000-0000-0000-0000-000000000001','late',2,3),
('00000000-0000-0000-0000-000000000002','no_show',0,0),
('00000000-0000-0000-0000-000000000002','checked_in',7,1);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competition_attendance ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin')
$$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
CREATE POLICY profiles_self_or_admin_select ON public.profiles FOR SELECT TO authenticated
USING (id=auth.uid() OR public.is_admin());
CREATE POLICY attendance_self_or_admin_select ON public.competition_attendance FOR SELECT TO authenticated
USING (user_id=auth.uid() OR public.is_admin());
GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role;
GRANT SELECT ON public.profiles,public.competition_attendance TO authenticated,service_role;
-- Match the live unnecessary anonymous source-table grants identified in PR #26.
GRANT ALL PRIVILEGES ON TABLE public.competition_attendance TO anon;
CREATE VIEW public.activity_member_stats AS
SELECT a.user_id,max(coalesce(p.nickname,a.user_id::text)) AS nickname,
count(*) FILTER (WHERE a.status=ANY(ARRAY['checked_in'::text,'late'::text]))::integer AS attended_count,
count(*) FILTER (WHERE a.status='late'::text)::integer AS late_count,
count(*) FILTER (WHERE a.status='no_show'::text)::integer AS no_show_count,
coalesce(sum(a.points_awarded),0::bigint)::integer AS checkin_points,
coalesce(sum(a.completion_points_awarded),0::bigint)::integer AS completion_points,
(coalesce(sum(a.points_awarded),0::bigint)+coalesce(sum(a.completion_points_awarded),0::bigint))::integer AS activity_points
FROM public.competition_attendance a LEFT JOIN public.profiles p ON p.id=a.user_id GROUP BY a.user_id;
GRANT SELECT ON public.activity_member_stats TO anon,authenticated,service_role;
