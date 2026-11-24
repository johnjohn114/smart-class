-- App Releases least-privilege ACL correction.
-- Reviewable SQL draft for an existing public.app_releases table.
-- Apply only after confirming this exact table/policy state in the target DB.
-- This script changes table grants only; it does not alter rows or RLS policies.
-- service_role is intentionally untouched until out-of-repository consumers
-- have been audited; do not infer that the role has no consumers from repo search.
BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.app_releases FROM anon;
GRANT SELECT ON TABLE public.app_releases TO anon;

-- Rebuild authenticated privileges explicitly. RLS policies continue to
-- restrict INSERT/UPDATE/DELETE to administrators. No TRUNCATE, REFERENCES,
-- or TRIGGER privilege is needed by the browser admin CRUD flow.
REVOKE ALL PRIVILEGES ON TABLE public.app_releases FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.app_releases TO authenticated;

COMMIT;
