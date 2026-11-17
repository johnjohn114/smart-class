-- Ephemeral CI bootstrap for a real GoTrue-issued JWT integration test.
-- This file is only run against the disposable GitHub Actions PostgreSQL service.
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'authenticator';
  END IF;
END
$$;

ALTER ROLE authenticator LOGIN NOINHERIT PASSWORD 'authenticator';
GRANT anon, authenticated TO authenticator;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;

-- Supabase-compatible UID helper: PostgREST sets request.jwt.claims from the
-- verified JWT. GoTrue itself issues the JWT; this helper only reads its sub.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb->>'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), '')
  ), '')::uuid
$$;
REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin', 'visitor'))
);

-- Mirror the production helper's essential behavior: admin status is read
-- from profiles for the authenticated auth.uid(), never from client input.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.profiles AS p
     WHERE p.id = auth.uid()
       AND p.role = 'admin'
  )
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

INSERT INTO public.profiles (id, role)
VALUES (:'admin_id'::uuid, 'admin'), (:'member_id'::uuid, 'visitor')
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role;
