# Activity leaderboard security review — 2026-11-20

## Confirmed existing product behavior

The public leaderboard displays:
- nickname
- attended count
- activity points
- late count
- no-show count

A member's own activity history also displays attended, late, no-show and point totals.

## Product decision

Public leaderboard behavior must be preserved. The public response therefore retains all five existing fields:
- nickname (blank nicknames become the generic label `會員`)
- attended count
- late count
- no-show count
- activity points

Member IDs, email addresses, and unrelated profile data are not returned. Members continue to read their own complete activity history through the authenticated view and existing RLS policies.

## Proposed architecture

1. `public.activity_member_stats` becomes a `security_invoker=true` view.
2. Revoke direct view access from `PUBLIC`, `anon`, `authenticated`, and `service_role`, then grant SELECT to `authenticated` and `service_role`.
3. Authenticated member history continues through the view and underlying RLS. The service role is used only inside the Edge Function, never in browser code.
4. The public `public-activity-leaderboard` Edge Function selects and returns only the five approved leaderboard fields. It does not return user IDs or other profile data. Successful responses are cached for 60 seconds.
5. `app.js` uses the Edge Function for the public leaderboard and displays all five existing fields. Personal history continues to use the authenticated view.

## Cross-checks against the live database

- The live `competition_attendance` table has RLS enabled and no anonymous policy, but the `anon` role still has explicit table privileges. The migration removes those unnecessary base-table grants; authenticated and service-role grants are preserved.
- The live `profiles` and `competition_attendance` policies restrict authenticated member reads to the member's own rows (admins have their existing admin policies).
- Several existing public-read RLS policies call `is_admin()`, including public competition and form reads. The PR #25 ACL plan therefore keeps `anon` EXECUTE on `is_admin()`; that function must return false when `auth.uid()` is NULL. Do not remove that grant without redesigning those policies.
- After PR #25, some Security Advisor warnings for authenticated-executable SECURITY DEFINER RPCs may remain by design: the explicit allowlist retains member RPCs and admin RPCs whose function bodies enforce self/admin authorization. A warning is not by itself proof of an authorization bypass; verify the exact function guard and role grants.
- The public endpoint is read-only and caches successful responses for 60 seconds. It does not yet implement per-client rate limiting; review traffic controls before broad public launch.

## Validation

- Deno tests verify that all five approved fields are preserved and that user IDs and unrelated profile data are excluded.
- SQL regression tests use a disposable PostgreSQL database and synthetic users only; they reproduce and verify removal of the unnecessary anonymous base-table grants.
- The candidate migration is `supabase/migrations/202611200001_activity_leaderboard_security.sql`; the isolated PostgreSQL regression test applies this exact file before checking ACL and RLS behavior.
- No production SQL or Edge Function deployment is performed by this change. The migration is committed for review only and requires separate explicit approval before rollout.
- Production has no migration-history table and the migration list is empty. Do not use a blind `db push`; first reconcile the existing live schema and the duplicate growth-function forward migrations in PR #25, then choose a controlled migration application plan.
