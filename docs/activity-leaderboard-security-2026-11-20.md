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

## Validation

- Deno tests verify that all five approved fields are preserved and that user IDs and unrelated profile data are excluded.
- SQL regression tests use a disposable PostgreSQL database and synthetic users only; they reproduce and verify removal of the unnecessary anonymous base-table grants.
- No production SQL or Edge Function deployment is performed by this change.
- Supabase CLI is not installed in the current execution environment, so the SQL is kept as a reviewable draft under `supabase/sql` rather than claimed as a generated migration. Before production rollout, create a formal migration, review it, and apply it only after separate explicit approval.
