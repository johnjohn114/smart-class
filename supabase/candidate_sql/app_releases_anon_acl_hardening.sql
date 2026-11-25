-- Candidate-only least-privilege hardening for the live App Releases table.
-- Apply only after a separate reviewed production approval.
-- Keeps anonymous SELECT for published releases while removing unused write/DDL-adjacent grants.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON TABLE public.app_releases
FROM anon;
