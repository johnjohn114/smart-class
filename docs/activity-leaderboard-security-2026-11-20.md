# Activity leaderboard security review — 2026-11-20

## Confirmed existing product behavior

The current `app.js` public leaderboard displays:
- nickname
- attended count
- activity points
- late and no-show counts

The member's own activity history also reads `activity_member_stats` and displays attended, late, no-show and point totals.

## Data-minimization decision

The public leaderboard will retain the ranking purpose but expose only:
- nickname (blank nicknames become the generic label `會員`)
- attended count
- activity points

Late/no-show counts and member IDs remain available only through the authenticated member's own RLS-filtered activity history (or an administrator's existing authorized access). The public response includes summary totals and no user identifiers.

## Proposed architecture

1. `public.activity_member_stats` becomes a `security_invoker=true` view.
2. Revoke `PUBLIC` and `anon` SELECT from that view.
3. Grant SELECT to `authenticated` and `service_role`. Authenticated reads are constrained by existing RLS policies on `competition_attendance` and `profiles`; service_role is used only server-side.
4. The `public-activity-leaderboard` Edge Function uses the service role key server-side and returns a strict allowlist of three fields. It is a read-only public endpoint and caches results for 60 seconds.
5. `app.js` switches the public leaderboard from direct PostgREST view access to that Edge Function. The personal history call remains on the view with the signed-in user's auth headers.

## Validation

- SQL regression test uses a disposable PostgreSQL database and synthetic users only.
- Deno test verifies the public response excludes user IDs, late/no-show details, and other unexpected fields.
- No production SQL or Edge Function deployment is performed by this change.
- Supabase CLI is not installed in the current execution environment, so the SQL is kept as a reviewable draft under `supabase/sql` rather than claiming a generated migration. Before production rollout, generate a migration with `supabase migration new activity_leaderboard_security`, copy the reviewed draft into it, and apply only after a separate explicit approval.
