\set ON_ERROR_STOP on

-- Isolated PostgreSQL-only harness. This is NOT a Supabase JWT/PostgREST test.
-- The auth.uid() and public.is_admin() functions below are test stubs only.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'authenticator';
GRANT anon, authenticated TO authenticator;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb->>'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), '')
  ), '')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

CREATE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    COALESCE(
      NULLIF(current_setting('request.jwt.claims', true), '')::jsonb->>'sub',
      NULLIF(current_setting('request.jwt.claim.sub', true), '')
    ) = '00000000-0000-4000-8000-000000000001',
    false
  )
$$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Apply the single-pass development draft under test. This runs only in the ephemeral CI database.
\ir ../../sql/maintenance-private-schema-rpc-draft-v0.1.sql

DO $$
BEGIN
  IF has_function_privilege('anon', 'pg_temp.maintenance_test_create(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.maintenance_event_update(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.maintenance_event_action(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.maintenance_admin_list(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon has an administrative RPC EXECUTE privilege';
  END IF;
  IF NOT has_function_privilege('anon', 'public.maintenance_status_public(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon cannot execute the public status RPC';
  END IF;
END
$$;

-- The admin RPC owner is non-login, non-superuser, and cannot bypass RLS.
DO $$
DECLARE
  executor record;
  table_name text;
  column_name text;
  function_name text;
BEGIN
  SELECT rolcanlogin, rolinherit, rolsuper, rolbypassrls, rolcreatedb, rolcreaterole, rolreplication
    INTO executor FROM pg_catalog.pg_roles WHERE rolname='maintenance_rpc_executor';
  IF executor.rolcanlogin OR executor.rolinherit OR executor.rolsuper OR executor.rolbypassrls
     OR executor.rolcreatedb OR executor.rolcreaterole OR executor.rolreplication THEN
    RAISE EXCEPTION 'FAIL: maintenance RPC executor has elevated role attributes';
  END IF;
  IF pg_catalog.has_schema_privilege('maintenance_rpc_executor','public','CREATE') THEN
    RAISE EXCEPTION 'FAIL: maintenance RPC executor retained CREATE on public schema';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'maintenance_scopes','maintenance_events','maintenance_event_private_notes',
    'maintenance_event_scopes','maintenance_audit_logs','maintenance_idempotency'
  ] LOOP
    IF pg_catalog.has_table_privilege('authenticated','private.'||table_name,'INSERT')
       OR pg_catalog.has_table_privilege('authenticated','private.'||table_name,'UPDATE')
       OR pg_catalog.has_table_privilege('authenticated','private.'||table_name,'DELETE')
       OR pg_catalog.has_table_privilege('authenticated','private.'||table_name,'TRUNCATE') THEN
      RAISE EXCEPTION 'FAIL: authenticated has direct write privilege on %', table_name;
    END IF;
    -- Table-level privilege checks do not replace checking every column grant.
    FOR column_name IN
      SELECT a.attname
      FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private' AND c.relname=table_name
        AND a.attnum>0 AND NOT a.attisdropped
    LOOP
      IF pg_catalog.has_column_privilege('authenticated','private.'||table_name,column_name,'INSERT')
         OR pg_catalog.has_column_privilege('authenticated','private.'||table_name,column_name,'UPDATE') THEN
        RAISE EXCEPTION 'FAIL: authenticated has direct column write privilege on %.%', table_name, column_name;
      END IF;
    END LOOP;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='private' AND c.relname=table_name
        AND c.relrowsecurity AND c.relforcerowsecurity
        AND c.relowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='maintenance_rpc_executor')
    ) THEN
      RAISE EXCEPTION 'FAIL: table % must FORCE RLS and not be owned by executor', table_name;
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    'maintenance_admin_list','maintenance_event_create',
    'maintenance_event_update','maintenance_event_action'
  ] LOOP
    IF (SELECT r.rolname
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
        WHERE n.nspname='public' AND p.proname=function_name) <> 'maintenance_rpc_executor' THEN
      RAISE EXCEPTION 'FAIL: admin RPC % is not owned by dedicated executor', function_name;
    END IF;
  END LOOP;
END
$$;


