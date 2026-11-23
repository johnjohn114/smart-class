-- Disposable PostgreSQL 17 authorization regression test for App Releases.
-- Run from repository root in a fresh database:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/sql/app-releases-authorization.test.sql
--
-- This test exercises the canonical migration only. It does not connect to or
-- modify the hosted production Supabase project. service_role is intentionally
-- not assigned an access contract here: the canonical migration grants table
-- DML to authenticated only, and any backend service_role use must be audited
-- against actual backend call sites before adding grants.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql STABLE
AS $function$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

CREATE TABLE public.profiles(
  id uuid PRIMARY KEY,
  role text NOT NULL
);
GRANT USAGE ON SCHEMA public, auth TO anon, authenticated, service_role;
GRANT SELECT ON public.profiles TO authenticated;

\ir ../../migrations/202610310001_app_releases.sql

INSERT INTO auth.users(id,email) VALUES
  ('00000000-0000-4000-8000-000000000001','admin@example.test'),
  ('00000000-0000-4000-8000-000000000002','member@example.test');
INSERT INTO public.profiles(id,role) VALUES
  ('00000000-0000-4000-8000-000000000001','admin'),
  ('00000000-0000-4000-8000-000000000002','member');

INSERT INTO public.app_releases(version_code,version_name,release_notes,apk_url,published,created_by)
VALUES
  (100,'1.0.0','公開版本','https://example.test/app-1.apk',true,'00000000-0000-4000-8000-000000000001'),
  (101,'1.0.1','尚未發布','https://example.test/app-2.apk',false,'00000000-0000-4000-8000-000000000001');

-- Table-level ACL assertions: RLS does not replace these checks.
DO $acl$
BEGIN
  IF NOT has_table_privilege('anon','public.app_releases','SELECT') THEN
    RAISE EXCEPTION 'FAIL: anon must have SELECT';
  END IF;
  IF has_table_privilege('anon','public.app_releases','INSERT')
     OR has_table_privilege('anon','public.app_releases','UPDATE')
     OR has_table_privilege('anon','public.app_releases','DELETE')
     OR has_table_privilege('anon','public.app_releases','TRUNCATE') THEN
    RAISE EXCEPTION 'FAIL: anon has an unexpected write/TRUNCATE privilege';
  END IF;
  IF NOT has_table_privilege('authenticated','public.app_releases','SELECT')
     OR NOT has_table_privilege('authenticated','public.app_releases','INSERT')
     OR NOT has_table_privilege('authenticated','public.app_releases','UPDATE')
     OR NOT has_table_privilege('authenticated','public.app_releases','DELETE') THEN
    RAISE EXCEPTION 'FAIL: authenticated is missing a privilege explicitly granted by the canonical migration';
  END IF;
  IF has_table_privilege('authenticated','public.app_releases','TRUNCATE') THEN
    RAISE EXCEPTION 'FAIL: authenticated unexpectedly has TRUNCATE';
  END IF;
END
$acl$;

-- Anonymous users see published rows only and cannot write.
SET ROLE anon;
DO $anon$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.app_releases;
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon should see exactly one published release, saw %', visible_count;
  END IF;
END
$anon$;
RESET ROLE;

-- A normal authenticated member also sees published rows only. Table GRANTs
-- allow DML at the ACL layer, but RLS must reject the member's attempted write.
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $member$
DECLARE visible_count integer; denied boolean := false;
BEGIN
  SELECT count(*) INTO visible_count FROM public.app_releases;
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: ordinary member should see exactly one published release, saw %', visible_count;
  END IF;
  BEGIN
    INSERT INTO public.app_releases(version_code,version_name,release_notes,apk_url,created_by)
    VALUES(102,'1.0.2','member attempt','https://example.test/member.apk',auth.uid());
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    denied := true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: ordinary member unexpectedly inserted a release';
  END IF;
END
$member$;
RESET ROLE;
RESET request.jwt.claim.sub;

-- An administrator can read unpublished rows and perform the intended
-- insert/update/delete operations through the authenticated role.
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $admin$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.app_releases;
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: admin should see both published and unpublished releases, saw %', visible_count;
  END IF;
  INSERT INTO public.app_releases(version_code,version_name,release_notes,apk_url,created_by)
  VALUES(103,'1.0.3','admin insert','https://example.test/admin.apk',auth.uid());
  UPDATE public.app_releases SET release_notes='admin update' WHERE version_code=103;
  IF NOT EXISTS (SELECT 1 FROM public.app_releases WHERE version_code=103 AND release_notes='admin update') THEN
    RAISE EXCEPTION 'FAIL: admin update did not persist';
  END IF;
  DELETE FROM public.app_releases WHERE version_code=103;
  IF EXISTS (SELECT 1 FROM public.app_releases WHERE version_code=103) THEN
    RAISE EXCEPTION 'FAIL: admin delete did not persist';
  END IF;
END
$admin$;
RESET ROLE;
RESET request.jwt.claim.sub;

\echo 'PASS: App Releases table ACL, published-row visibility, member denial, and admin CRUD tests'
