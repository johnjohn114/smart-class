# Growth RPC and activity view forward-hardening rollout

**Status:** Draft for review; no production SQL or deployment is authorized.  
**Branch:** `security/growth-view-forward-hardening-review-20261122`

## Scope

This change addresses the growth RPC exposures and activity-view exposure found in the live catalog, without rewriting historical migrations:

1. Remove browser-role direct EXECUTE on `public.award_growth_points(...)`, preserving trusted SECURITY DEFINER/trigger calls.
2. Restore the self/admin ownership check in `public.check_growth_achievements(uuid)` and deny anonymous execution.
3. Repair `admin_delete_growth_reward(uuid)` so a missing `auth.uid()` fails closed.
4. Split growth-level calculation into a private `_refresh_growth_level_internal(uuid)` helper and an authenticated self/admin `refresh_growth_level(uuid)` wrapper.
5. Replace the broad public member aggregate read with a five-column public leaderboard projection, then harden the original member/admin view with `security_invoker=true`.

The public leaderboard still intentionally exposes nicknames and displayed attendance/late/no-show/activity-point aggregates. That product/privacy decision must be approved before production rollout.

## New forward migrations

### Stage A — `20261122120000_growth_rpc_and_public_leaderboard_hardening.sql`

- Revokes `PUBLIC`, `anon`, and `authenticated` EXECUTE on the internal award helper.
- Pins the growth award, achievement, admin-delete, and level-refresh SECURITY DEFINER routines to an empty `search_path`.
- Repairs the NULL-sensitive admin delete guard (`auth.uid() IS NULL` / role comparison uses fail-closed logic).
- Moves raw level calculation into `_refresh_growth_level_internal(uuid)`; the exposed wrapper permits only the member themself or an admin, and the internal helper is not directly executable by API roles.
- Repairs PostgreSQL function default privileges so future `postgres`-owned functions are not automatically executable by `PUBLIC`, `anon`, or `authenticated`.
- Replaces `check_growth_achievements(uuid)` with the existing self/admin ownership guard.
- Revokes `PUBLIC` and `anon` execution while preserving authenticated self-service.
- Creates `activity_public_leaderboard` with exactly five presentation columns; it omits `user_id`, `checkin_points`, and `completion_points`.
- Grants only SELECT to the API roles that need the public projection.

### Stage B — `20261122130000_activity_member_stats_security_invoker.sql`

- Requires Stage A's public projection to exist.
- Sets `security_invoker=true` on `activity_member_stats`.
- Removes all view grants, then grants SELECT only to `authenticated` and `service_role`.
- Revokes `PUBLIC` and `anon` privileges on the underlying `competition_attendance` table; the five-column security-definer public projection remains available to `anon`.
- Must be applied only after the frontend's Stage A projection reader has been released and verified.

## Existing frontend compatibility

The current `app.js` already reads the five-column public projection first. It falls back to the legacy view only on HTTP 404 and still selects only the five display fields. This fallback preserves availability during Stage A rollout; it does not secure the legacy view. Stage B must therefore remain blocked until the new projection is installed and the frontend has been verified.

## Regression coverage

- `growth-function-authorization.test.sql` now simulates reintroducing the vulnerable direct grants and unguarded achievement function after the historical hardening migration, applies the new Stage A migration, and checks:
  - anonymous and authenticated direct award-helper denial;
  - unsafe function default privileges are reintroduced before Stage A and verified to be revoked for future functions;
  - anonymous achievement RPC denial and authenticated RPC preservation;
  - self/admin achievement guard restored and cross-account call rejected;
  - anonymous admin reward deletion denied, NULL-identity admin deletion denied, and authenticated admin deletion still works;
  - anonymous level refresh denied, cross-account member refresh denied, and own-member/admin refresh remains available;
  - five-column public projection and anonymous SELECT;
  - trusted SECURITY DEFINER trigger can still call the internal award helper.
- The activity view workflow test now applies the new Stage B migration after creating the Stage A public projection, then runs member/admin RLS and public-output assertions.
- CI remains synthetic PostgreSQL only; passing CI does not constitute a production hosted Supabase smoke test.

## Rollout gates

1. Reconcile every relevant environment's schema and migration history. Production's missing migration tracking table does not prove whether another environment applied historical SQL.
2. Confirm the public nickname and aggregate visibility decision (approved: all five displayed fields remain public).
3. Run the updated PostgreSQL 17 CI suites.
4. Stage A: apply only after the migration baseline is reconciled; verify ACLs, function guards, trigger awards, and public projection.
5. Release/verify the frontend against the public projection.
6. Stage B: apply only after Stage A and frontend verification; verify anon denial on both the private view and underlying attendance table, member self-only rows, admin visibility, and continued public leaderboard access.
7. Run hosted Supabase/PostgREST smoke tests and record rollback evidence.

## Safety

This branch contains candidate migrations and disposable test changes only. No production SQL, data, RLS policy, function, view, Edge Function, feature flag, website deployment, or migration tracking state was modified. Do not merge or apply these migrations to production until all rollout gates pass.
