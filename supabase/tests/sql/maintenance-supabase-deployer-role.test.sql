-- Verify the single-pass draft was applied by a non-superuser CREATEROLE role.
DO $$
DECLARE
  v_owner text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname='maintenance_deployer' AND rolcreaterole AND NOT rolsuper
  ) THEN
    RAISE EXCEPTION 'FAIL: migration test did not use the intended non-superuser CREATEROLE role';
  END IF;

  IF pg_catalog.pg_has_role('maintenance_deployer','maintenance_rpc_executor','MEMBER')
     OR pg_catalog.pg_has_role('maintenance_deployer','maintenance_rpc_executor','SET') THEN
    RAISE EXCEPTION 'FAIL: temporary executor role membership was not removed';
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
