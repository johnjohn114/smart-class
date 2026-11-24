-- Disposable CI-only rate-limit prototype. Never apply to production.
-- Uses one atomic UPSERT per bucket; no external service and no app integration.
CREATE SCHEMA rate_limit_lab;

CREATE TABLE rate_limit_lab.buckets (
  bucket_key text PRIMARY KEY CHECK (pg_catalog.char_length(bucket_key) BETWEEN 1 AND 200),
  window_started_at timestamptz NOT NULL,
  request_count integer NOT NULL CHECK (request_count >= 1)
);

CREATE TABLE rate_limit_lab.decisions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  allowed boolean NOT NULL,
  remaining integer NOT NULL,
  retry_after_seconds integer NOT NULL
);

CREATE FUNCTION rate_limit_lab.consume(
  p_bucket_key text,
  p_limit integer,
  p_window_seconds integer
)
RETURNS TABLE (
  allowed boolean,
  remaining integer,
  retry_after_seconds integer
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_started_at timestamptz;
  v_count integer;
BEGIN
  IF p_bucket_key IS NULL OR pg_catalog.char_length(p_bucket_key) NOT BETWEEN 1 AND 200
     OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000
     OR p_window_seconds IS NULL OR p_window_seconds NOT BETWEEN 1 AND 3600 THEN
    RAISE EXCEPTION 'invalid rate-limit arguments' USING ERRCODE = '22023';
  END IF;

  INSERT INTO rate_limit_lab.buckets AS current_bucket
    (bucket_key, window_started_at, request_count)
  VALUES (p_bucket_key, v_now, 1)
  ON CONFLICT (bucket_key) DO UPDATE
    SET window_started_at = CASE
          WHEN current_bucket.window_started_at
               + pg_catalog.make_interval(secs => p_window_seconds) <= pg_catalog.clock_timestamp()
          THEN pg_catalog.clock_timestamp()
          ELSE current_bucket.window_started_at
        END,
        request_count = CASE
          WHEN current_bucket.window_started_at
               + pg_catalog.make_interval(secs => p_window_seconds) <= pg_catalog.clock_timestamp()
          THEN 1
          WHEN current_bucket.request_count >= p_limit + 1
          THEN p_limit + 1
          ELSE current_bucket.request_count + 1
        END
  RETURNING current_bucket.window_started_at, current_bucket.request_count
       INTO v_started_at, v_count;

  allowed := v_count <= p_limit;
  remaining := CASE
    WHEN p_limit - v_count > 0 THEN p_limit - v_count
    ELSE 0
  END;
  retry_after_seconds := CASE
    WHEN allowed THEN 0
    WHEN pg_catalog.date_part(
      'epoch', v_started_at + pg_catalog.make_interval(secs => p_window_seconds)
        - pg_catalog.clock_timestamp()
    ) < 1 THEN 1
    ELSE pg_catalog.ceil(pg_catalog.date_part(
      'epoch', v_started_at + pg_catalog.make_interval(secs => p_window_seconds)
        - pg_catalog.clock_timestamp()
    ))::integer
  END;
  RETURN NEXT;
END;
$function$;

COMMENT ON SCHEMA rate_limit_lab IS
  'Disposable CI prototype only; not exposed through the Supabase Data API.';
COMMENT ON FUNCTION rate_limit_lab.consume(text, integer, integer) IS
  'Atomic fixed-window limiter prototype using one PostgreSQL UPSERT per bucket.';

-- CI roles model Supabase API roles in a disposable database only.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$roles$;

REVOKE ALL ON SCHEMA rate_limit_lab FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA rate_limit_lab FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA rate_limit_lab FROM PUBLIC, anon, authenticated;

-- Identity-aware lab endpoint: actor identity is read from the verified-JWT
-- claim setting, never accepted as a function argument. This SECURITY DEFINER
-- function exists only in the disposable CI database.
CREATE TABLE rate_limit_lab.identity_buckets (
  endpoint_key text NOT NULL,
  actor_id uuid NOT NULL,
  window_started_at timestamptz NOT NULL,
  request_count integer NOT NULL CHECK (request_count >= 1),
  PRIMARY KEY (endpoint_key, actor_id)
);

CREATE FUNCTION rate_limit_lab.consume_authenticated_admin()
RETURNS TABLE (allowed boolean, remaining integer, retry_after_seconds integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $identity$
DECLARE
  v_actor uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_started timestamptz;
  v_count integer;
  v_claims text;
BEGIN
  v_claims := nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '');
  IF v_claims IS NULL THEN
    v_claims := nullif(
      (nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'),
      ''
    );
  END IF;
  IF v_claims IS NULL THEN
    RAISE EXCEPTION 'verified JWT subject required' USING ERRCODE = '28000';
  END IF;
  BEGIN
    v_actor := v_claims::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'verified JWT subject invalid' USING ERRCODE = '28000';
  END;

  INSERT INTO rate_limit_lab.identity_buckets AS existing
    (endpoint_key, actor_id, window_started_at, request_count)
  VALUES ('maintenance_admin', v_actor, v_now, 1)
  ON CONFLICT (endpoint_key, actor_id) DO UPDATE
    SET window_started_at = CASE
          WHEN existing.window_started_at + interval '60 seconds' <= pg_catalog.clock_timestamp()
          THEN pg_catalog.clock_timestamp()
          ELSE existing.window_started_at
        END,
        request_count = CASE
          WHEN existing.window_started_at + interval '60 seconds' <= pg_catalog.clock_timestamp()
          THEN 1
          WHEN existing.request_count >= 4 THEN 4
          ELSE existing.request_count + 1
        END
  RETURNING existing.window_started_at, existing.request_count
       INTO v_started, v_count;

  allowed := v_count <= 3;
  remaining := pg_catalog.greatest(0, 3 - v_count);
  retry_after_seconds := CASE WHEN allowed THEN 0 ELSE
    pg_catalog.greatest(1, pg_catalog.ceil(pg_catalog.date_part(
      'epoch', v_started + interval '60 seconds' - pg_catalog.clock_timestamp()
    ))::integer) END;
  RETURN NEXT;
END;
$identity$;

REVOKE ALL ON rate_limit_lab.identity_buckets FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION rate_limit_lab.consume_authenticated_admin() FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA rate_limit_lab TO authenticated;
GRANT EXECUTE ON FUNCTION rate_limit_lab.consume_authenticated_admin() TO authenticated;
