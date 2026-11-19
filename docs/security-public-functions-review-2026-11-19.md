# Supabase public function security review — 2026-11-19

## Scope and safety

- Reviewed the live PostgreSQL function catalog and selected function definitions using read-only queries.
- No production SQL, grants, function definitions, Edge Functions, or Dashboard settings were changed.
- This document is an audit record and proposed remediation plan, not an approved migration.
- Project ref: `fsoowongtavlsrwvzbze`.

## Findings

### 1. EXECUTE privilege exposure on administrative functions

The live catalog reports `anon_can_execute = true` and `authenticated_can_execute = true` for the following **16** `public.admin_*` functions. All 16 are `SECURITY DEFINER`.

- `admin_activity_analytics()`
- `admin_adjust_growth_points(uuid, integer, text)`
- `admin_apply_competition_rewards(uuid)`
- `admin_cancel_order(uuid)`
- `admin_complete_order(uuid)`
- `admin_delete_growth_reward(uuid)`
- `admin_delete_video(uuid)`
- `admin_grant_competition_reward(uuid, text, text, text, integer, uuid)`
- `admin_mark_competition_attendance(uuid, text, text)`
- `admin_mark_competition_member_attendance(uuid, uuid, text, text)`
- `admin_mark_order_paid(uuid)`
- `admin_promote_competition_waitlist(uuid)`
- `admin_reset_growth_member(uuid, text)`
- `admin_settle_competition(uuid)`
- `admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean)`
- `admin_upsert_video(jsonb)`

EXECUTE privilege alone does not prove an operation succeeds. The definitions sampled in this pass generally perform admin checks:
- Most check for a matching `profiles.id = auth.uid()` row with `role = 'admin'`.
- `admin_adjust_growth_points` delegates to `public.is_admin()`, which checks the authenticated UID against `profiles`.
- `admin_delete_video` and `admin_upsert_video` delegate to `public.is_admin_user()`, which also checks the authenticated UID against `profiles`.
- `admin_reset_growth_member` explicitly rejects a NULL `auth.uid()` and checks `is_admin()`.

Therefore, the broad EXECUTE grants are an unnecessary exposure surface, but the read-only checks do **not** establish that all 16 functions can be successfully used by anonymous callers. The two NULL-sensitive checks below are the confirmed authorization logic defects found so far.

### 2. Two confirmed NULL-sensitive authorization checks

The live definitions of these functions use a check equivalent to:

```sql
if caller_role <> 'admin' then
  raise exception '...';
end if;
```

- `public.admin_delete_growth_reward(uuid)`
- `public.admin_upsert_growth_reward(...)`

In SQL, a comparison with NULL yields UNKNOWN, and PL/pgSQL IF does not enter the branch for UNKNOWN. If no profile row is found, `caller_role` can remain NULL and this check does not reject the caller.

Proposed correction:

```sql
if caller_role is distinct from 'admin' then
  raise exception '只有管理員可以執行此操作';
end if;
```

This is a confirmed logic defect in the current definitions and should be fixed in a reviewed migration.

### 3. Dependency / trigger check

- Catalog dependency query found no catalog-recorded function dependents for these 16 admin functions.
- None of the 16 is attached to a non-internal trigger.
- This does not detect every dynamic SQL call or application-side RPC call. A repository-wide source search is still needed before changing grants.
- Some admin functions call shared helpers (for example `award_growth_points`, `check_activity_badges`, `is_admin`, and `is_admin_user`). These helpers have separate permissions and should not be blanket-revoked without reviewing their intended use.

### 4. Authorization helpers

- `public.is_admin()` is `SECURITY DEFINER`, checks `auth.uid()` against `profiles.role = 'admin'`, and the catalog reports EXECUTE for `authenticated` but not `anon`.
- `public.is_admin_user()` is `SECURITY DEFINER`, checks `auth.uid()` against `profiles.role = 'admin'`, and the catalog reports EXECUTE for both `anon` and `authenticated`. An anonymous caller receives the boolean result of the admin check; it does not itself grant admin identity.
- `public.award_growth_points` is `SECURITY DEFINER`, executable by `anon` but not `authenticated` in the inspected catalog. It does not itself perform an admin check in the inspected definition. It is called by admin RPC, growth-task/achievement functions, and two trigger functions; the existing migration removes direct API-role execution while preserving trusted internal calls.

