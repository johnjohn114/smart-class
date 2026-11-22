-- Stage B: harden the private member/admin activity aggregate view.
-- Apply only after the frontend has been released and verified against
-- public.activity_public_leaderboard (Stage A).
-- Candidate-only until migration history and production rollout are approved.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.activity_member_stats') IS NULL THEN
    RAISE EXCEPTION 'Required view public.activity_member_stats is missing';
  END IF;
  IF to_regclass('public.activity_public_leaderboard') IS NULL THEN
    RAISE EXCEPTION 'Stage A public.activity_public_leaderboard must exist first';
  END IF;
  IF to_regclass('public.competition_attendance') IS NULL THEN
    RAISE EXCEPTION 'Required source table public.competition_attendance is missing';
  END IF;
END
$preflight$;

ALTER VIEW public.activity_member_stats
  SET (security_invoker = true);

-- The live source table has unnecessary anonymous grants. RLS alone is not
-- enough when a role has table privileges, so remove both direct and inherited
-- PUBLIC access. The public leaderboard remains readable through its separate
-- security-definer projection, which exposes only the five approved fields.
REVOKE ALL PRIVILEGES ON TABLE public.competition_attendance
  FROM PUBLIC, anon;

REVOKE ALL PRIVILEGES ON TABLE public.activity_member_stats
  FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.activity_member_stats
  TO authenticated, service_role;

COMMIT;
