-- Maintenance private schema + RPC draft v0.1
-- DEVELOPMENT DRAFT ONLY. DO NOT RUN AGAINST PRODUCTION.
-- Architecture: user JWT + SECURITY INVOKER + RLS. No service_role impersonation.
-- Preconditions: public.is_admin() exists and is callable by authenticated users.
-- This file is intentionally not stored under supabase/migrations/.

DO $preflight$
BEGIN
  IF pg_catalog.to_regprocedure('public.is_admin()') IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION_FAILED: public.is_admin() is required';
  END IF;
  IF pg_catalog.to_regclass('private.maintenance_scopes') IS NOT NULL
     OR pg_catalog.to_regclass('private.maintenance_events') IS NOT NULL
     OR pg_catalog.to_regclass('private.maintenance_event_scopes') IS NOT NULL
     OR pg_catalog.to_regclass('private.maintenance_audit_logs') IS NOT NULL
     OR pg_catalog.to_regclass('private.maintenance_idempotency') IS NOT NULL THEN
    RAISE EXCEPTION 'PRECONDITION_FAILED: maintenance objects already exist; reconcile before applying';
  END IF;
END
$preflight$;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO anon, authenticated;

CREATE TABLE private.maintenance_scopes (
  code text PRIMARY KEY,
  label text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL,
  CONSTRAINT maintenance_scopes_code_check CHECK (
    code IN ('site_core','announcements_info','events_competitions',
             'video_content','membership_growth','store_support','downloads_app')
  )
);

INSERT INTO private.maintenance_scopes(code,label,enabled,sort_order) VALUES
 ('site_core','網站核心',true,1),
 ('announcements_info','公告與資訊',true,2),
 ('events_competitions','活動與比賽',true,3),
 ('video_content','影音內容',true,4),
 ('membership_growth','會員與成長',true,5),
 ('store_support','商城與客服',true,6),
 ('downloads_app','下載與 App',true,7);

CREATE TABLE private.maintenance_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  title text NOT NULL CHECK (pg_catalog.char_length(title) BETWEEN 1 AND 200),
  message text NOT NULL CHECK (pg_catalog.char_length(message) BETWEEN 1 AND 4000),
  internal_note text CHECK (internal_note IS NULL OR pg_catalog.char_length(internal_note) <= 4000),
  is_global boolean NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','scheduled','cancelled','completed')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT maintenance_events_time_check CHECK (starts_at < ends_at)
);

CREATE TABLE private.maintenance_event_scopes (
  event_id uuid NOT NULL REFERENCES private.maintenance_events(id) ON DELETE RESTRICT,
  scope_code text NOT NULL REFERENCES private.maintenance_scopes(code) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY(event_id, scope_code)
);

CREATE TABLE private.maintenance_audit_logs (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES private.maintenance_events(id) ON DELETE RESTRICT,
  admin_id uuid NOT NULL DEFAULT auth.uid(),
  action text NOT NULL,
  reason text NOT NULL CHECK (pg_catalog.char_length(reason) BETWEEN 1 AND 500),
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE private.maintenance_idempotency (
  actor_id uuid NOT NULL DEFAULT auth.uid(),
  idempotency_key uuid NOT NULL,
  request_payload jsonb NOT NULL,
  response_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  PRIMARY KEY(actor_id, idempotency_key)
);

CREATE INDEX maintenance_events_status_schedule_idx
  ON private.maintenance_events(status, starts_at, ends_at);
CREATE INDEX maintenance_events_created_idx
  ON private.maintenance_events(created_at DESC, id DESC);
CREATE INDEX maintenance_event_scopes_scope_idx
  ON private.maintenance_event_scopes(scope_code, event_id);
CREATE INDEX maintenance_audit_logs_event_created_idx
  ON private.maintenance_audit_logs(event_id, created_at DESC);

ALTER TABLE private.maintenance_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_event_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_idempotency ENABLE ROW LEVEL SECURITY;

CREATE POLICY maintenance_scopes_public_enabled_select
  ON private.maintenance_scopes FOR SELECT TO anon, authenticated
  USING (enabled = true);
CREATE POLICY maintenance_scopes_admin_select
  ON private.maintenance_scopes FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin());

