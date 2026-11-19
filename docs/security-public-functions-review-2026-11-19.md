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


### 7. Cross-account authorization checks in growth functions

The live definitions show three additional functions that accept a target member ID but do not adequately enforce ownership in the current production version:

- `check_growth_achievements(uuid)`: the live definition accepts any supplied member ID and can insert achievement unlocks and award points for that member.
- `refresh_growth_level(uuid)`: the live definition accepts any supplied member ID and updates that member's `profiles.growth_level`.
- `check_activity_badges(uuid)`: the live ownership condition uses a nullable comparison (`p_user_id <> auth.uid()`). For an anonymous caller, the comparison can evaluate to UNKNOWN and the PL/pgSQL IF may fail to reject the request. The live ACL also allows anon execution.

These are cross-account authorization risks in the live schema. The existing feature-branch migration contains fixes:
- explicitly rejects missing `auth.uid()`;
- compares target IDs using `IS DISTINCT FROM`;
- permits cross-account operations only when the caller is an admin;
- keeps the internal level recalculation in a separate `_refresh_growth_level_internal(uuid)` helper whose direct API-role EXECUTE is revoked.

The isolated SQL regression test checks that ordinary authenticated users cannot target another member, admins can perform permitted cross-member operations, and anonymous callers cannot execute these helpers.

### 8. Frontend call-site compatibility spot check

The repository's `app.js` calls `check_growth_achievements` and `refresh_growth_level` with the current signed-in user's own `u.id`. This matches the stricter self-or-admin contract in the migration. A scan of `admin.js` separately found the admin RPC call sites listed above.

The current spot check does not prove every external client or all inline scripts have been searched; it is sufficient to show the main app call pattern for these two growth functions is self-targeted.

### 9. Other public SECURITY DEFINER functions reviewed

- Trigger-returning functions are not intended as RPC endpoints; the migration revokes direct API-role EXECUTE while retaining trigger execution.
- `close_my_support_ticket`, `complete_growth_task`, `create_cash_order`, `join_competition_waitlist`, `record_growth_activity`, `redeem_growth_reward`, and `use_growth_coupon` include login/ownership checks in their inspected definitions.
- `is_admin_user()` returns only whether the current `auth.uid()` has the admin role; an anonymous caller gets false, so this is not an admin-identity bypass.
- `increment_download_count(uuid)` updates the counter for a published file without tying the target ID to a user. The feature migration restricts this RPC to authenticated users; consider rate limiting or a trusted server-side counter if download metrics must resist manipulation.
- `check_growth_achievements`, `check_activity_badges`, and `refresh_growth_level` must retain their new self-or-admin checks when future edits are made.


### 10. Final migration review — blocker found

A fresh live catalog query enumerated 36 public `SECURITY DEFINER` functions in total. A separate trigger inventory found 7 non-internal public triggers; 5 of their trigger functions are `SECURITY DEFINER` and 2 are `SECURITY INVOKER`. Do not infer trigger-function counts from the total routine count. The migration's final dynamic ACL loop currently:
- revokes `PUBLIC` and `anon` from every non-trigger SECURITY DEFINER function;
- grants `authenticated` to every non-trigger SECURITY DEFINER function except `award_growth_points` and `_refresh_growth_level_internal`;
- separately grants `anon` on `is_admin()`;
- revokes all API-role EXECUTE from trigger functions.

**This blanket authenticated grant is a production blocker.** It can expose internal or admin-oriented SECURITY DEFINER functions to every logged-in user unless each function body independently enforces the correct authorization. A list of names or a prior high-level scan is not enough to justify this grant.

The production catalog currently shows 36 public SECURITY DEFINER routines, including admin RPCs, growth functions, order and competition functions, helper functions, and trigger functions. The ACL loop must be replaced with a reviewed explicit allowlist of intended API RPC signatures, with all internal helpers and admin functions separately granted only after per-function authorization review. Trigger functions should remain non-callable directly by API roles; existing trigger execution must be regression-tested.

The isolated tests currently verify several key growth and admin paths, but do not cover every SECURITY DEFINER function that the blanket loop would grant to `authenticated`. Therefore the current CI pass does not clear this blocker.

**Decision:** do not apply this migration to production and do not merge it as a production-ready security fix yet. No production changes have been made.

## Important caveats

