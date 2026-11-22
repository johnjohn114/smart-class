-- Verify the single-pass draft was applied by a non-superuser CREATEROLE role.
DO $$
DECLARE
  v_owner text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname='maintenance_deployer' AND rolcanlogin AND rolcreaterole AND NOT rolsuper
  ) THEN
    RAISE EXCEPTION 'FAIL: migration test did not use the intended non-superuser CREATEROLE role';
  END IF;

  IF NOT pg_catalog.pg_has_role('maintenance_deployer','maintenance_rpc_executor','MEMBER')
     OR pg_catalog.pg_has_role('maintenance_deployer','maintenance_rpc_executor','SET')
     OR pg_catalog.pg_has_role('maintenance_deployer','maintenance_rpc_executor','USAGE') THEN
    RAISE EXCEPTION 'FAIL: executor membership must remain non-inheritable and non-settable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted_role ON granted_role.oid=m.roleid
    JOIN pg_catalog.pg_roles member_role ON member_role.oid=m.member
    WHERE granted_role.rolname='maintenance_rpc_executor'
      AND member_role.rolname='maintenance_deployer'
      AND (m.set_option OR m.inherit_option OR m.admin_option)
  ) THEN
    RAISE EXCEPTION 'FAIL: executor membership retains SET, INHERIT or ADMIN option';
  END IF;

  IF pg_catalog.has_schema_privilege('maintenance_rpc_executor','public','CREATE') THEN
    RAISE EXCEPTION 'FAIL: executor retained CREATE on public';
  END IF;
  IF pg_catalog.has_schema_privilege('maintenance_rpc_executor','auth','USAGE') THEN
    RAISE EXCEPTION 'FAIL: executor unexpectedly depends on auth schema access';
  END IF;
  IF NOT pg_catalog.has_schema_privilege('maintenance_rpc_executor','private','USAGE') THEN
    RAISE EXCEPTION 'FAIL: executor lacks private schema USAGE';
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
        AND pg_catalog.pg_get_userbyid(p.proowner)='maintenance_rpc_executor'
    ) THEN
      RAISE EXCEPTION 'FAIL: admin RPC owner mismatch for %', v_owner;
    END IF;
  END LOOP;

  IF NOT pg_catalog.has_function_privilege(
       'maintenance_rpc_executor','private.maintenance_uid()','EXECUTE')
     OR NOT pg_catalog.has_function_privilege(
       'maintenance_rpc_executor','public.is_admin()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: executor lacks required identity/admin helper execution';
  END IF;
END
$$;

SELECT 'PASS: non-superuser CREATEROLE migration owner transfer and privilege cleanup';
