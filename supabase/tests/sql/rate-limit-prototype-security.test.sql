-- Disposable PostgreSQL CI regression tests for the rate-limit lab.
-- Run after rate-limit-prototype-setup.sql in a fresh database.
DO $acl$
BEGIN
  IF pg_catalog.has_schema_privilege('anon', 'rate_limit_lab', 'USAGE')
     OR NOT pg_catalog.has_schema_privilege('authenticated', 'rate_limit_lab', 'USAGE')
     OR pg_catalog.has_function_privilege('anon', 'rate_limit_lab.consume(text,integer,integer)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'rate_limit_lab.consume(text,integer,integer)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'rate_limit_lab.consume_authenticated_admin()', 'EXECUTE')
     OR pg_catalog.has_table_privilege('anon', 'rate_limit_lab.buckets', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'rate_limit_lab.buckets', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'rate_limit_lab.identity_buckets', 'SELECT') THEN
    RAISE EXCEPTION 'rate-limit lab ACL boundary is incorrect';
  END IF;
END
$acl$;

DO $window$
DECLARE
  v_allowed boolean;
  v_remaining integer;
  v_retry integer;
BEGIN
  SELECT allowed, remaining, retry_after_seconds
    INTO v_allowed, v_remaining, v_retry
    FROM rate_limit_lab.consume('ci:v1:window-test', 2, 60);
  IF NOT v_allowed OR v_remaining <> 1 OR v_retry <> 0 THEN
    RAISE EXCEPTION 'first request quota result incorrect';
  END IF;

  PERFORM * FROM rate_limit_lab.consume('ci:v1:window-test', 2, 60);
  SELECT allowed, remaining, retry_after_seconds
    INTO v_allowed, v_remaining, v_retry
    FROM rate_limit_lab.consume('ci:v1:window-test', 2, 60);
  IF v_allowed OR v_remaining <> 0 OR v_retry < 1 OR v_retry > 60 THEN
    RAISE EXCEPTION 'denied request or retry-after result incorrect';
  END IF;

  UPDATE rate_limit_lab.buckets
     SET window_started_at = pg_catalog.clock_timestamp() - interval '61 seconds'
   WHERE bucket_key = 'ci:v1:window-test';

  SELECT allowed, remaining, retry_after_seconds
    INTO v_allowed, v_remaining, v_retry
    FROM rate_limit_lab.consume('ci:v1:window-test', 2, 60);
  IF NOT v_allowed OR v_remaining <> 1 OR v_retry <> 0 THEN
    RAISE EXCEPTION 'expired window did not reset correctly';
  END IF;
END
$window$;

DO $invalid$
BEGIN
  BEGIN
    PERFORM * FROM rate_limit_lab.consume('invalid-policy', 0, 60);
    RAISE EXCEPTION 'invalid policy unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END
$invalid$;


DO $retention$
DECLARE
  v_deleted integer;
  v_remaining integer;
BEGIN
  -- Seed 502 stale, expired buckets to verify the per-call deletion cap.
  INSERT INTO rate_limit_lab.identity_buckets
    (endpoint_key, actor_id, window_started_at, last_seen_at, request_count)
  SELECT
    'cleanup:stale',
    (pg_catalog.md5('stale-' || g::text))::uuid,
    pg_catalog.clock_timestamp() - interval '25 hours',
    pg_catalog.clock_timestamp() - interval '25 hours',
    1
  FROM pg_catalog.generate_series(1, 502) AS g;

  -- A recently seen row must survive.
  INSERT INTO rate_limit_lab.identity_buckets
    (endpoint_key, actor_id, window_started_at, last_seen_at, request_count)
  VALUES
    ('cleanup:recent', '00000000-0000-0000-0000-000000000001',
     pg_catalog.clock_timestamp() - interval '2 minutes',
     pg_catalog.clock_timestamp() - interval '1 hour', 1);

  -- A stale last-seen row with an active window must also survive.
  INSERT INTO rate_limit_lab.identity_buckets
    (endpoint_key, actor_id, window_started_at, last_seen_at, request_count)
  VALUES
    ('cleanup:active', '00000000-0000-0000-0000-000000000002',
     pg_catalog.clock_timestamp() - interval '30 seconds',
     pg_catalog.clock_timestamp() - interval '25 hours', 1);

  v_deleted := rate_limit_lab.cleanup_stale_identity_buckets();
  IF v_deleted <> 500 THEN
    RAISE EXCEPTION 'cleanup batch limit incorrect: deleted % instead of 500', v_deleted;
  END IF;

  SELECT pg_catalog.count(*)::integer INTO v_remaining
    FROM rate_limit_lab.identity_buckets
   WHERE endpoint_key = 'cleanup:stale';
  IF v_remaining <> 2 THEN
    RAISE EXCEPTION 'cleanup did not leave exactly two stale rows for next batch: %', v_remaining;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM rate_limit_lab.identity_buckets
     WHERE endpoint_key = 'cleanup:recent'
  ) THEN
    RAISE EXCEPTION 'recently active bucket was deleted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM rate_limit_lab.identity_buckets
     WHERE endpoint_key = 'cleanup:active'
  ) THEN
    RAISE EXCEPTION 'bucket with an active window was deleted';
  END IF;

  v_deleted := rate_limit_lab.cleanup_stale_identity_buckets();
  IF v_deleted <> 2 THEN
    RAISE EXCEPTION 'second cleanup batch should delete remaining two stale rows, got %', v_deleted;
  END IF;

  v_deleted := rate_limit_lab.cleanup_stale_identity_buckets();
  IF v_deleted <> 0 THEN
    RAISE EXCEPTION 'cleanup should be idempotent when no stale rows remain';
  END IF;
END
$retention$;
