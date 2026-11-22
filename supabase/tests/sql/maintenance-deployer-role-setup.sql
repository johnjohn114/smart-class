-- Disposable CI only: emulate Supabase postgres as a non-superuser database owner.
-- Supabase's postgres database owner has BYPASSRLS; the RPC pseudo-role must not inherit it.
CREATE ROLE maintenance_deployer
  LOGIN CREATEROLE CREATEDB NOSUPERUSER BYPASSRLS
  PASSWORD 'maintenance-deployer-ci-only';
ALTER DATABASE maintenance_gotrue_test OWNER TO maintenance_deployer;
-- In production postgres owns this helper; grant-option simulates that ownership
-- for the non-superuser database-owner role used by this isolated harness.
GRANT EXECUTE ON FUNCTION public.is_admin()
  TO maintenance_deployer WITH GRANT OPTION;
