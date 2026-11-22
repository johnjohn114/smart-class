# Production growth RPC and activity view security review

**Date:** 2026-11-22  
**Status:** review only; no production changes authorized or performed  
**Base:** `main` at `fd9ce87015d202e3c33f47f8c2669c2b45d4e040`

## Executive summary

The live Supabase catalog confirms that two previously identified exposures remain present. A related third issue was also found in the growth subsystem: `check_growth_achievements(uuid)` is callable by `anon` and its live function body does not validate that the requested user is the caller. It can award achievements and points for an arbitrary supplied user UUID.

Do not treat the existing repository migration or candidate SQL as applied to production. The production migration-history query remains empty / unavailable, and the live ACLs and function body differ from the hardened repository definitions.

## 1. `award_growth_points(uuid,integer,text,text,text,text,uuid)`

Live read-only catalog evidence:

- `SECURITY DEFINER`, owner `postgres`.
- ACL includes `anon=X/postgres`; `has_function_privilege('anon', ..., 'EXECUTE') = true`.
- The live body has no `auth.uid()`, `auth.jwt()`, or admin authorization check.
- The body accepts a caller-supplied `p_user_id` and `p_amount`, updates `profiles.growth_points`, inserts a `growth_point_transactions` row, refreshes the level, and may create notifications.
- No function was invoked and no member data was read or changed.

Live caller review identified these internal paths:

- `growth_registration_reward()` — trigger on `competition_registrations`.
- `growth_result_reward()` — trigger on `competition_results`.
- `admin_adjust_growth_points(uuid,integer,text)` — checks `public.is_admin()` before calling the helper.
- `complete_growth_task(text)` — derives the target from `auth.uid()`.
- `check_growth_achievements(uuid)` — see separate issue below.
- `redeem_growth_reward(uuid)` — derives the target from `auth.uid()`.

The helper is not used directly by the browser application. Its direct API execution should be removed while preserving its internal SECURITY DEFINER / trigger call paths.

## 2. `check_growth_achievements(uuid)` — additional related finding

Live read-only catalog evidence:

- `SECURITY DEFINER`, owner `postgres`.
- `anon` and `authenticated` both have EXECUTE.
- The live function body begins by checking only whether `p_user_id` is null; it does not compare the target with `auth.uid()` and does not check admin status.
- The function evaluates the supplied user's activity, inserts achievement rows, and calls `award_growth_points` when an achievement has a reward.

This creates a second route by which an anonymous caller can request achievement processing for another member. The repository's existing `202611160001_growth_function_authorization_hardening.sql` already contains a self/admin ownership guard and revokes anonymous execution, but the live production function does not match that hardened definition.

A forward-only remediation must restore the self/admin guard and remove anonymous EXECUTE. Keep authenticated self-service behavior and the admin path. The related admin-delete and level-refresh exposures are documented below.

## 3. Related growth RPC findings: admin delete and level refresh

A further read-only catalog inspection confirmed:

- `admin_delete_growth_reward(uuid)` and `admin_upsert_growth_reward(...)` are `SECURITY DEFINER`, callable by `anon`, and both live guards use `caller_role <> 'admin'` without first rejecting `auth.uid() IS NULL`. SQL NULL semantics mean a missing identity does not satisfy the rejection condition. These routines can disable/delete or create/update growth rewards.
- `refresh_growth_level(uuid)` is `SECURITY DEFINER`, callable by `anon` and `authenticated`, and the live body updates the target member's `profiles.growth_level` without checking caller ownership or admin status.

The candidate Stage A migration now restores fail-closed admin checks for both reward RPCs and separates internal level calculation into `_refresh_growth_level_internal(uuid)`, while the public `refresh_growth_level(uuid)` wrapper enforces self/admin ownership. Tests cover anonymous denial, missing-identity denial, cross-account denial, and successful admin/self flows. These are candidate changes only; the production catalog remains unchanged.

## 4. Related badge RPC finding: `check_activity_badges(uuid)`

The live function also has a NULL-sensitive ownership comparison:

- It is `SECURITY DEFINER` and directly executable by `anon` and `authenticated`.
- It checks whether `p_user_id` differs from `auth.uid()` but does not first reject a NULL `auth.uid()`.
- When an anonymous caller supplies another member's UUID, the comparison evaluates to SQL NULL and the `IF` does not reject the call. The routine can then process and unlock badges for that supplied member.

