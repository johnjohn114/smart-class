-- Candidate-only migration. Do not apply to production until the live migration
-- baseline, deployment sequence, and rollback have been explicitly approved.
-- PostgreSQL 17: separate the member/admin view from the intentionally public
-- leaderboard projection. Source-table RLS policies are not changed.

BEGIN;

-- Member history/admin view: enforce the caller's source-table grants and RLS.
ALTER VIEW public.activity_member_stats
  SET (security_invoker = true);

REVOKE ALL PRIVILEGES ON TABLE public.activity_member_stats
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.activity_member_stats
  TO authenticated, service_role;

-- Public projection: only expose fields rendered by the public leaderboard.
-- Deliberately omit user_id and internal point subtotals.
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

REVOKE ALL PRIVILEGES ON TABLE public.activity_public_leaderboard
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.activity_public_leaderboard
  TO anon, authenticated, service_role;

COMMENT ON VIEW public.activity_public_leaderboard IS
  'Intentionally public leaderboard projection; exposes nickname and displayed activity aggregates only. It omits account identifiers and internal point subtotals. Blank nicknames are shown as 會員.';

COMMIT;