CREATE POLICY maintenance_events_public_active_select
  ON private.maintenance_events FOR SELECT TO anon, authenticated
  USING (status = 'scheduled' AND starts_at <= pg_catalog.now() AND ends_at > pg_catalog.now());
CREATE POLICY maintenance_events_admin_select
  ON private.maintenance_events FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin());
CREATE POLICY maintenance_events_admin_insert
  ON private.maintenance_events FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND public.is_admin() AND created_by = auth.uid());
CREATE POLICY maintenance_events_admin_update
  ON private.maintenance_events FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin())
  WITH CHECK (auth.uid() IS NOT NULL AND public.is_admin());

CREATE POLICY maintenance_event_scopes_public_select
  ON private.maintenance_event_scopes FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM private.maintenance_events e
    WHERE e.id = event_id AND e.status = 'scheduled'
      AND e.starts_at <= pg_catalog.now() AND e.ends_at > pg_catalog.now()
  ));
CREATE POLICY maintenance_event_scopes_admin_select
  ON private.maintenance_event_scopes FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin());
CREATE POLICY maintenance_event_scopes_admin_insert
  ON private.maintenance_event_scopes FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND public.is_admin());
CREATE POLICY maintenance_event_scopes_admin_delete
  ON private.maintenance_event_scopes FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin());

CREATE POLICY maintenance_audit_admin_select
  ON private.maintenance_audit_logs FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND public.is_admin());
CREATE POLICY maintenance_audit_admin_insert
  ON private.maintenance_audit_logs FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND public.is_admin() AND admin_id = auth.uid());

CREATE POLICY maintenance_idempotency_admin_select
  ON private.maintenance_idempotency FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND actor_id = auth.uid() AND public.is_admin());
CREATE POLICY maintenance_idempotency_admin_insert
  ON private.maintenance_idempotency FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND actor_id = auth.uid() AND public.is_admin());

-- Column-level grants keep anon from reading private notes and actor/audit data.
-- IMPORTANT: authenticated needs SELECT on the event table for the SECURITY INVOKER admin-list RPC.
-- RLS is row-based and cannot hide internal_note by column for non-admin authenticated users.
-- Therefore private MUST remain excluded from Data API Exposed schemas; the public RPCs are the only app entry points.
GRANT SELECT (code,label,enabled,sort_order) ON private.maintenance_scopes TO anon, authenticated;
GRANT SELECT (id,title,message,is_global,status,starts_at,ends_at)
  ON private.maintenance_events TO anon;
GRANT SELECT (event_id,scope_code) ON private.maintenance_event_scopes TO anon;

GRANT SELECT ON private.maintenance_events, private.maintenance_event_scopes,
  private.maintenance_scopes TO authenticated;
GRANT INSERT (title,message,internal_note,is_global,status,starts_at,ends_at)
  ON private.maintenance_events TO authenticated;
GRANT UPDATE (title,message,internal_note,is_global,status,starts_at,ends_at,version,updated_at)
  ON private.maintenance_events TO authenticated;
GRANT INSERT (event_id,scope_code), DELETE ON private.maintenance_event_scopes TO authenticated;
GRANT SELECT ON private.maintenance_audit_logs TO authenticated;
GRANT INSERT (event_id,action,reason,before_data,after_data)
  ON private.maintenance_audit_logs TO authenticated;
GRANT SELECT ON private.maintenance_idempotency TO authenticated;
GRANT INSERT (idempotency_key,request_payload,response_json)
  ON private.maintenance_idempotency TO authenticated;

CREATE FUNCTION private.maintenance_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER maintenance_events_set_updated_at
BEFORE UPDATE ON private.maintenance_events
FOR EACH ROW EXECUTE FUNCTION private.maintenance_set_updated_at();