-- Test-only helper: mirror the public lifecycle by creating a draft first and
-- scheduling it through the action RPC when the fixture requests scheduled.
CREATE FUNCTION pg_temp.maintenance_test_create(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $
DECLARE
  v_request jsonb := p_request;
  v_created jsonb;
  v_event_id uuid;
BEGIN
  IF p_request->>'status' = 'scheduled' THEN
    v_request := pg_catalog.jsonb_set(v_request, '{status}', '"draft"'::jsonb, false);
  END IF;
  v_created := public.maintenance_event_create(v_request);
  IF p_request->>'status' = 'scheduled' THEN
    v_event_id := (v_created #>> '{data,event_id}')::uuid;
    RETURN public.maintenance_event_action(pg_catalog.jsonb_build_object(
      'event_id', v_event_id,
      'expected_version', 1,
      'action', 'schedule',
      'reason', 'isolated test fixture schedule',
      'idempotency_key', pg_catalog.gen_random_uuid()
    ));
  END IF;
  RETURN v_created;
END
$;

-- Only this isolated harness may backdate an event after exercising the
-- real schedule transition, so completion-after-end can be tested safely.
CREATE FUNCTION pg_temp.maintenance_test_mark_ended(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $
BEGIN
  UPDATE private.maintenance_events
     SET starts_at = pg_catalog.now() - interval '30 minutes',
         ends_at = pg_catalog.now() - interval '10 minutes'
   WHERE id = p_event_id;
END
$;

-- Anonymous caller can read the public status function, but no maintenance is active yet.
SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', false);
DO $$
DECLARE
  result jsonb;
BEGIN
  result := public.maintenance_status_public('{}'::jsonb);
  IF (result #>> '{data,is_maintenance}')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: initial public status should be inactive';
  END IF;
END
$$;
RESET ROLE;

-- Create one active global event as the test admin. The same idempotency request
-- must return the original response and must not create a duplicate row.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $$
DECLARE
  request_payload jsonb;
  first_result jsonb;
  replay_result jsonb;
  conflict_seen boolean := false;
  invalid_scope_seen boolean := false;
  invalid_scope_payload jsonb;
BEGIN
  request_payload := jsonb_build_object(
    'title', '  CI isolated maintenance event  ', 
    'message', '  Public maintenance notice  ', 
    'internal_note', '  CI_PRIVATE_NOTE_DO_NOT_EXPOSE  ', 
    'is_global', true,
    'scope_codes', '[]'::jsonb,
    'starts_at', pg_catalog.to_char((pg_catalog.now() + interval '2 seconds') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '1 hour') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'status', 'draft',
    'reason', '  isolated PostgreSQL integration test  ', 
    'idempotency_key', '00000000-0000-4000-8000-000000000011'
  );
  -- JSON arrays must contain strings only; numeric values must not be coerced to text.
  invalid_scope_payload := pg_catalog.jsonb_set(request_payload, '{scope_codes}', '[1]'::jsonb, false);
  invalid_scope_payload := pg_catalog.jsonb_set(invalid_scope_payload, '{idempotency_key}',
    pg_catalog.to_jsonb('00000000-0000-4000-8000-000000000012'::text), false);
  BEGIN
    PERFORM public.maintenance_event_create(invalid_scope_payload);
  EXCEPTION WHEN SQLSTATE '22023' THEN
    invalid_scope_seen := true;
  END;
  IF NOT invalid_scope_seen THEN
    RAISE EXCEPTION 'FAIL: non-string scope_codes array element was accepted';
  END IF;

  first_result := public.maintenance_event_create(request_payload);
  -- Equivalent semantic payload: trimmed text and UTC Z timestamps instead of +00:00.
  request_payload := pg_catalog.jsonb_set(request_payload, '{title}', pg_catalog.to_jsonb('CI isolated maintenance event'::text), false);
  request_payload := pg_catalog.jsonb_set(request_payload, '{message}', pg_catalog.to_jsonb('Public maintenance notice'::text), false);
  request_payload := pg_catalog.jsonb_set(request_payload, '{internal_note}', pg_catalog.to_jsonb('CI_PRIVATE_NOTE_DO_NOT_EXPOSE'::text), false);
  request_payload := pg_catalog.jsonb_set(request_payload, '{reason}', pg_catalog.to_jsonb('isolated PostgreSQL integration test'::text), false);
  request_payload := pg_catalog.jsonb_set(request_payload, '{starts_at}',
    pg_catalog.to_jsonb(pg_catalog.to_char((pg_catalog.now() - interval '5 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || 'Z'), false);
  request_payload := pg_catalog.jsonb_set(request_payload, '{ends_at}',
    pg_catalog.to_jsonb(pg_catalog.to_char((pg_catalog.now() + interval '1 hour') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || 'Z'), false);
  replay_result := public.maintenance_event_create(request_payload);
  IF first_result IS DISTINCT FROM replay_result THEN
    RAISE EXCEPTION 'FAIL: idempotent replay did not return the original response';
  END IF;

  request_payload := pg_catalog.jsonb_set(
    request_payload, '{title}', pg_catalog.to_jsonb('Changed title'::text), false
  );
  BEGIN
    PERFORM public.maintenance_event_create(request_payload);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    conflict_seen := SQLERRM = 'IDEMPOTENCY_KEY_REUSED';
  END;
  IF NOT conflict_seen THEN
    RAISE EXCEPTION 'FAIL: same idempotency key with different payload was accepted';
  END IF;

  PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id', (first_result #>> '{data,event_id}')::uuid,
    'expected_version', 1,
    'action', 'schedule',
    'reason', 'activate initial public status fixture',
    'idempotency_key', '00000000-0000-4000-8000-000000000099'
  ));
END
$;
RESET ROLE;
SELECT pg_catalog.pg_sleep(2.5);

-- Anonymous public visibility is limited to the active event. The private note
-- table is not readable by anon, and the RPC response must not contain the note.
SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', false);
DO $$
DECLARE
  result jsonb;
  visible_events integer;
BEGIN
  result := public.maintenance_status_public('{}'::jsonb);
  IF (result #>> '{data,is_maintenance}')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: active event was not visible through public status RPC';
  END IF;
  IF result::text LIKE '%CI_PRIVATE_NOTE_DO_NOT_EXPOSE%' THEN
    RAISE EXCEPTION 'FAIL: public status RPC exposed an internal note';
  END IF;
  SELECT count(*) INTO visible_events FROM private.maintenance_events;
  IF visible_events <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon RLS should expose exactly one active event row';
  END IF;
  BEGIN
    PERFORM internal_note FROM private.maintenance_event_private_notes;
    RAISE EXCEPTION 'FAIL: anon unexpectedly read private notes';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$$;
RESET ROLE;

-- Authenticated non-admin can use public status but cannot read admin-only rows
-- or execute an administrative RPC.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', false);
SET ROLE authenticated;
DO $$
DECLARE
  note_rows integer;
  audit_rows integer;
  idempotency_rows integer;
BEGIN
  SELECT count(*) INTO note_rows FROM private.maintenance_event_private_notes;
  SELECT count(*) INTO audit_rows FROM private.maintenance_audit_logs;
  SELECT count(*) INTO idempotency_rows FROM private.maintenance_idempotency;
  IF note_rows <> 0 OR audit_rows <> 0 OR idempotency_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: non-admin RLS exposed admin-only records';
  END IF;
  BEGIN
    PERFORM public.maintenance_admin_list('{}'::jsonb);
    RAISE EXCEPTION 'FAIL: non-admin unexpectedly executed maintenance_admin_list';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$$;
RESET ROLE;

-- Admin can read the private note and audit/idempotency records. Audit rows
-- remain protected against ordinary UPDATE/DELETE by grants and triggers.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $$
DECLARE
  note_rows integer;
  audit_rows integer;
  idempotency_rows integer;
BEGIN
  SELECT count(*) INTO note_rows FROM private.maintenance_event_private_notes
   WHERE internal_note = 'CI_PRIVATE_NOTE_DO_NOT_EXPOSE';
  SELECT count(*) INTO audit_rows FROM private.maintenance_audit_logs;
  SELECT count(*) INTO idempotency_rows FROM private.maintenance_idempotency;
  IF note_rows <> 1 OR audit_rows <> 2 OR idempotency_rows <> 2 THEN
    RAISE EXCEPTION 'FAIL: admin could not read expected private/audit/idempotency records';
  END IF;
  BEGIN
    UPDATE private.maintenance_audit_logs SET reason = 'tampered';
    RAISE EXCEPTION 'FAIL: admin unexpectedly updated audit rows';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$$;
RESET ROLE;

-- A conflicting scheduled event must fail atomically: no second event,
-- audit row, or idempotency row may remain.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $$
DECLARE
  request_payload jsonb;
  event_rows integer;
  audit_rows integer;
  idempotency_rows integer;
BEGIN
  request_payload := jsonb_build_object(
    'title', 'Conflicting event',
    'message', 'This must be rejected',
    'is_global', true,
    'scope_codes', '[]'::jsonb,
    'starts_at', pg_catalog.to_char(pg_catalog.now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '30 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'status', 'scheduled',
    'reason', 'conflict integration test',
    'idempotency_key', '00000000-0000-4000-8000-000000000012'
  );
  BEGIN
    PERFORM public.maintenance_event_create(request_payload);
    RAISE EXCEPTION 'FAIL: conflicting schedule was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  SELECT count(*) INTO event_rows FROM private.maintenance_events;
  SELECT count(*) INTO audit_rows FROM private.maintenance_audit_logs;
  SELECT count(*) INTO idempotency_rows FROM private.maintenance_idempotency;
  IF event_rows <> 1 OR audit_rows <> 2 OR idempotency_rows <> 2 THEN
    RAISE EXCEPTION 'FAIL: rejected conflict left partial records';
  END IF;
END
$$;
RESET ROLE;

-- Verify an active global event conflicts with every one of the seven local scopes.
-- This catches the case where global maintenance accidentally leaves a region available.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $scope_matrix$
DECLARE
  scope_code text;
  request_payload jsonb;
  conflict_seen boolean;
  scope_codes text[] := ARRAY[
    'site_core',
    'announcements_info',
    'events_competitions',
    'video_content',
    'membership_growth',
    'store_support',
    'downloads_app'
  ];
BEGIN
  FOREACH scope_code IN ARRAY scope_codes LOOP
    request_payload := pg_catalog.jsonb_build_object(
      'title', 'Global overlap test ' || scope_code,
      'message', 'Must conflict with active global event',
      'is_global', false,
      'scope_codes', pg_catalog.jsonb_build_array(scope_code),
      'starts_at', pg_catalog.to_char((pg_catalog.now() + interval '10 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
      'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '20 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
      'status', 'scheduled',
      'reason', 'global scope matrix integration test',
      'idempotency_key', pg_catalog.gen_random_uuid()::text
    );
    conflict_seen := false;
    BEGIN
      PERFORM public.maintenance_event_create(request_payload);
    EXCEPTION WHEN unique_violation THEN
      conflict_seen := true;
    END;
    IF NOT conflict_seen THEN
      RAISE EXCEPTION 'FAIL: active global event did not block scope %', scope_code;
    END IF;
  END LOOP;
END
$scope_matrix$;
RESET ROLE;

-- Verify public status resolves the active global event for every supported scope.
SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', false);
DO $scope_status$
DECLARE
  scope_code text;
  result jsonb;
  scope_codes text[] := ARRAY[
    'site_core',
    'announcements_info',
    'events_competitions',
    'video_content',
    'membership_growth',
    'store_support',
    'downloads_app'
  ];
BEGIN
  FOREACH scope_code IN ARRAY scope_codes LOOP
    result := public.maintenance_status_public(
      pg_catalog.jsonb_build_object('scope', scope_code)
    );
    IF (result #>> '{data,is_maintenance}')::boolean IS DISTINCT FROM true
       OR (result #>> '{data,is_global}')::boolean IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'FAIL: public status did not report global maintenance for scope %', scope_code;
    END IF;
  END LOOP;
END
$scope_status$;
RESET ROLE;

-- Replace the global event with one local event, then prove that only
-- its selected scope is in maintenance and the other six remain available.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $local_scope_admin$
DECLARE
  global_event_id uuid;
  global_version bigint;
  local_result jsonb;
  local_event_id uuid;
  local_version bigint;
  disjoint_result jsonb;
  disjoint_event_id uuid;
  disjoint_version bigint;
  conflict_seen boolean := false;
BEGIN
  SELECT id, version INTO STRICT global_event_id, global_version
    FROM private.maintenance_events
   WHERE is_global = true AND status = 'scheduled';

  PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id', global_event_id,
    'expected_version', global_version,
    'action', 'cancel',
    'reason', 'replace global event with local scope test',
    'idempotency_key', '00000000-0000-4000-8000-000000000021'
  ));

  local_result := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title', 'Local scope isolation test',
    'message', 'Only announcements_info is under maintenance',
    'is_global', false,
    'scope_codes', pg_catalog.jsonb_build_array('announcements_info'),
    'starts_at', pg_catalog.to_char((pg_catalog.now() - interval '5 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '30 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'status', 'scheduled',
    'reason', 'local scope isolation integration test',
    'idempotency_key', '00000000-0000-4000-8000-000000000022'
  ));
  IF (local_result #>> '{data,status}') IS DISTINCT FROM 'scheduled' THEN
    RAISE EXCEPTION 'FAIL: local maintenance event was not scheduled';
  END IF;
  local_event_id := (local_result #>> '{data,event_id}')::uuid;
  local_version := (local_result #>> '{data,version}')::bigint;

  -- A second overlapping event for the same local scope must be rejected.
  BEGIN
    PERFORM public.maintenance_event_create(pg_catalog.jsonb_build_object(
      'title', 'Same scope conflict test',
      'message', 'This overlapping event must be rejected',
      'is_global', false,
      'scope_codes', pg_catalog.jsonb_build_array('announcements_info'),
      'starts_at', pg_catalog.to_char((pg_catalog.now() - interval '4 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
      'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '20 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
      'status', 'scheduled',
      'reason', 'same scope conflict integration test',
      'idempotency_key', '00000000-0000-4000-8000-000000000023'
    ));
  EXCEPTION WHEN unique_violation THEN
    conflict_seen := true;
  END;
  IF NOT conflict_seen THEN
    RAISE EXCEPTION 'FAIL: overlapping event in the same local scope was accepted';
  END IF;

  -- A different local scope may be scheduled at the same time.
  disjoint_result := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title', 'Disjoint scope coexistence test',
    'message', 'A different local scope may be scheduled concurrently',
    'is_global', false,
    'scope_codes', pg_catalog.jsonb_build_array('downloads_app'),
    'starts_at', pg_catalog.to_char((pg_catalog.now() - interval '3 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '15 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'status', 'scheduled',
    'reason', 'disjoint scope coexistence integration test',
    'idempotency_key', '00000000-0000-4000-8000-000000000024'
  ));
  IF (disjoint_result #>> '{data,status}') IS DISTINCT FROM 'scheduled' THEN
    RAISE EXCEPTION 'FAIL: disjoint local scope was not scheduled';
  END IF;
  disjoint_event_id := (disjoint_result #>> '{data,event_id}')::uuid;
  disjoint_version := (disjoint_result #>> '{data,version}')::bigint;

  PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id', disjoint_event_id,
    'expected_version', disjoint_version,
    'action', 'cancel',
    'reason', 'cleanup disjoint scope coexistence test',
    'idempotency_key', '00000000-0000-4000-8000-000000000025'
  ));
END
$local_scope_admin$;
RESET ROLE;

SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', false);
DO $local_scope_matrix$
DECLARE
  scope_code text;
  result jsonb;
  expected_active boolean;
  scope_codes text[] := ARRAY[
    'site_core',
    'announcements_info',
    'events_competitions',
    'video_content',
    'membership_growth',
    'store_support',
    'downloads_app'
  ];
BEGIN
  FOREACH scope_code IN ARRAY scope_codes LOOP
    result := public.maintenance_status_public(
      pg_catalog.jsonb_build_object('scope', scope_code)
    );
    expected_active := scope_code = 'announcements_info';
    IF (result #>> '{data,is_maintenance}')::boolean IS DISTINCT FROM expected_active
       OR (result #>> '{data,is_global}')::boolean IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'FAIL: local maintenance leaked to scope %; expected active=%',
        scope_code, expected_active;
    END IF;
  END LOOP;
END
$local_scope_matrix$;
RESET ROLE;

-- Lifecycle regression matrix: draft -> scheduled -> completed,
-- draft/scheduled -> cancelled, invalid transitions, versioning, and replay.
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);
SET ROLE authenticated;
DO $lifecycle_matrix$
DECLARE
  complete_create jsonb;
  complete_schedule jsonb;
  complete_replay jsonb;
  cancel_draft_create jsonb;
  cancel_draft_action jsonb;
  cancel_scheduled_create jsonb;
  cancel_scheduled_action jsonb;
  past_draft_create jsonb;
  event_id uuid;
  event_version bigint;
  event_status text;
  audit_before integer;
  audit_after integer;
  idempotency_before integer;
  idempotency_after integer;
  invalid_seen boolean;
BEGIN
  SELECT count(*) INTO audit_before FROM private.maintenance_audit_logs;
  SELECT count(*) INTO idempotency_before FROM private.maintenance_idempotency;

  -- Create an already-ended scheduled fixture so the completion guard is tested.
  complete_create := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title','Lifecycle complete path',
    'message','Synthetic lifecycle integration test',
    'is_global',false,
    'scope_codes',pg_catalog.jsonb_build_array('membership_growth'),
    'starts_at',pg_catalog.to_char((pg_catalog.now()+interval '2 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'ends_at',pg_catalog.to_char((pg_catalog.now()+interval '3 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'status','draft',
    'reason','create completion lifecycle draft fixture',
    'idempotency_key','00000000-0000-4000-8000-000000000031'
  ));
  event_id := (complete_create #>> '{data,event_id}')::uuid;
  PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id', event_id, 'expected_version', 1, 'action', 'schedule',
    'reason', 'schedule completion fixture',
    'idempotency_key', '00000000-0000-4000-8000-000000000044'
  ));
  PERFORM pg_temp.maintenance_test_mark_ended(event_id);
  event_version := 2;
  IF (complete_create #>> '{data,status}') IS DISTINCT FROM 'draft' OR event_version<>2 THEN
    RAISE EXCEPTION 'FAIL: completion fixture setup returned unexpected state/version';
  END IF;

  -- The fixture was scheduled through the lifecycle RPC and then ended by the test harness.

  invalid_seen := false;
  BEGIN
    PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
      'event_id',event_id,'expected_version',2,'action','schedule',
      'reason','repeat schedule must fail',
      'idempotency_key','00000000-0000-4000-8000-000000000033'
    ));
  EXCEPTION WHEN SQLSTATE '22023' THEN
    invalid_seen := true;
  END;
  IF NOT invalid_seen THEN
    RAISE EXCEPTION 'FAIL: scheduling an already scheduled event was accepted';
  END IF;

  complete_schedule := public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id',event_id,'expected_version',2,'action','complete',
    'reason','complete expired lifecycle test',
    'idempotency_key','00000000-0000-4000-8000-000000000034'
  ));
  IF (complete_schedule #>> '{data,status}') IS DISTINCT FROM 'completed'
     OR (complete_schedule #>> '{data,version}')::bigint<>3 THEN
    RAISE EXCEPTION 'FAIL: scheduled -> completed transition/version incorrect';
  END IF;

  invalid_seen := false;
  BEGIN
    PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
      'event_id',event_id,'expected_version',3,'action','cancel',
      'reason','completed event cannot be cancelled',
      'idempotency_key','00000000-0000-4000-8000-000000000035'
    ));
  EXCEPTION WHEN SQLSTATE '22023' THEN
    invalid_seen := true;
  END;
  IF NOT invalid_seen THEN
    RAISE EXCEPTION 'FAIL: completed event was allowed to transition to cancelled';
  END IF;

  -- Draft cancellation is allowed.
  cancel_draft_create := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title','Lifecycle cancel draft',
    'message','Synthetic lifecycle integration test',
    'is_global',false,
    'scope_codes',pg_catalog.jsonb_build_array('store_support'),
    'starts_at',pg_catalog.to_char((pg_catalog.now()+interval '2 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'ends_at',pg_catalog.to_char((pg_catalog.now()+interval '3 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'status','draft',
    'reason','create draft cancellation test',
    'idempotency_key','00000000-0000-4000-8000-000000000036'
  ));
  event_id := (cancel_draft_create #>> '{data,event_id}')::uuid;
  cancel_draft_action := public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id',event_id,'expected_version',1,'action','cancel',
    'reason','cancel draft lifecycle test',
    'idempotency_key','00000000-0000-4000-8000-000000000037'
  ));
  IF (cancel_draft_action #>> '{data,status}') IS DISTINCT FROM 'cancelled'
     OR (cancel_draft_action #>> '{data,version}')::bigint<>2 THEN
    RAISE EXCEPTION 'FAIL: draft -> cancelled transition/version incorrect';
  END IF;

  -- Scheduled cancellation is allowed, but completion before ends_at is not.
  cancel_scheduled_create := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title','Lifecycle cancel scheduled',
    'message','Synthetic lifecycle integration test',
    'is_global',false,
    'scope_codes',pg_catalog.jsonb_build_array('video_content'),
    'starts_at',pg_catalog.to_char((pg_catalog.now()+interval '2 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'ends_at',pg_catalog.to_char((pg_catalog.now()+interval '3 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'status','draft',
    'reason','create scheduled cancellation test',
    'idempotency_key','00000000-0000-4000-8000-000000000038'
  ));
  event_id := (cancel_scheduled_create #>> '{data,event_id}')::uuid;
  PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id',event_id,'expected_version',1,'action','schedule',
    'reason','schedule future cancellation test',
    'idempotency_key','00000000-0000-4000-8000-000000000039'
  ));

  invalid_seen := false;
  BEGIN
    PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
      'event_id',event_id,'expected_version',2,'action','complete',
      'reason','premature completion must fail',
      'idempotency_key','00000000-0000-4000-8000-000000000040'
    ));
  EXCEPTION WHEN SQLSTATE '22023' THEN
    invalid_seen := true;
  END;
  IF NOT invalid_seen THEN
    RAISE EXCEPTION 'FAIL: scheduled event completed before ends_at';
  END IF;

  cancel_scheduled_action := public.maintenance_event_action(pg_catalog.jsonb_build_object(
    'event_id',event_id,'expected_version',2,'action','cancel',
    'reason','cancel scheduled lifecycle test',
    'idempotency_key','00000000-0000-4000-8000-000000000041'
  ));
  IF (cancel_scheduled_action #>> '{data,status}') IS DISTINCT FROM 'cancelled'
     OR (cancel_scheduled_action #>> '{data,version}')::bigint<>3 THEN
    RAISE EXCEPTION 'FAIL: scheduled -> cancelled transition/version incorrect';
  END IF;

  -- An expired draft must not be scheduled, even by calling the RPC directly.
  past_draft_create := public.maintenance_event_create(pg_catalog.jsonb_build_object(
    'title','Lifecycle reject past schedule',
    'message','Synthetic lifecycle integration test',
    'is_global',false,
    'scope_codes',pg_catalog.jsonb_build_array('membership_growth'),
    'starts_at',pg_catalog.to_char((pg_catalog.now()-interval '30 minutes') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'ends_at',pg_catalog.to_char((pg_catalog.now()+interval '30 minutes') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS')||'+00:00',
    'status','draft',
    'reason','create past draft scheduling rejection test',
    'idempotency_key','00000000-0000-4000-8000-000000000042'
  ));
  event_id := (past_draft_create #>> '{data,event_id}')::uuid;
  invalid_seen := false;
  BEGIN
    PERFORM public.maintenance_event_action(pg_catalog.jsonb_build_object(
      'event_id',event_id,'expected_version',1,'action','schedule',
      'reason','past schedule must fail',
      'idempotency_key','00000000-0000-4000-8000-000000000043'
    ));
  EXCEPTION WHEN SQLSTATE '22023' THEN
    invalid_seen := true;
  END;
  IF NOT invalid_seen THEN
    RAISE EXCEPTION 'FAIL: an expired draft was allowed to be scheduled';
  END IF;
  SELECT status,version INTO event_status,event_version
    FROM private.maintenance_events WHERE id=event_id;
  IF event_status IS DISTINCT FROM 'draft' OR event_version<>1 THEN
    RAISE EXCEPTION 'FAIL: rejected past schedule changed event state or version';
  END IF;

  SELECT count(*) INTO audit_after FROM private.maintenance_audit_logs;
  SELECT count(*) INTO idempotency_after FROM private.maintenance_idempotency;
  IF audit_after-audit_before<>8 OR idempotency_after-idempotency_before<>8 THEN
    RAISE EXCEPTION 'FAIL: lifecycle success audit/idempotency counts incorrect (audit %, idempotency %)',
      audit_after-audit_before,idempotency_after-idempotency_before;
  END IF;

  SELECT status,version INTO event_status,event_version
    FROM private.maintenance_events
   WHERE id=(cancel_scheduled_create #>> '{data,event_id}')::uuid;
  IF event_status IS DISTINCT FROM 'cancelled' OR event_version<>3 THEN
    RAISE EXCEPTION 'FAIL: persisted lifecycle final state/version incorrect';
  END IF;
END
$lifecycle_matrix$;
RESET ROLE;

\echo 'PASS: isolated PostgreSQL maintenance RPC/RLS integration checks'
