# activity_member_stats View hardening review (v0.1)

**Status:** candidate only; not applied to production.  
**Checked:** 2026-11-17, Supabase project PostgreSQL 17.11.

## Live read-only findings

- Exactly one ordinary view exists in `public`: `activity_member_stats`.
- Owner: `postgres`.
- Definition aggregates `competition_attendance` by `user_id`, joins `profiles`, and returns nickname plus attendance counts and point totals.
- `reloptions` is NULL, so `security_invoker` is not enabled.
- Effective privilege checks report SELECT on the view for `anon`, `authenticated`, `service_role`, and `postgres`.
- `competition_attendance` and `profiles` both have RLS enabled.
- Existing SELECT policies on the underlying tables target `authenticated`; attendance is scoped to the current user or admin, and profiles to self or admin.

## Risk statement

Because the view is owned by the privileged `postgres` role and does not use `security_invoker`, its query can run with owner privileges rather than the caller's privileges. The view is SELECT-accessible to `anon`. This is a confirmed privilege configuration and a plausible RLS bypass path; the read-only audit did not query or export any attendance/profile rows, so no claim is made that a particular user's data was actually retrieved.

## Candidate remediation

1. Set `security_invoker = true` so underlying table privileges and RLS apply to the caller.
2. Revoke all privileges on the view from `PUBLIC` and `anon`.
3. Grant SELECT only to `authenticated` and `service_role`.
4. Keep the underlying RLS policies unchanged in this focused patch.

The SQL is in `supabase/candidate_sql/activity_member_stats_view_hardening.sql`. Catalog assertions are in `supabase/tests/sql/activity_member_stats_view_hardening.test.sql`.

## Verification required before production

- Apply only in a disposable CI database first.
- Verify anonymous SELECT is denied.
- Verify authenticated users see only rows permitted by both underlying RLS policies.
- Verify an admin still sees the intended aggregate scope.
- Verify application code does not depend on anonymous access to this view.
- Re-run Supabase security advisors and inspect the resulting grants/options.
- Do not apply to production until the complete migration baseline and release gates are reconciled.

## Scope

This change does not alter the view's output columns or aggregation logic. It does not modify table data, table policies, production schema, or Data API exposed schemas.