- `anon_can_execute = true` indicates a database privilege, not proof of successful business operation.
- The read-only review covers all 16 admin functions and the other public SECURITY DEFINER routines at a high level. It does not replace exhaustive call-site tracing for external clients or production JWT testing.
- The existing migration is still a branch-only draft; the successful CI run used disposable PostgreSQL databases and did not modify the live project.
- The migration's blanket authenticated grant to non-trigger SECURITY DEFINER functions is a confirmed production blocker; replace it with a reviewed explicit allowlist and expand regression coverage.
- No production change has been made.


### 11. Expanded frontend RPC trace — 2026-11-19

A second read-only source pass inspected the following files on `security/admin-function-permissions-20261119`: `admin.js`, `app.js`, `calendar.js`, `settings.js`, `maintenance-client.js`, `admin-app-releases.js`, `app-release-center.js`, and the main HTML pages for checkout, competitions, coupons, downloads, videos, member profile, home, news, products, and support.

**Admin-page RPCs found in `admin.js`:**
- `admin_activity_analytics()`
- `admin_cancel_order(uuid)`
- `admin_complete_order(uuid)`
- `admin_delete_video(uuid)`
- `admin_grant_competition_reward(uuid, text, text, text, integer, uuid)`
- `admin_mark_competition_member_attendance(uuid, uuid, text, text)`
- `admin_mark_order_paid(uuid)`
- `admin_promote_competition_waitlist(uuid)`
- `admin_reset_growth_member(uuid, text)`
- `admin_settle_competition(uuid)`
- `admin_upsert_video(jsonb)`
- `admin_adjust_growth_points(uuid, integer, text)`

The three order RPCs are invoked through a shared helper that constructs `/rest/v1/rpc/` plus a function name supplied by the caller; they were confirmed by tracing the helper and its three call sites, not by a literal endpoint scan.

**Member-app RPCs found in `app.js`:**
- `check_growth_achievements(uuid)`
- `refresh_growth_level(uuid)`
- `close_my_support_ticket(uuid)`
- `use_growth_coupon(uuid)`
- `checkin_competition(uuid, text)`
- `join_competition_waitlist(uuid, text)`
- `record_growth_activity()`
- `complete_growth_task(text)`
- `redeem_growth_reward(uuid)`
- `increment_download_count(uuid)`

The main member app calls `check_growth_achievements` and `refresh_growth_level` with the current signed-in user's `u.id`, which is compatible with a self-or-admin authorization rule.

**Not found in the inspected frontend files:** `admin_apply_competition_rewards`, `admin_delete_growth_reward`, `admin_mark_competition_attendance`, and `admin_upsert_growth_reward`. Their absence from these files is not proof they are unused: they may be called by external clients, hidden/legacy pages, SQL routines, or other integration paths. Keep them out of any allowlist until their intended callers and authorization rules are confirmed.

**Production ACL cross-check:** a read-only catalog query reconfirmed that all listed `admin_*` functions are `SECURITY DEFINER` and currently have EXECUTE entries for both `anon` and `authenticated`. This is a privilege exposure finding; whether a caller can complete an operation still depends on each function's body-level authorization checks. The catalog query also reconfirmed direct `anon` EXECUTE on `award_growth_points(uuid, integer, text, text, text, text, uuid)`, which remains a higher-priority helper exposure.

**Decision for migration work:** the frontend trace is materially broader but is not a complete external-client inventory. Do not replace the blanket grant loop with an allowlist based only on these frontend matches. First inspect every candidate function body and signature, confirm all legitimate callers (including trigger/helper dependencies and any external client), then grant only the minimal API roles per reviewed signature. No production database change was made during this pass.


### 12. Administrative function-body review — read-only production inspection

Inspected the current production definitions of all 16 `public.admin_*` SECURITY DEFINER functions using `pg_get_functiondef`. No SQL was executed that changes data, definitions, or privileges.

**Admin authorization guard present in the inspected body:**
- Direct `profiles.id = auth.uid() AND role = 'admin'` check: `admin_activity_analytics`, `admin_apply_competition_rewards`, `admin_cancel_order`, `admin_complete_order`, `admin_grant_competition_reward`, `admin_mark_competition_attendance`, `admin_mark_competition_member_attendance`, `admin_mark_order_paid`, `admin_promote_competition_waitlist`, `admin_settle_competition`.
- Delegates to `public.is_admin()`: `admin_adjust_growth_points`, `admin_reset_growth_member`.
- Delegates to `public.is_admin_user()`: `admin_delete_video`, `admin_upsert_video`.

