-- Disposable PostgreSQL CI regression tests for the rate-limit lab.
-- Run after rate-limit-prototype-setup.sql in a fresh database.
DO $acl$
BEGIN
  IF pg_catalog.has_schema_privilege('anon', 'rate_limit_lab', 'USAGE')
     OR pg_catalog.has_schema_privilege('authenticated', 'rate_limit_lab', 'USAGE')
     OR pg_catalog.has_function_privilege('anon', 'rate_limit_lab.consume(text,integer,integer)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'rate_limit_lab.consume(text,integer,integer)', 'EXECUTE')
     OR pg_catalog.has_table_privilege('anon', 'rate_limit_lab.buckets', 'SELECT')
     OR pg_catalog.has_table_privilege('authenticated', 'rate_limit_lab.buckets', 'SELECT') THEN
    RAISE EXCEPTION 'API roles unexpectedly have rate-limit lab access';
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
