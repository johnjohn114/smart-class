-- pgbench issues this statement concurrently against one shared bucket.
SELECT * FROM rate_limit_lab.consume('ci:v1:admin:test-user', 5, 60);
