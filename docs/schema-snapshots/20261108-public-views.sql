-- Catalog-reconstructed view definitions. Not pg_dump output.
-- SECURITY INVOKER options and grants require separate verification.
CREATE OR REPLACE VIEW public.activity_member_stats AS
 SELECT a.user_id,
    max(COALESCE(p.nickname, (a.user_id)::text)) AS nickname,
    (count(*) FILTER (WHERE (a.status = ANY (ARRAY['checked_in'::text, 'late'::text]))))::integer AS attended_count,
    (count(*) FILTER (WHERE (a.status = 'late'::text)))::integer AS late_count,
    (count(*) FILTER (WHERE (a.status = 'no_show'::text)))::integer AS no_show_count,
    (COALESCE(sum(a.points_awarded), (0)::bigint))::integer AS checkin_points,
    (COALESCE(sum(a.completion_points_awarded), (0)::bigint))::integer AS completion_points,
    ((COALESCE(sum(a.points_awarded), (0)::bigint) + COALESCE(sum(a.completion_points_awarded), (0)::bigint)))::integer AS activity_points
   FROM (competition_attendance a
     LEFT JOIN profiles p ON ((p.id = a.user_id)))
  GROUP BY a.user_id;;
