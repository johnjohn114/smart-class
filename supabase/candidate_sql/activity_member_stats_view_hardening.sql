-- Candidate hardening only; do NOT execute against production yet.
-- Reviewed against live PostgreSQL 17 catalog on 2026-11-17.
-- Goal: make the view obey caller permissions/RLS and remove anonymous access.

BEGIN;

ALTER VIEW public.activity_member_stats
  SET (security_invoker = true);

-- Remove inherited/default privileges from every API role first.
-- Keep only the SELECT access required by member history and admin tools.
REVOKE ALL PRIVILEGES ON TABLE public.activity_member_stats
  FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.activity_member_stats
  TO authenticated, service_role;

COMMIT;