CREATE FUNCTION private.maintenance_reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUDIT_IMMUTABLE';
END;
$$;

CREATE TRIGGER maintenance_audit_no_row_mutation
BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs
FOR EACH ROW EXECUTE FUNCTION private.maintenance_reject_audit_mutation();
CREATE TRIGGER maintenance_audit_no_truncate
BEFORE TRUNCATE ON private.maintenance_audit_logs
FOR EACH STATEMENT EXECUTE FUNCTION private.maintenance_reject_audit_mutation();

REVOKE ALL ON FUNCTION private.maintenance_set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.maintenance_reject_audit_mutation() FROM PUBLIC, anon, authenticated;

-- Public status: anon reads only current active public fields; admin bypass is informational only.
CREATE FUNCTION public.maintenance_status_public(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_scope text;
  v_is_admin boolean := false;
  v_event record;
BEGIN
  IF p_request IS NULL OR pg_catalog.jsonb_typeof(p_request) <> 'object'
     OR (p_request - ARRAY['scope']) <> '{}'::jsonb THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'VALIDATION_ERROR';
  END IF;

  v_scope := p_request->>'scope';
  IF v_scope IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM private.maintenance_scopes s WHERE s.code = v_scope AND s.enabled
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'VALIDATION_ERROR';
  END IF;

  IF auth.uid() IS NOT NULL THEN
    v_is_admin := public.is_admin();
  END IF;

  SELECT e.id, e.title, e.message, e.is_global, e.starts_at, e.ends_at,
         COALESCE(
           (SELECT pg_catalog.jsonb_agg(es.scope_code ORDER BY es.scope_code)
            FROM private.maintenance_event_scopes es WHERE es.event_id = e.id),
           '[]'::jsonb
         ) AS scopes
    INTO v_event
    FROM private.maintenance_events e
   WHERE e.status = 'scheduled'
     AND e.starts_at <= pg_catalog.now()
     AND e.ends_at > pg_catalog.now()
     AND (e.is_global OR (v_scope IS NOT NULL AND EXISTS (
       SELECT 1 FROM private.maintenance_event_scopes es
       WHERE es.event_id = e.id AND es.scope_code = v_scope
     )))
   ORDER BY e.is_global DESC
   LIMIT 1;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'data', pg_catalog.jsonb_build_object(
      'is_maintenance', v_event.id IS NOT NULL,
      'is_global', COALESCE(v_event.is_global, false),
      'scopes', COALESCE(v_event.scopes, '[]'::jsonb),
      'title', v_event.title,
      'message', v_event.message,
      'starts_at', v_event.starts_at,
      'ends_at', v_event.ends_at,
      'server_time', pg_catalog.now(),
      'admin_bypass', v_is_admin
    )
  );
END;
$$;

