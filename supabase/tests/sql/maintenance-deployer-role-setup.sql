-- Disposable CI only: emulate hosted Supabase's non-superuser CREATEROLE migration role.
CREATE ROLE maintenance_deployer
  LOGIN CREATEROLE NOSUPERUSER NOCREATEDB NOREPLICATION NOBYPASSRLS
  PASSWORD 'maintenance-deployer-ci-only';

GRANT CREATE ON DATABASE maintenance_gotrue_test TO maintenance_deployer;
GRANT USAGE ON SCHEMA public TO maintenance_deployer;
GRANT CREATE ON SCHEMA public TO maintenance_deployer WITH GRANT OPTION;
GRANT EXECUTE ON FUNCTION public.is_admin() TO maintenance_deployer WITH GRANT OPTION;
