-- Activity leaderboard security draft.
-- Apply only after review; this file is NOT a production migration.
-- Purpose:
--   1. Make the existing per-member stats view obey caller permissions and RLS.
--   2. Remove anonymous direct access to the full view.
--   3. Keep authenticated members' own activity history working.
--   4. Let the public leaderboard Edge Function read a sanitized projection
--      with the service_role key, without exposing user IDs to browsers.
BEGIN;

CREATE OR REPLACE VIEW public.activity_member_stats
WITH (security_invoker = true)
AS
SELECT
  a.user_id,
  COALESCE(NULLIF(BTRIM(p.nickname), ''), '會員') AS nickname,
  COUNT(*) FILTER (
    WHERE a.status = ANY (ARRAY['checked_in'::text, 'late'::text])
  )::integer AS attended_count,
  COUNT(*) FILTER (WHERE a.status = 'late'::text)::integer AS late_count,
  COUNT(*) FILTER (WHERE a.status = 'no_show'::text)::integer AS no_show_count,
  COALESCE(SUM(a.points_awarded), 0::bigint)::integer AS checkin_points,
  COALESCE(SUM(a.completion_points_awarded), 0::bigint)::integer AS completion_points,
  (
    COALESCE(SUM(a.points_awarded), 0::bigint)
    + COALESCE(SUM(a.completion_points_awarded), 0::bigint)
  )::integer AS activity_points
FROM public.competition_attendance AS a
LEFT JOIN public.profiles AS p ON p.id = a.user_id
GROUP BY a.user_id;

REVOKE ALL PRIVILEGES ON TABLE public.activity_member_stats
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.activity_member_stats
  TO authenticated, service_role;

COMMIT;