-- Admin event list with stable keyset pagination.
CREATE FUNCTION public.maintenance_admin_list(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_limit integer := COALESCE((p_request->>'limit')::integer, 20);
  v_cursor_text text;
  v_cursor_created timestamptz;
  v_cursor_id uuid;
  v_row record;
  v_count integer := 0;
  v_events jsonb := '[]'::jsonb;
  v_last_created timestamptz;
  v_last_id uuid;
  v_has_more boolean := false;
  v_next_cursor text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FORBIDDEN';
  END IF;
  IF p_request IS NULL OR pg_catalog.jsonb_typeof(p_request) <> 'object'
     OR (p_request - ARRAY['status','scope','is_global','from','to','limit','cursor']) <> '{}'::jsonb
     OR v_limit < 1 OR v_limit > 100 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  IF p_request ? 'status' AND p_request->>'status' NOT IN ('draft','scheduled','cancelled','completed') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  IF p_request ? 'is_global' AND pg_catalog.jsonb_typeof(p_request->'is_global') <> 'boolean' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  IF p_request ? 'cursor' THEN
    v_cursor_text := pg_catalog.convert_from(pg_catalog.decode(p_request->>'cursor','base64'),'UTF8');
    v_cursor_created := pg_catalog.split_part(v_cursor_text,'|',1)::timestamptz;
    v_cursor_id := pg_catalog.split_part(v_cursor_text,'|',2)::uuid;
  END IF;

  FOR v_row IN
    SELECT e.id,e.title,e.message,e.internal_note,e.is_global,e.status,e.starts_at,e.ends_at,
           e.version,e.created_at,e.updated_at,
           COALESCE((SELECT pg_catalog.jsonb_agg(es.scope_code ORDER BY es.scope_code)
                     FROM private.maintenance_event_scopes es WHERE es.event_id=e.id),'[]'::jsonb) AS scopes
      FROM private.maintenance_events e
     WHERE (NOT (p_request ? 'status') OR e.status=p_request->>'status')
       AND (NOT (p_request ? 'is_global') OR e.is_global=(p_request->>'is_global')::boolean)
       AND (NOT (p_request ? 'from') OR e.starts_at >= (p_request->>'from')::timestamptz)
       AND (NOT (p_request ? 'to') OR e.starts_at < (p_request->>'to')::timestamptz)
       AND (NOT (p_request ? 'scope') OR EXISTS (
         SELECT 1 FROM private.maintenance_event_scopes f
          WHERE f.event_id=e.id AND f.scope_code=p_request->>'scope'
       ))
       AND (v_cursor_created IS NULL OR (e.created_at,e.id) < (v_cursor_created,v_cursor_id))
     ORDER BY e.created_at DESC,e.id DESC
     LIMIT v_limit + 1
  LOOP
    v_count := v_count + 1;
    IF v_count > v_limit THEN
      v_has_more := true;
      EXIT;
    END IF;
    v_events := v_events || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'id',v_row.id,'title',v_row.title,'message',v_row.message,
      'internal_note',v_row.internal_note,'is_global',v_row.is_global,
      'status',v_row.status,'starts_at',v_row.starts_at,'ends_at',v_row.ends_at,
      'version',v_row.version,'created_at',v_row.created_at,'updated_at',v_row.updated_at,
      'scopes',v_row.scopes
    ));
    v_last_created := v_row.created_at;
    v_last_id := v_row.id;
  END LOOP;

  IF v_has_more THEN
    v_next_cursor := pg_catalog.encode(
      pg_catalog.convert_to(v_last_created::text || '|' || v_last_id::text,'UTF8'),'base64'
    );
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,'data',
    pg_catalog.jsonb_build_object('events',v_events,'next_cursor',v_next_cursor));
END;
$$;