## Existing remediation draft and verification

The feature branch already contains `supabase/migrations/202611160001_growth_function_authorization_hardening.sql`. It:
- fixes the two NULL-sensitive reward-admin checks by explicitly rejecting NULL identity and using `IS DISTINCT FROM`;
- revokes direct EXECUTE on `award_growth_points` from `PUBLIC`, `anon`, and `authenticated` while preserving calls made by trusted SECURITY DEFINER functions and triggers;
- hardens several related growth helpers and trigger functions;
- loops through public SECURITY DEFINER functions to remove `PUBLIC` / `anon` EXECUTE and grants `authenticated` EXECUTE to non-trigger functions (with specific internal helpers excluded).

The branch also contains `supabase/tests/sql/growth-function-authorization.test.sql`, which checks anonymous ACL denial, ordinary member vs admin behavior, missing identity rejection, and that trigger side effects continue after trigger-function EXECUTE revocation.

**CI verification:** GitHub Actions run `44522250340` on commit `9fc4c27ead8372a9df594e3e02985b9af703e618` completed successfully. The isolated PostgreSQL job explicitly passed both the growth-function authorization regression tests and the default-privileges/trigger-side-effect tests. This verifies the migration and tests in disposable PostgreSQL fixtures, not on the live Supabase project.

## Remaining review before any production application

1. Review every public SECURITY DEFINER function body, not only the 16 `admin_*` names, to confirm authenticated callers are authorized for the specific target records and actions.
2. Trace all frontend and other repository RPC call sites, including any non-admin flows.
3. Run Supabase security advisors and compare the before/after findings in an isolated or staging environment.
4. Confirm the intended release/migration ordering and rollback plan.
5. Only after review and explicit approval, apply a production migration. No production SQL or grants have been changed as part of this audit.


### 5. Critical additional finding: `award_growth_points`

The live catalog reports this function as `SECURITY DEFINER`, executable by `anon`, and not executable by `authenticated`. Its inspected definition:
- accepts a target user ID and point amount;
- updates that user's points and records a transaction;
- does not perform an authenticated-user or admin-role check in the function body.

This means the anonymous role has a direct database execution path to a privileged points-changing function. Unlike the admin RPCs above, the inspected definition does not contain an authorization guard. Treat this as **critical priority** and address it before the routine admin grant cleanup.

The function is called internally by `admin_adjust_growth_points`, `check_growth_achievements`, `complete_growth_task`, and the `growth_registration_reward` / `growth_result_reward` trigger functions. A repository migration already revokes direct API-role EXECUTE on this helper while retaining the owner-executed internal/trigger paths. The isolated regression test explicitly verifies that the triggers still run after direct EXECUTE is revoked.

### 6. Frontend RPC call-site spot check

A read-only scan of `admin.js` on the security review branch found direct RPC call sites for:
- `admin_activity_analytics`
- `admin_cancel_order`
- `admin_complete_order`
- `admin_delete_video`
- `admin_grant_competition_reward`
- `admin_mark_competition_member_attendance`
- `admin_mark_order_paid`
- `admin_promote_competition_waitlist`
- `admin_reset_growth_member`
- `admin_settle_competition`
- `admin_upsert_video`

No direct string match was found for the remaining admin function names in `admin.js`. This is only a spot check of that one file, not proof that there are no call sites elsewhere in the repository or external clients.

## Important caveats

- `anon_can_execute = true` indicates a database privilege, not proof of successful business operation.
- The definition review in this pass covers all 16 admin functions at a high level, but does not replace full testing with real JWT roles or exhaustive application call-site tracing.
- The existing migration is still a branch-only draft; the successful CI run used disposable PostgreSQL databases and did not modify the live project.
- The migration's blanket authenticated grant to non-trigger SECURITY DEFINER functions still requires a complete function-body authorization review before production use.
- No production change has been made.
