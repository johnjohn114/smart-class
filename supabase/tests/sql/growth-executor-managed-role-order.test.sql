-- PostgreSQL 17 managed-role rehearsal for the growth executor ownership sequence.
-- Disposable database only. This deliberately uses a non-superuser migration role.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='migration_runner') THEN
    CREATE ROLE migration_runner NOLOGIN CREATEROLE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='growth_executor_probe') THEN
    CREATE ROLE growth_executor_probe NOLOGIN BYPASSRLS;
  END IF;
END
$roles$;

CREATE SCHEMA migration_role_probe;
GRANT USAGE, CREATE ON SCHEMA migration_role_probe TO migration_runner, growth_executor_probe;
GRANT growth_executor_probe TO migration_runner WITH ADMIN OPTION, SET TRUE, INHERIT FALSE;

SET ROLE migration_runner;
CREATE FUNCTION migration_role_probe.probe() RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$ SELECT 1 $$;

-- Function replacement must happen while the migration role still owns it.
CREATE OR REPLACE FUNCTION migration_role_probe.probe() RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$ SELECT 2 $$;

ALTER FUNCTION migration_role_probe.probe() OWNER TO growth_executor_probe;
GRANT growth_executor_probe TO migration_runner WITH SET FALSE, INHERIT FALSE;

DO $ownership_check$
DECLARE
  can_replace boolean := true;
BEGIN
  IF (SELECT pg_get_userbyid(proowner) FROM pg_proc
      WHERE oid='migration_role_probe.probe()'::regprocedure) <> 'growth_executor_probe' THEN
    RAISE EXCEPTION 'FAIL: function ownership was not transferred';
  END IF;
  IF (SELECT set_option FROM pg_auth_members
      WHERE roleid='growth_executor_probe'::regrole
        AND member='migration_runner'::regrole) THEN
    RAISE EXCEPTION 'FAIL: migration runner retained SET ROLE after hardening';
  END IF;

  BEGIN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION migration_role_probe.probe() RETURNS integer
      LANGUAGE sql SECURITY DEFINER SET search_path TO 'pg_catalog'
      AS 'SELECT 3'
    $sql$;
  EXCEPTION WHEN insufficient_privilege THEN
    can_replace := false;
  END;

  IF can_replace THEN
    RAISE EXCEPTION 'FAIL: migration runner can still replace executor-owned function after SET was revoked';
  END IF;
END
$ownership_check$;

RESET ROLE;
REVOKE growth_executor_probe FROM migration_runner;
DROP SCHEMA migration_role_probe CASCADE;
DROP ROLE growth_executor_probe;
DROP ROLE migration_runner;

\echo 'PASS: non-superuser migration role can replace before transfer and cannot replace after SET is revoked'
