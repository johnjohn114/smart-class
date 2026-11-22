-- Probe the effective role inside SECURITY DEFINER after the migration was
-- applied by a BYPASSRLS database owner. The function owner must be the
-- pg_database_owner pseudo-role, which itself must not have BYPASSRLS.
CREATE FUNCTION public.maintenance_test_effective_rpc_role()
RETURNS TABLE(effective_role text, effective_bypassrls boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $probe$
  SELECT current_user::text,
         COALESCE((SELECT r.rolbypassrls
                   FROM pg_catalog.pg_roles r
                   WHERE r.rolname = current_user), false)
$probe$;
ALTER FUNCTION public.maintenance_test_effective_rpc_role() OWNER TO pg_database_owner;

DO $$
DECLARE
  v_role text;
  v_bypassrls boolean;
BEGIN
  SELECT effective_role, effective_bypassrls
    INTO v_role, v_bypassrls
    FROM public.maintenance_test_effective_rpc_role();
  IF v_role <> 'pg_database_owner' OR v_bypassrls THEN
    RAISE EXCEPTION 'FAIL: SECURITY DEFINER inherited BYPASSRLS from database owner (role %, bypassrls %)',
      v_role, v_bypassrls;
  END IF;
END
$$;

DROP FUNCTION public.maintenance_test_effective_rpc_role();

-- Verify the single-pass draft uses the built-in database-owner pseudo-role (not a custom executor role).
DO $$
DECLARE
  v_owner text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname='maintenance_deployer'
      AND rolcanlogin AND rolcreaterole AND rolcreatedb
      AND NOT rolsuper AND rolbypassrls
  ) THEN
    RAISE EXCEPTION 'FAIL: migration test did not use a non-superuser CREATEROLE BYPASSRLS database owner';
  END IF;

  IF NOT pg_catalog.pg_has_role('maintenance_deployer','pg_database_owner','SET') THEN
    RAISE EXCEPTION 'FAIL: test migration actor is not the database owner';
  END IF;
  IF pg_catalog.pg_has_role('authenticated','pg_database_owner','MEMBER')
     OR pg_catalog.pg_has_role('anon','pg_database_owner','MEMBER') THEN
    RAISE EXCEPTION 'FAIL: application roles must not be members of pg_database_owner';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='maintenance_rpc_executor'
  ) THEN
    RAISE EXCEPTION 'FAIL: migration must not create a CREATEROLE-managed executor role';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname='pg_database_owner'
      AND (rolcanlogin OR rolsuper OR rolcreaterole OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'FAIL: pg_database_owner has unsafe role attributes';
  END IF;

  IF NOT pg_catalog.has_schema_privilege('pg_database_owner','private','USAGE')
     OR NOT pg_catalog.has_schema_privilege('pg_database_owner','public','CREATE') THEN
    RAISE EXCEPTION 'FAIL: built-in database owner lacks required schema access';
  END IF;
  IF pg_catalog.has_schema_privilege('pg_database_owner','auth','USAGE') THEN
    RAISE EXCEPTION 'FAIL: admin RPC owner unexpectedly depends on auth schema access';
  END IF;

  FOREACH v_owner IN ARRAY ARRAY[
    'maintenance_admin_list(jsonb)',
    'maintenance_event_create(jsonb)',
    'maintenance_event_update(jsonb)',
    'maintenance_event_action(jsonb)'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc p
      WHERE p.oid = pg_catalog.to_regprocedure('public.' || v_owner)
        AND pg_catalog.pg_get_userbyid(p.proowner)='pg_database_owner'
        AND p.prosecdef
    ) THEN
      RAISE EXCEPTION 'FAIL: admin RPC must be SECURITY DEFINER owned by pg_database_owner: %', v_owner;
    END IF;
  END LOOP;

  IF NOT pg_catalog.has_function_privilege(
       'pg_database_owner','private.maintenance_uid()','EXECUTE')
     OR NOT pg_catalog.has_function_privilege(
       'pg_database_owner','public.is_admin()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: built-in admin RPC owner lacks identity/admin helper execution';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_database d
    WHERE d.datname=current_database()
      AND pg_catalog.pg_get_userbyid(d.datdba)='maintenance_deployer'
  ) THEN
    RAISE EXCEPTION 'FAIL: migration actor is not the disposable test database owner';
  END IF;
END
$$;

SELECT 'PASS: built-in pg_database_owner ownership under non-superuser database owner';