The candidate Stage A migration restores an explicit `auth.uid() IS NULL` denial, retains authenticated self/admin behavior, revokes anonymous execution, and adds tests for anonymous and cross-account attempts.

## 6. `activity_member_stats` view

Live read-only catalog evidence:

- Exposed ordinary view in `public`.
- `reloptions` is null; `security_invoker=true` is not enabled.
- `anon` and `authenticated` have SELECT.
- The view returns `user_id`, nickname, attendance counts, and both internal point subtotals plus total activity points.
- It joins `competition_attendance` and `profiles`, both of which have RLS.

The existing candidate `supabase/candidate_sql/activity_member_stats_view_hardening.sql` changes the view to `security_invoker=true`, revokes `PUBLIC` / `anon` access, and retains SELECT for `authenticated` and `service_role`.

## 7. Frontend compatibility already present in main

The current `app.js` has two relevant paths:

- `loadMyActivityHistory()` reads `activity_member_stats` with the current user's authenticated token and filters by that user's UUID. This should continue to work after the view becomes security-invoker and the source-table RLS policies apply.
- `loadActivityLeaderboard()` first reads `activity_public_leaderboard` with the anon key. If that relation returns HTTP 404, it temporarily falls back to the legacy view while selecting only the five display fields.

The candidate `supabase/candidate_sql/activity_public_leaderboard_view.sql` creates a public projection with only `nickname`, `attended_count`, `late_count`, `no_show_count`, and `activity_points`; it omits `user_id`, `checkin_points`, and `completion_points`.

The fallback is a compatibility bridge only. It does not harden the legacy view. Preserve the staged order: create and verify the restricted public projection, verify/release the frontend reader, then harden the private member view.

Public nickname and displayed aggregate visibility has been approved by the user for exactly these five fields: `nickname`, `attended_count`, `late_count`, `no_show_count`, and `activity_points`. This approval does not include `user_id`, `checkin_points`, or `completion_points`.

## 8. Candidate PR test status

The candidate PR now includes the previously required authorization and compatibility assertions in isolated PostgreSQL tests:

- `anon` cannot execute `check_growth_achievements(uuid)` or directly execute `award_growth_points(...)`.
- A non-admin member cannot process another member's achievements; the member's own achievement flow remains available.
- Trigger-based growth awards remain functional after direct API-role EXECUTE is revoked.
- The authenticated EXECUTE allowlist and trigger-only function privilege removal are checked after simulating production grant drift.
- Unsafe default function privileges are reintroduced in the test fixture and verified as revoked for future functions.
- Admin reward delete/upsert, level refresh, and activity badge checks include anonymous, missing-identity, cross-account, and permitted self/admin cases.
- The activity-view test applies Stage B after the public Stage A projection and checks member/admin RLS plus public five-column output.

Latest recorded CI run passed all three jobs. These remain synthetic PostgreSQL/Deno tests, not a hosted production Supabase/PostgREST smoke test. Re-run CI against the final PR head before merge.

## 9. Forward-only remediation outline

Do not rewrite or delete existing migration files because other environments may have applied them.

Prepare a new, idempotent forward migration that:

- Revokes direct EXECUTE on `award_growth_points` from `PUBLIC`, `anon`, and `authenticated`, while preserving required internal calls and explicitly reviewed trusted server access.
- Replaces the live `check_growth_achievements` body with the self/admin ownership guard already represented in the hardened repository definition, then removes anonymous EXECUTE.
- Applies the already-reviewed public leaderboard projection and private view hardening in the staged release sequence, after the migration baseline and frontend deployment state are reconciled.
- Includes explicit post-migration ACL, function-body, view-option, and role-based assertions.

Do not apply this migration to production until all relevant environments and migration history are reconciled, the disposable tests pass, and the hosted rollout checks are completed. The five-field public leaderboard visibility decision is already approved.

## 10. Safety record

This review used GitHub source reads and read-only PostgreSQL catalog queries only. No production SQL writes, data reads, data updates, migrations, Edge Function deployments, frontend deployments, feature-flag changes, or PR merges were performed.