**Two confirmed NULL-sensitive defects remain in live production definitions:**
- `admin_delete_growth_reward(uuid)`
- `admin_upsert_growth_reward(...)`

Both load `caller_role` from `profiles` and then test `caller_role <> 'admin'`. A missing profile / NULL role makes the condition UNKNOWN, which does not enter the PL/pgSQL rejection branch. The migration's `IS DISTINCT FROM 'admin'` fix is necessary. The same two functions should not receive broad authenticated EXECUTE as a substitute for fixing their body checks.

**Important helper dependency:**
- `admin_settle_competition(uuid)` calls `admin_apply_competition_rewards(uuid)` internally.
- `admin_apply_competition_rewards(uuid)` is not found as a direct frontend RPC call in the inspected source set, but it is a legitimate internal dependency of settlement. This is concrete evidence that a frontend-only allowlist would be incomplete. It should be denied direct API-role EXECUTE unless a separate supported caller is confirmed; its internal call path must remain regression-tested.
- `admin_apply_competition_rewards` also calls `check_activity_badges(uuid)` for each attendee. Any direct EXECUTE restriction on that helper must preserve the trusted SECURITY DEFINER call path.

**Preliminary permission classification (not yet an applied allowlist):**
- Admin-facing API candidates with frontend call sites and body-level admin checks: `admin_activity_analytics`, `admin_adjust_growth_points`, `admin_cancel_order`, `admin_complete_order`, `admin_delete_video`, `admin_grant_competition_reward`, `admin_mark_competition_member_attendance`, `admin_mark_order_paid`, `admin_promote_competition_waitlist`, `admin_reset_growth_member`, `admin_settle_competition`, `admin_upsert_video`. These should be granted to `authenticated` only after the migration explicitly revokes `PUBLIC` and `anon`, and the NULL-sensitive reward admin functions are fixed.
- Internal dependency candidate: `admin_apply_competition_rewards`; no direct frontend call found, but used by `admin_settle_competition`. Do not expose directly to API roles without a separately confirmed need.
- No direct frontend call found for `admin_mark_competition_attendance`, `admin_delete_growth_reward`, or `admin_upsert_growth_reward`; first verify whether a hidden/legacy admin page or external client requires them. The two growth reward functions have the confirmed NULL-sensitive guard defect.
  
**Caveat:** this pass confirms the presence of guards in function bodies; it does not exercise them with production JWTs or prove the behavior of every helper under all role contexts. A separate review of the non-admin SECURITY DEFINER RPCs and internal helper dependencies is still required before editing the blanket grant loop. No production privileges or function definitions were changed.


### 13. Member-facing RPC and growth-helper body review — 2026-11-19

Inspected production definitions (read-only) for the member-facing RPCs and growth helpers listed below.

**Confirmed cross-account authorization defects / high-risk helper exposure:**
- `check_growth_achievements(uuid)`: accepts an arbitrary `p_user_id`, reads and writes that user's achievement state, sends notifications, and can award points. The function body has no check that the target is `auth.uid()` or that the caller is an admin.
- `refresh_growth_level(uuid)`: accepts an arbitrary `p_user_id` and updates that profile's growth level; no caller identity or admin check exists in the function body.
- `check_activity_badges(uuid)`: checks `p_user_id <> auth.uid()`. With an anonymous caller, `auth.uid()` is NULL and the comparison is UNKNOWN, so the rejection branch can be skipped. It also mutates badge rows for the selected user. Must explicitly reject missing identity and use NULL-safe comparison (e.g. `IS DISTINCT FROM`) with admin override.
- `award_growth_points(uuid,integer,text,text,text,text,uuid)`: SECURITY DEFINER helper accepts arbitrary target user and amount, updates balances and inserts transactions, with no authorization check in its own body. It is used internally by `admin_adjust_growth_points`, `check_growth_achievements`, `complete_growth_task`, and `redeem_growth_reward`; trusted trigger paths also exist. Direct API EXECUTE should be revoked from `PUBLIC`, `anon`, and `authenticated`, while preserving owner/internal/trigger invocation. Ensure caller-facing wrappers are independently authorized and test the internal paths.
  
