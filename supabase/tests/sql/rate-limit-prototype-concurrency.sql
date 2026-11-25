WITH decision AS (
  SELECT * FROM rate_limit_lab.consume('ci:v1:admin:test-user', 5, 60)
)
INSERT INTO rate_limit_lab.decisions(allowed, remaining, retry_after_seconds)
SELECT allowed, remaining, retry_after_seconds FROM decision;