-- Create event: all writes, audit and idempotency are atomic in this function call.
CREATE FUNCTION public.maintenance_event_create(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_key uuid;
  v_payload jsonb;
  v_old_payload jsonb;
  v_old_response jsonb;
  v_title text;
  v_message text;
  v_note text;
  v_reason text;
  v_global boolean;
  v_status text;
  v_start timestamptz;
  v_end timestamptz;
  v_codes text[];
  v_code_count integer;
  v_event private.maintenance_events%ROWTYPE;
  v_response jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN';
  END IF;
  IF p_request IS NULL OR pg_catalog.jsonb_typeof(p_request)<>'object'
     OR (p_request - ARRAY['title','message','internal_note','is_global','scope_codes',
                           'starts_at','ends_at','status','reason','idempotency_key']) <> '{}'::jsonb THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  IF pg_catalog.jsonb_typeof(p_request->'is_global')<>'boolean'
     OR pg_catalog.jsonb_typeof(p_request->'scope_codes')<>'array' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  v_title := pg_catalog.btrim(p_request->>'title');
  v_message := pg_catalog.btrim(p_request->>'message');
  v_note := p_request->>'internal_note';
  v_reason := pg_catalog.btrim(p_request->>'reason');
  v_global := (p_request->>'is_global')::boolean;
  v_status := p_request->>'status';
  v_start := (p_request->>'starts_at')::timestamptz;
  v_end := (p_request->>'ends_at')::timestamptz;
  v_key := (p_request->>'idempotency_key')::uuid;
  IF v_key IS NULL OR v_title IS NULL OR v_title='' OR pg_catalog.char_length(v_title)>200
     OR v_message IS NULL OR v_message='' OR pg_catalog.char_length(v_message)>4000
     OR (v_note IS NOT NULL AND pg_catalog.char_length(v_note)>4000)
     OR v_reason IS NULL OR v_reason='' OR pg_catalog.char_length(v_reason)>500
     OR v_start IS NULL OR v_end IS NULL OR v_start>=v_end
     OR v_status IS NULL OR v_status NOT IN ('draft','scheduled') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  SELECT COALESCE(pg_catalog.array_agg(DISTINCT x ORDER BY x),ARRAY[]::text[])
    INTO v_codes FROM pg_catalog.jsonb_array_elements_text(p_request->'scope_codes') x;
  SELECT pg_catalog.count(*) INTO v_code_count FROM private.maintenance_scopes s
   WHERE s.code=ANY(v_codes) AND s.enabled;
  IF v_code_count<>pg_catalog.cardinality(v_codes)
     OR (v_global AND pg_catalog.cardinality(v_codes)<>0)
     OR (NOT v_global AND pg_catalog.cardinality(v_codes)=0) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(20261108,1);
  v_payload := p_request || pg_catalog.jsonb_build_object('_operation','create');
  SELECT request_payload,response_json INTO v_old_payload,v_old_response
    FROM private.maintenance_idempotency
   WHERE actor_id=v_actor AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old_payload<>v_payload THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN v_old_response;
  END IF;

  IF v_status='scheduled' AND EXISTS (
    SELECT 1 FROM private.maintenance_events e
     WHERE e.status='scheduled' AND e.starts_at<v_end AND v_start<e.ends_at
       AND (v_global OR e.is_global OR EXISTS (
         SELECT 1 FROM private.maintenance_event_scopes es
          WHERE es.event_id=e.id AND es.scope_code=ANY(v_codes)
       ))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='CONFLICT';
  END IF;

  INSERT INTO private.maintenance_events(title,message,internal_note,is_global,status,starts_at,ends_at)
  VALUES(v_title,v_message,v_note,v_global,v_status,v_start,v_end)
  RETURNING * INTO v_event;
  IF pg_catalog.cardinality(v_codes)>0 THEN
    INSERT INTO private.maintenance_event_scopes(event_id,scope_code)
    SELECT v_event.id,x FROM pg_catalog.unnest(v_codes) x;
  END IF;
  v_response := pg_catalog.jsonb_build_object('ok',true,'data',
    pg_catalog.jsonb_build_object('event_id',v_event.id,'version',v_event.version,
      'status',v_event.status,'title',v_event.title));
  INSERT INTO private.maintenance_audit_logs(event_id,action,reason,before_data,after_data)
  VALUES(v_event.id,'create',v_reason,NULL,
    pg_catalog.to_jsonb(v_event) || pg_catalog.jsonb_build_object('scope_codes',v_codes));
  INSERT INTO private.maintenance_idempotency(idempotency_key,request_payload,response_json)
  VALUES(v_key,v_payload,v_response);
  RETURN v_response;
END;
$$;

-- Update event: merges partial input against the stored row before validating final state.
CREATE FUNCTION public.maintenance_event_update(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_key uuid;
  v_payload jsonb;
  v_old_payload jsonb;
  v_old_response jsonb;
  v_event private.maintenance_events%ROWTYPE;
  v_title text;
  v_message text;
  v_note text;
  v_reason text;
  v_global boolean;
  v_start timestamptz;
  v_end timestamptz;
  v_codes text[];
  v_code_count integer;
  v_schedule_changed boolean;
  v_before_data jsonb;
  v_after_data jsonb;
  v_response jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN';
  END IF;
  IF p_request IS NULL OR pg_catalog.jsonb_typeof(p_request)<>'object'
     OR (p_request - ARRAY['event_id','expected_version','reason','idempotency_key',
       'title','message','internal_note','is_global','scope_codes','starts_at','ends_at']) <> '{}'::jsonb
     OR NOT (p_request ?| ARRAY['title','message','internal_note','is_global','scope_codes','starts_at','ends_at']) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  v_key := (p_request->>'idempotency_key')::uuid;
  v_reason := pg_catalog.btrim(p_request->>'reason');
  IF v_key IS NULL OR p_request->>'event_id' IS NULL OR p_request->>'expected_version' IS NULL
     OR v_reason IS NULL OR v_reason='' OR pg_catalog.char_length(v_reason)>500
     OR (p_request->>'expected_version')::bigint<1 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(20261108,1);
  v_payload := p_request || pg_catalog.jsonb_build_object('_operation','update');
  SELECT request_payload,response_json INTO v_old_payload,v_old_response
    FROM private.maintenance_idempotency WHERE actor_id=v_actor AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old_payload<>v_payload THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN v_old_response;
  END IF;

  SELECT * INTO v_event FROM private.maintenance_events
   WHERE id=(p_request->>'event_id')::uuid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='NOT_FOUND'; END IF;
  IF v_event.version<>(p_request->>'expected_version')::bigint THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='VERSION_CONFLICT';
  END IF;
  IF v_event.status IN ('cancelled','completed') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;

  IF (p_request ? 'is_global' AND pg_catalog.jsonb_typeof(p_request->'is_global')<>'boolean')
     OR (p_request ? 'scope_codes' AND pg_catalog.jsonb_typeof(p_request->'scope_codes')<>'array')
     OR (p_request ? 'starts_at' AND p_request->>'starts_at' IS NULL)
     OR (p_request ? 'ends_at' AND p_request->>'ends_at' IS NULL)
     OR (p_request ? 'title' AND p_request->>'title' IS NULL)
     OR (p_request ? 'message' AND p_request->>'message' IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  v_title := CASE WHEN p_request ? 'title' THEN pg_catalog.btrim(p_request->>'title') ELSE v_event.title END;
  v_message := CASE WHEN p_request ? 'message' THEN pg_catalog.btrim(p_request->>'message') ELSE v_event.message END;
  v_note := CASE WHEN p_request ? 'internal_note' THEN p_request->>'internal_note' ELSE v_event.internal_note END;
  v_global := CASE WHEN p_request ? 'is_global' THEN (p_request->>'is_global')::boolean ELSE v_event.is_global END;
  v_start := CASE WHEN p_request ? 'starts_at' THEN (p_request->>'starts_at')::timestamptz ELSE v_event.starts_at END;
  v_end := CASE WHEN p_request ? 'ends_at' THEN (p_request->>'ends_at')::timestamptz ELSE v_event.ends_at END;
  SELECT COALESCE(pg_catalog.array_agg(es.scope_code ORDER BY es.scope_code),ARRAY[]::text[])
    INTO v_codes FROM private.maintenance_event_scopes es WHERE es.event_id=v_event.id;
  IF p_request ? 'scope_codes' THEN
    IF pg_catalog.jsonb_typeof(p_request->'scope_codes')<>'array' THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
    END IF;
    SELECT COALESCE(pg_catalog.array_agg(DISTINCT x ORDER BY x),ARRAY[]::text[])
      INTO v_codes FROM pg_catalog.jsonb_array_elements_text(p_request->'scope_codes') x;
  END IF;
  SELECT pg_catalog.count(*) INTO v_code_count FROM private.maintenance_scopes s
   WHERE s.code=ANY(v_codes) AND s.enabled;
  IF v_title IS NULL OR v_title='' OR pg_catalog.char_length(v_title)>200
     OR v_message IS NULL OR v_message='' OR pg_catalog.char_length(v_message)>4000
     OR (v_note IS NOT NULL AND pg_catalog.char_length(v_note)>4000)
     OR v_start>=v_end OR v_code_count<>pg_catalog.cardinality(v_codes)
     OR (v_global AND pg_catalog.cardinality(v_codes)<>0)
     OR (NOT v_global AND pg_catalog.cardinality(v_codes)=0) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  v_before_data := pg_catalog.to_jsonb(v_event) || pg_catalog.jsonb_build_object('scope_codes',
    COALESCE((SELECT pg_catalog.jsonb_agg(es.scope_code ORDER BY es.scope_code)
              FROM private.maintenance_event_scopes es WHERE es.event_id=v_event.id),'[]'::jsonb));
  v_schedule_changed := p_request ?| ARRAY['is_global','scope_codes','starts_at','ends_at'];
  IF v_event.status='scheduled' AND v_event.starts_at<=pg_catalog.now() AND v_schedule_changed THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  IF v_event.status='scheduled' AND EXISTS (
    SELECT 1 FROM private.maintenance_events e
     WHERE e.id<>v_event.id AND e.status='scheduled'
       AND e.starts_at<v_end AND v_start<e.ends_at
       AND (v_global OR e.is_global OR EXISTS (
         SELECT 1 FROM private.maintenance_event_scopes es
          WHERE es.event_id=e.id AND es.scope_code=ANY(v_codes)
       ))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='CONFLICT';
  END IF;

  UPDATE private.maintenance_events
     SET title=v_title,message=v_message,internal_note=v_note,is_global=v_global,
         starts_at=v_start,ends_at=v_end,version=version+1
   WHERE id=v_event.id RETURNING * INTO v_event;
  IF p_request ? 'scope_codes' THEN
    DELETE FROM private.maintenance_event_scopes WHERE event_id=v_event.id;
    IF pg_catalog.cardinality(v_codes)>0 THEN
      INSERT INTO private.maintenance_event_scopes(event_id,scope_code)
      SELECT v_event.id,x FROM pg_catalog.unnest(v_codes) x;
    END IF;
  END IF;
  v_after_data := pg_catalog.to_jsonb(v_event) || pg_catalog.jsonb_build_object('scope_codes',v_codes);
  v_response := pg_catalog.jsonb_build_object('ok',true,'data',
    pg_catalog.jsonb_build_object('event_id',v_event.id,'version',v_event.version,
      'status',v_event.status,'title',v_event.title));
  INSERT INTO private.maintenance_audit_logs(event_id,action,reason,before_data,after_data)
  VALUES(v_event.id,'update',v_reason,v_before_data,v_after_data);
  INSERT INTO private.maintenance_idempotency(idempotency_key,request_payload,response_json)
  VALUES(v_key,v_payload,v_response);
  RETURN v_response;
END;
$$;

-- Lifecycle action: schedule, cancel, complete.
CREATE FUNCTION public.maintenance_event_action(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_key uuid;
  v_payload jsonb;
  v_old_payload jsonb;
  v_old_response jsonb;
  v_event private.maintenance_events%ROWTYPE;
  v_reason text;
  v_action text;
  v_response jsonb;
  v_codes text[];
  v_before_data jsonb;
  v_after_data jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN';
  END IF;
  IF p_request IS NULL OR pg_catalog.jsonb_typeof(p_request)<>'object'
     OR (p_request - ARRAY['event_id','expected_version','action','reason','idempotency_key']) <> '{}'::jsonb THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;
  v_key := (p_request->>'idempotency_key')::uuid;
  v_reason := pg_catalog.btrim(p_request->>'reason');
  v_action := p_request->>'action';
  IF v_key IS NULL OR p_request->>'event_id' IS NULL OR p_request->>'expected_version' IS NULL
     OR v_reason IS NULL OR v_reason='' OR pg_catalog.char_length(v_reason)>500
     OR (p_request->>'expected_version')::bigint<1
     OR v_action IS NULL OR v_action NOT IN ('schedule','cancel','complete') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(20261108,1);
  v_payload := p_request || pg_catalog.jsonb_build_object('_operation','action');
  SELECT request_payload,response_json INTO v_old_payload,v_old_response
    FROM private.maintenance_idempotency WHERE actor_id=v_actor AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old_payload<>v_payload THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN v_old_response;
  END IF;

  SELECT * INTO v_event FROM private.maintenance_events
   WHERE id=(p_request->>'event_id')::uuid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='NOT_FOUND'; END IF;
  IF v_event.version<>(p_request->>'expected_version')::bigint THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='VERSION_CONFLICT';
  END IF;
  SELECT COALESCE(pg_catalog.array_agg(es.scope_code ORDER BY es.scope_code),ARRAY[]::text[])
    INTO v_codes FROM private.maintenance_event_scopes es WHERE es.event_id=v_event.id;
  v_before_data := pg_catalog.to_jsonb(v_event) || pg_catalog.jsonb_build_object('scope_codes',v_codes);

  IF v_action='schedule' THEN
    IF v_event.status<>'draft' THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
    END IF;
    IF EXISTS (
      SELECT 1 FROM private.maintenance_events e
       WHERE e.id<>v_event.id AND e.status='scheduled'
         AND e.starts_at<v_event.ends_at AND v_event.starts_at<e.ends_at
         AND (v_event.is_global OR e.is_global OR EXISTS (
           SELECT 1 FROM private.maintenance_event_scopes es
            WHERE es.event_id=e.id AND es.scope_code=ANY(v_codes)
         ))
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='CONFLICT';
    END IF;
  ELSIF v_action='cancel' THEN
    IF v_event.status NOT IN ('draft','scheduled') THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
    END IF;
  ELSIF v_action='complete' THEN
    IF v_event.status<>'scheduled' OR pg_catalog.now()<v_event.ends_at THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION_ERROR';
    END IF;
  END IF;

  UPDATE private.maintenance_events
     SET status=CASE v_action WHEN 'schedule' THEN 'scheduled'
                              WHEN 'cancel' THEN 'cancelled'
                              ELSE 'completed' END,
         version=version+1
   WHERE id=v_event.id RETURNING * INTO v_event;
  v_after_data := pg_catalog.to_jsonb(v_event) || pg_catalog.jsonb_build_object('scope_codes',v_codes);
  v_response := pg_catalog.jsonb_build_object('ok',true,'data',
    pg_catalog.jsonb_build_object('event_id',v_event.id,'version',v_event.version,
      'status',v_event.status,'action',v_action));
  INSERT INTO private.maintenance_audit_logs(event_id,action,reason,before_data,after_data)
  VALUES(v_event.id,v_action,v_reason,v_before_data,v_after_data);
  INSERT INTO private.maintenance_idempotency(idempotency_key,request_payload,response_json)
  VALUES(v_key,v_payload,v_response);
  RETURN v_response;
END;
$$;

-- RPC ACLs: revoke PostgreSQL's default PUBLIC EXECUTE first.
REVOKE ALL ON FUNCTION public.maintenance_status_public(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.maintenance_admin_list(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maintenance_event_create(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maintenance_event_update(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maintenance_event_action(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.maintenance_status_public(jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.maintenance_admin_list(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.maintenance_event_create(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.maintenance_event_update(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.maintenance_event_action(jsonb) TO authenticated;

COMMENT ON SCHEMA private IS 'Maintenance data schema; keep excluded from Supabase Data API exposed schemas.';
COMMENT ON TABLE private.maintenance_events IS 'Draft schema proposal only; all writes should use SECURITY INVOKER RPCs.';
COMMENT ON TABLE private.maintenance_audit_logs IS 'Append-only audit trail; row mutation and TRUNCATE are blocked by triggers.';
