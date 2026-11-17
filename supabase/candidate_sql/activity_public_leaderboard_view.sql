-- Candidate-only public leaderboard projection.
-- This view is intentionally public, but exposes only fields already rendered
-- by the public leaderboard. It deliberately omits user_id and private totals.
-- A missing/blank nickname uses a neutral label, never an account identifier.
BEGIN;

CREATE OR REPLACE VIEW public.activity_public_leaderboard
WITH (security_barrier = true, security_invoker = false) AS
SELECT
  max(COALESCE(NULLIF(btrim(p.nickname), ''), '會員')) AS nickname,
  count(*) FILTER (
    WHERE a.status = ANY (ARRAY['checked_in'::text, 'late'::text])
  )::integer AS attended_count,
  count(*) FILTER (WHERE a.status = 'late'::text)::integer AS late_count,
  count(*) FILTER (WHERE a.status = 'no_show'::text)::integer AS no_show_count,
  (
    COALESCE(sum(a.points_awarded), 0::bigint)
    + COALESCE(sum(a.completion_points_awarded), 0::bigint)
  )::integer AS activity_points
FROM public.competition_attendance a
LEFT JOIN public.profiles p ON p.id = a.user_id
GROUP BY a.user_id;

-- The project has broad default ACLs, so explicitly clear inherited grants
-- from every API role before granting the single required privilege.
REVOKE ALL PRIVILEGES ON TABLE public.activity_public_leaderboard
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.activity_public_leaderboard
  TO anon, authenticated, service_role;

COMMENT ON VIEW public.activity_public_leaderboard IS
  'Intentionally public leaderboard projection; contains only nickname and displayed activity aggregates, not account identifiers. Missing or blank nicknames are shown as 會員.';

COMMIT;