**Other inspected member-facing RPC bodies contain identity/ownership checks:**
- `close_my_support_ticket(uuid)`: updates only a ticket whose `user_id=auth.uid()`.
- `use_growth_coupon(uuid)`: rejects missing login and checks coupon ownership before marking it used.
- `checkin_competition(uuid,text)`: requires login and finds registration/attendance for `auth.uid()`; checks published event, enabled/time window and code.
- `join_competition_waitlist(uuid,text)`: requires login and writes waitlist row for `auth.uid()`.
- `record_growth_activity()`: requires login and records activity only for `auth.uid()`; calls `check_growth_achievements(uid)` internally.
- `complete_growth_task(text)`: requires login and performs task/point changes for `auth.uid()`.
- `redeem_growth_reward(uuid)`: requires login and operates on the current user's profile, points, coupon and redemption.
- `is_admin()` and `is_admin_user()`: return whether the current `auth.uid()` is an admin; these are identity predicates, not standalone admin-action endpoints.

**Integrity / abuse-control observation:**
- `increment_download_count(uuid)` increments the counter for any published file ID and has no login, ownership, or rate-limit check. This does not expose private file contents in the inspected function body, but it permits download metrics manipulation if directly callable. Consider whether this should be an authenticated-only endpoint, rate-limited server-side, or treated as non-security-sensitive analytics.

**Dependency implications:**
- `check_growth_achievements` is called internally by `record_growth_activity` and `check_activity_badges` is called internally by `admin_apply_competition_rewards`. Direct API restrictions must preserve these trusted SECURITY DEFINER call paths.
- `award_growth_points` is a shared mutation helper and must not be granted to API roles merely because authenticated wrapper RPCs call it.
- `refresh_growth_level` is called by `award_growth_points`; any helper refactor (e.g. private/internal implementation) must preserve that path and be tested.
  
**Status:** This review is based on function definitions, not production JWT exploit tests. Existing feature-branch migration changes were not yet applied to production. No production function, privilege, or data change was made during this pass.

### 14. Trigger and internal dependency review — 2026-11-19

A fresh read-only production catalog check found **7 non-internal triggers** on public tables. Their trigger functions are:

- `check_competition_registration_rules()` — `SECURITY DEFINER`, attached to `competition_registrations`; validates event existence, deadline, capacity, and registration status.
- `growth_registration_reward()` — `SECURITY DEFINER`, attached to `competition_registrations`; calls `award_growth_points(...)`.
- `growth_result_reward()` — `SECURITY DEFINER`, attached to `competition_results`; calls `award_growth_points(...)` when the related competition is published.
- `assign_member_no_and_nickname()` — `SECURITY DEFINER`, attached to `profiles`; assigns visitor member number / nickname and updates the member number counter.
- `ensure_visitor_profile()` — `SECURITY DEFINER`, attached to `visitor_accounts`; creates or normalizes the visitor profile.
- `set_competition_publish_time()` — `SECURITY INVOKER`, attached to `competitions`.
- `protect_profile_fields()` — `SECURITY INVOKER`, attached to `profiles`.

The catalog contains **36 public SECURITY DEFINER functions total**, of which **5 are trigger-returning functions**. This corrects the earlier inconsistent parenthetical count in section 10.

**Permission implications:**
- The migration's trigger branch revokes direct API-role EXECUTE from trigger-returning SECURITY DEFINER functions. Trigger invocation is governed by the trigger mechanism; the trigger's continued operation must be regression-tested after those direct grants are removed.
- Both growth reward triggers depend on `award_growth_points`. Its direct API EXECUTE should remain revoked, while the trigger functions' owner-executed call path must remain functional.
- `admin_settle_competition()` calls `admin_apply_competition_rewards()` internally, and `admin_apply_competition_rewards()` calls `check_activity_badges()` for attendees. These internal calls do not by themselves justify exposing either helper as a direct API RPC.
- `_refresh_growth_level_internal()` is called by trusted growth functions and should remain unavailable to API roles.

**Current boundary:** This was a read-only production catalog and function-definition inspection. No production grants, triggers, function definitions, or data were changed. The final API allowlist is still not ready: the remaining non-trigger SECURITY DEFINER functions need a per-signature classification and their legitimate external callers must be confirmed before replacing the blanket authenticated grant loop.


### 15. Explicit EXECUTE allowlist draft — 2026-11-19

The feature-branch migration has now been updated to replace the blanket grant of every non-trigger SECURITY DEFINER routine to `authenticated` with a signature-based allowlist. The migration revokes EXECUTE from `PUBLIC`, `anon`, and `authenticated` for every public SECURITY DEFINER routine, then re-grants only reviewed API endpoints and the two RLS identity helpers described below. Existing explicit `service_role` grants on non-trigger routines are preserved; trigger-returning SECURITY DEFINER functions are also revoked from `service_role`.

