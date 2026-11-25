\set ON_ERROR_STOP on

-- Disposable GoTrue/PostgreSQL integration only.
-- This test makes the legacy migration boundary explicit:
-- migration 1 alone has authenticated direct-write privileges; migration 2
-- must immediately remove them and move writes behind maintenance RPCs.
-- Never use this script against production.

\ir ../../migrations/20261117121103_maintenance_system_initial.sql

DO $legacy_boundary$
DECLARE
  has_legacy_direct_writes boolean;
BEGIN
  has_legacy_direct_writes :=
    pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_events', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_events', 'UPDATE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_private_notes', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_private_notes', 'UPDATE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_scopes', 'INSERT')
    OR pg_catalog.has_table_privilege('authenticated', 'private.maintenance_event_scopes', 'DELETE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_audit_logs', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_idempotency', 'INSERT');

  IF NOT has_legacy_direct_writes THEN
    RAISE EXCEPTION
      'LEGACY_BOUNDARY_CHANGED: initial migration no longer exposes direct authenticated writes; update this boundary test and deployment guidance';
  END IF;

  RAISE NOTICE
    'CONFIRMED: initial migration alone permits direct authenticated writes; do not pause deployment or expose the feature before the least-privilege upgrade completes';
END
$legacy_boundary$;

\ir ../../migrations/20261121140000_maintenance_rpc_least_privilege_upgrade.sql

DO $hardened_boundary$
DECLARE
  table_name text;
  has_direct_writes boolean;
  executor record;
BEGIN
  has_direct_writes :=
    pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_events', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_events', 'UPDATE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_private_notes', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_private_notes', 'UPDATE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_event_scopes', 'INSERT')
    OR pg_catalog.has_table_privilege('authenticated', 'private.maintenance_event_scopes', 'DELETE')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_audit_logs', 'INSERT')
    OR pg_catalog.has_any_column_privilege('authenticated', 'private.maintenance_idempotency', 'INSERT');

  IF has_direct_writes THEN
    RAISE EXCEPTION 'FAIL: authenticated retained direct maintenance-table write privileges after the upgrade';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'maintenance_scopes',
    'maintenance_events',
    'maintenance_event_private_notes',
    'maintenance_event_scopes',
    'maintenance_audit_logs',
    'maintenance_idempotency'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'private'
        AND c.relname = table_name
        AND c.relrowsecurity
        AND c.relforcerowsecurity
    ) THEN
      RAISE EXCEPTION 'FAIL: private.% must have RLS enabled and forced after upgrade', table_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'private'
      AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
      AND p.roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'FAIL: authenticated remains a target of a private maintenance mutation policy';
  END IF;

  SELECT rolcanlogin, rolinherit, rolsuper, rolbypassrls,
         rolcreatedb, rolcreaterole, rolreplication
    INTO executor
    FROM pg_catalog.pg_roles
    WHERE rolname = 'maintenance_rpc_executor';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: maintenance_rpc_executor role is missing';
  END IF;

  IF executor.rolcanlogin
     OR executor.rolinherit
     OR executor.rolsuper
     OR executor.rolbypassrls
     OR executor.rolcreatedb
     OR executor.rolcreaterole
     OR executor.rolreplication THEN
    RAISE EXCEPTION 'FAIL: maintenance_rpc_executor has elevated role attributes';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'maintenance_admin_list',
        'maintenance_event_create',
        'maintenance_event_update',
        'maintenance_event_action'
      )
      AND r.rolname <> 'maintenance_rpc_executor'
  ) THEN
    RAISE EXCEPTION 'FAIL: an administrative maintenance RPC is not owned by the dedicated executor';
  END IF;

  RAISE NOTICE
    'PASS: least-privilege upgrade removed direct authenticated writes, forced RLS, and assigned admin RPC ownership to the constrained executor';
END
$hardened_boundary$;
