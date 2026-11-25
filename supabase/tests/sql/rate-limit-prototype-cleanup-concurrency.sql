-- pgbench worker script for simultaneous cleanup calls in the disposable CI DB.
-- The fixture is seeded separately, then this script is run with multiple clients.
SELECT rate_limit_lab.cleanup_stale_identity_buckets();