**Reviewed authenticated API endpoints in the draft allowlist:**
- Admin endpoints with body-level admin checks: `admin_activity_analytics()`, `admin_adjust_growth_points(uuid,integer,text)`, `admin_cancel_order(uuid)`, `admin_complete_order(uuid)`, `admin_delete_growth_reward(uuid)`, `admin_delete_video(uuid)`, `admin_grant_competition_reward(uuid,text,text,text,integer,uuid)`, `admin_mark_competition_attendance(uuid,text,text)`, `admin_mark_competition_member_attendance(uuid,uuid,text,text)`, `admin_mark_order_paid(uuid)`, `admin_promote_competition_waitlist(uuid)`, `admin_reset_growth_member(uuid,text)`, `admin_settle_competition(uuid)`, `admin_upsert_growth_reward(...)`, and `admin_upsert_video(jsonb)`.
- Member endpoints with login / ownership guards: `check_growth_achievements(uuid)`, `check_activity_badges(uuid)`, `refresh_growth_level(uuid)`, `close_my_support_ticket(uuid)`, `create_cash_order(uuid,integer,text)`, `use_growth_coupon(uuid)`, `checkin_competition(uuid,text)`, `join_competition_waitlist(uuid,text)`, `record_growth_activity()`, `complete_growth_task(text)`, `redeem_growth_reward(uuid)`, and `increment_download_count(uuid)`.
- RLS identity helpers: `is_admin()` is granted to `anon` and `authenticated` because public RLS policies invoke it; its implementation returns false when `auth.uid()` is NULL. `is_admin_user()` is granted to `authenticated` because the videos RLS policy invokes it.

**Intentionally not granted directly to API roles:**
- `admin_apply_competition_rewards(uuid)`: internal dependency of `admin_settle_competition(uuid)`.
- `award_growth_points(...)`: internal points mutation helper used by trusted wrappers and triggers.
- `_refresh_growth_level_internal(uuid)`: migration-created internal level helper.
- Trigger-returning SECURITY DEFINER functions: invoked by database triggers, not as direct RPCs.

The explicit allowlist includes the two previously unguarded reward admin endpoints only after the migration fixes their NULL-sensitive role checks. It also includes `admin_mark_competition_attendance`, whose body has an admin guard, although no direct frontend call was found in the inspected source set; this preserves the reviewed admin RPC surface while keeping it unavailable to anonymous callers.

**Regression coverage added:** the SQL test now checks that member-facing growth endpoints remain executable by authenticated users, that the internal points and competition-reward helpers are not directly executable by authenticated users, and that RLS identity helper grants remain intact. The disposable test fixture does not define every production routine, so assertions for optional production-only helpers are guarded by `to_regprocedure(...)`.

**Still required before merge or production:** run the full CI suite against this exact branch head; inspect the test result and resolve any failures; complete a final signature-vs-allowlist diff against the live catalog; and review whether the public download counter's authenticated-only exposure is acceptable for metrics integrity. This draft is not approved for production deployment. No production database changes have been made.

### 16. Exact-branch CI and production signature reconciliation — 2026-11-19

The updated branch head `5c21435bc81a7cec4970ac4f985e32589896c174` was exercised by GitHub Actions run `44531585665`. All three jobs completed successfully:
- Deno type check and tests — success.
- Isolated PostgreSQL RPC and RLS tests — success, including the growth-function authorization regression test, trigger side-effect test, and PostgREST JWT/RPC/RLS/concurrency checks.
- GoTrue-issued JWT and PostgREST integration — success.

A fresh read-only production catalog reconciliation compared all 36 current public SECURITY DEFINER routines with the explicit migration classification. The only routines omitted from direct API grants are the five SECURITY DEFINER trigger-returning functions (which are separately revoked from API roles), plus the explicitly classified internal routines `admin_apply_competition_rewards(uuid)` and `award_growth_points(...)`. `_refresh_growth_level_internal(uuid)` is created by the migration and is explicitly revoked from all API roles and `service_role`. The two identity helpers retain only the roles needed by RLS; the reviewed admin/member endpoints are listed in section 15.

**Status:** CI is green on the current branch head and the production signature inventory has been reconciled. This does not authorize deployment. The pull request remains unmerged; no production Supabase SQL, grants, or function definitions have been changed. A final human review should still inspect the PR diff before merge and separately approve any production migration.
