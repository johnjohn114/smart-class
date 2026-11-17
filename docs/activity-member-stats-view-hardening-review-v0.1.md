# activity_member_stats View hardening review (v0.2)

**Status:** candidate only; not applied to production.  
**Checked:** 2026-11-17, Supabase project PostgreSQL 17.11.

## Live read-only findings
- The only ordinary view in `public` is `activity_member_stats`, owned by `postgres`.
- It aggregates `competition_attendance` by `user_id`, joins `profiles`, and returns nickname, attendance counts and point totals.
- `security_invoker` is not enabled.
- SELECT on the view is granted effectively to `anon`, `authenticated`, `service_role` and `postgres`.
- Both source tables have RLS enabled. Their SELECT policies target `authenticated`, with attendance scoped to self/admin and profiles scoped to self/admin.
- No production attendance/profile rows were queried or exported during this audit.

## Candidate remediation
1. Set `security_invoker = true` so underlying table privileges and RLS apply to the caller.
2. Revoke all view privileges from `PUBLIC` and `anon`.
3. Grant SELECT only to `authenticated` and `service_role`.
4. Leave source table policies unchanged.

## Frontend dependency and compatibility finding
The current public activity leaderboard in `app.js` reads `activity_member_stats` with the anon key and renders nickname, attendance, late/no-show counts, and activity points. Simply revoking anon from that view would break the public leaderboard.

The candidate therefore separates two purposes:
- `activity_member_stats`: authenticated member/admin access with caller RLS (`security_invoker=true`); anonymous access revoked.
- `activity_public_leaderboard`: an explicitly public, security-barrier projection containing only the five fields rendered by the public leaderboard. It omits `user_id`, `checkin_points`, and `completion_points`.

The public leaderboard query in `app.js` is switched to the new projection. Public visibility of nicknames and displayed activity aggregates is intentional and should be confirmed as a product/privacy decision before production release.

## Combined disposable PostgreSQL integration test
CI runs synthetic fixture setup, both candidate SQL files, and one consolidated test sequence:
- Anonymous SELECT on `activity_member_stats` is denied.
- A normal authenticated member sees only their own aggregate.
- An admin sees both synthetic member aggregates.
- All eight original `activity_member_stats` output columns remain present.
- Anonymous SELECT on `activity_public_leaderboard` succeeds.
- The public projection exposes exactly five presentation columns and no account UUID or internal point subtotals.
- Synthetic aggregate totals match the expected values.

Files:
- `supabase/tests/sql/activity_member_stats_view_hardening_setup.sql`
- `supabase/tests/sql/activity_member_stats_view_hardening.test.sql`
- `supabase/candidate_sql/activity_member_stats_view_hardening.sql`
- `supabase/candidate_sql/activity_public_leaderboard_view.sql`

## Release gates
The CI test is isolated and synthetic; it is not a production smoke test. Review application dependencies and reconcile the full production migration baseline before any production change. No production schema, data, policies, Data API settings, or deployed functions are changed by this candidate.
