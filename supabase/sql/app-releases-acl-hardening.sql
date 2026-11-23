-- App Releases least-privilege ACL correction.
-- Reviewable SQL draft for an existing public.app_releases table.
-- Apply only after confirming no out-of-repository service_role consumer.
-- This script changes table grants only; it does not alter rows, policies, or RLS.
BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.app_releases
  FROM anon, authenticated, service_role;

-- Public clients may read rows permitted by the published-only RLS policy.
GRANT SELECT ON TABLE public.app_releases TO anon;

-- Authenticated users need SELECT for the admin list and UPDATE's RLS
-- visibility check. RLS policies restrict writes to administrators.
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.app_releases TO authenticated;

-- No direct table privileges are granted to service_role. No audited
-- in-repository backend call site requires this table.

COMMIT;
