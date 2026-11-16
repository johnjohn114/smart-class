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

-- Apply the exact draft under test. This runs only in the ephemeral CI database.
\ir ../../sql/maintenance-private-schema-rpc-draft-v0.1.sql

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.maintenance_event_create(jsonb)', 'EXECUTE')
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
BEGIN
  request_payload := jsonb_build_object(
    'title', '  CI isolated maintenance event  ', 
    'message', '  Public maintenance notice  ', 
    'internal_note', '  CI_PRIVATE_NOTE_DO_NOT_EXPOSE  ', 
    'is_global', true,
    'scope_codes', '[]'::jsonb,
    'starts_at', pg_catalog.to_char((pg_catalog.now() - interval '5 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'ends_at', pg_catalog.to_char((pg_catalog.now() + interval '1 hour') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00',
    'status', 'scheduled',
    'reason', '  isolated PostgreSQL integration test  ', 
    'idempotency_key', '00000000-0000-4000-8000-000000000011'
  );
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
END
$$;
RESET ROLE;

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
  IF note_rows <> 1 OR audit_rows <> 1 OR idempotency_rows <> 1 THEN
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
  IF event_rows <> 1 OR audit_rows <> 1 OR idempotency_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: rejected conflict left partial records';
  END IF;
END
$$;
RESET ROLE;

\echo 'PASS: isolated PostgreSQL maintenance RPC/RLS integration checks'
