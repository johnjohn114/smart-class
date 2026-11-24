\set ON_ERROR_STOP on

-- Disposable PostgreSQL regression test for App Releases anon ACL hardening.
-- Run in a fresh CI database as postgres:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/sql/app-releases-anon-acl.test.sql

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text NOT NULL);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $ SELECT NULL::uuid $;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;


CREATE TABLE public.app_releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_code integer NOT NULL UNIQUE CHECK (version_code > 0),
  version_name text NOT NULL,
  release_notes text NOT NULL DEFAULT '',
  apk_url text NOT NULL,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  created_by uuid REFERENCES auth.users(id)
);

ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can read published app releases"
  ON public.app_releases FOR SELECT TO anon, authenticated
  USING (published = true);
CREATE POLICY "Admins can read all app releases"
  ON public.app_releases FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin'));
CREATE POLICY "Admins can insert app releases"
  ON public.app_releases FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin')
    AND (created_by IS NULL OR created_by=auth.uid()));
CREATE POLICY "Admins can update app releases"
  ON public.app_releases FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin'));
CREATE POLICY "Admins can delete app releases"
  ON public.app_releases FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin'));

-- Reproduce the broad grants observed in production, then retain required read/write access.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.app_releases TO anon, authenticated;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
\ir ../../candidate_sql/app_releases_anon_acl_hardening.sql

DO $acl$
BEGIN
  IF NOT has_table_privilege('anon','public.app_releases','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon lost SELECT required by the public release center';
  END IF;
  IF has_table_privilege('anon','public.app_releases','INSERT')
     OR has_table_privilege('anon','public.app_releases','UPDATE')
     OR has_table_privilege('anon','public.app_releases','DELETE')
     OR has_table_privilege('anon','public.app_releases','TRUNCATE')
     OR has_table_privilege('anon','public.app_releases','REFERENCES')
     OR has_table_privilege('anon','public.app_releases','TRIGGER') THEN
    RAISE EXCEPTION 'FAIL: anon retains an unnecessary App Releases table privilege';
  END IF;
  IF NOT has_table_privilege('authenticated','public.app_releases','SELECT')
     OR NOT has_table_privilege('authenticated','public.app_releases','INSERT')
     OR NOT has_table_privilege('authenticated','public.app_releases','UPDATE')
     OR NOT has_table_privilege('authenticated','public.app_releases','DELETE') THEN
    RAISE EXCEPTION 'FAIL: authenticated admin workflow lost a required table privilege';
  END IF;
END
$acl$;

INSERT INTO public.app_releases(version_code,version_name,apk_url,published)
VALUES (1,'1.0.0','https://example.invalid/app.apk',true),
       (2,'1.0.1','https://example.invalid/draft.apk',false);

SET ROLE anon;
DO $visibility$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.app_releases;
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon must see only published releases, saw %', visible_count;
  END IF;
  BEGIN
    INSERT INTO public.app_releases(version_code,version_name,apk_url)
    VALUES (3,'1.0.2','https://example.invalid/blocked.apk');
    RAISE EXCEPTION 'FAIL: anon unexpectedly inserted an App Release';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$visibility$;
RESET ROLE;

\echo 'PASS: anon retains published-release SELECT only; authenticated admin table grants remain unchanged'
