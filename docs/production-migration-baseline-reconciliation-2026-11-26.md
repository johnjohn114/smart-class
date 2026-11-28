# Production migration baseline reconciliation — 2026-11-26

## Scope and safety

This is a read-only comparison of the connected Supabase production catalog with the repository's `main` migration directory and the candidate PR branch. No production SQL was executed that changes data, schema, grants, policies, or functions. No deployment or merge was performed.

Project ref: `fsoowongtavlsrwvzbze`  
Repository: `johnjohn114/smart-class`  
PR: #41  
Candidate head after 2026-11-26 ACL follow-up: `9b04f34fe4ef349bf3a0a3a17c087c24926b3643`

## Executive result

**The production application migration baseline is not reconstructable from the current repository migration directory alone.** The `main` branch contains six migration files, while the production `public` schema contains 44 tables and one view. Several production objects match individual migration scripts, but the core schema's creation history is not represented in the available migration set. No application-owned migration history table/schema was found, and the Supabase migration-list interface returned an empty application migration list.

This is not proof that migrations were never applied. It means their application history and order cannot currently be independently verified.

## Repository migration inventory

The `main` branch `supabase/migrations` directory currently contains:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `26.11.3_calendar_fields.sql`

The candidate PR adds migrations `202611250001` through `202611250005`; these are candidate-only and have not been applied to production.

## Confirmed object comparisons

| Area | Repository definition | Production catalog observation | Result |
|---|---|---|---|
| `app_releases` | `202610310001_app_releases.sql` | Columns include `version_code`, `version_name`, `published`, `published_at`, and `created_by`; FK `created_by -> auth.users`; positive version check; policies match the first script | Matches first script |
| `app_releases` duplicate | `20261031_app_releases.sql` | This script defines `is_latest`, omits `created_by`, and adds a different APK URL constraint/index | Conflicting variant; do not run as an additional migration |
| Announcement calendar | `26.11.3_calendar_fields.sql` | All four calendar columns, both date checks, and the partial calendar index are present | Matches inspected objects |
| Maintenance system | `20261117121103_maintenance_system_initial.sql` | No `private` schema or its maintenance tables were found | Not present in production |
| Growth executor | Candidate migration `202611250001` | `growth_points_executor` role is absent; current growth RPC ownership remains `postgres` | Candidate prerequisite not present |
| Growth default ACL hardening | `202611160001` | Current `award_growth_points` and `refresh_growth_level` ACLs still include API-role EXECUTE; `_refresh_growth_level_internal` was not found; public default EXECUTE grants remain | Expected effects not present |
| Default privileges and trigger hardening | `202611170001` | `postgres` public-schema defaults still grant broad table, sequence, and function privileges to API roles | Expected effects not present |

## Current production growth RPC ACL observations

The read-only catalog showed:

- `award_growth_points(uuid, integer, text, text, text, text, uuid)`: EXECUTE granted to `postgres`, `anon`, and `service_role`.
- `refresh_growth_level(uuid)`: EXECUTE granted to `postgres`, `anon`, `authenticated`, and `service_role`.
- `check_growth_achievements(uuid)`: EXECUTE granted to `postgres`, `anon`, `authenticated`, and `service_role`.
- `check_activity_badges(uuid)`: EXECUTE granted to PUBLIC/default, `postgres`, `anon`, `authenticated`, and `service_role`.

These observations support the need for the candidate ACL work, but do not by themselves prove exploitability of every function. Caller checks, triggers, RLS, and function bodies must still be evaluated together.

## Migration-history limitations

- The Supabase `list_migrations` integration returned no application migration entries.
- No application-owned `supabase_migrations` schema or migration-history relation was found in the inspected non-system schemas.
- `auth.schema_migrations`, `realtime.schema_migrations`, and `storage.migrations` exist, but their rows track Supabase-managed subsystems, not this application's public-schema migration history.
- The repository's six migration scripts do not contain a complete creation baseline for all 44 production public tables and the existing view.

## Release blockers

1. Establish an authoritative production schema baseline and provenance. Obtain a trusted schema-only dump or equivalent catalog snapshot and identify which SQL changes were applied manually, through the Dashboard, or through migrations.
2. Resolve the duplicate `app_releases` migration pair. Preserve the production-matching definition and clearly mark the other as superseded or remove it only after confirming repository history and consumers.
3. Reconcile the effects of migrations `202611160001` and `202611170001` against live default ACLs, function ACLs, triggers, and service-role dependencies before any production execution.
4. Validate candidate migrations `202611250001`–`202611250005` against the verified baseline, including ownership transfer, function caller grants, RLS behavior, and the public leaderboard data-exposure decision.
5. Produce a reviewed forward plan and rollback/restore plan. Do not treat reverse SQL alone as a safe rollback for data-changing operations.


## 2026-11-26 follow-up: service-role RPC scope and CI

The combined candidate removes direct `service_role` EXECUTE from the application-facing SECURITY DEFINER RPC classes in migration `202611250004_security_definer_execution_scope_guard.sql`:

- Admin and member RPCs: EXECUTE remains granted to `authenticated`; direct `service_role` EXECUTE is revoked.
- Trigger-only routines: EXECUTE is revoked from PUBLIC, anon, authenticated, and service_role; trigger dispatch is covered by the isolated SQL regression test.
- Internal growth routines: direct EXECUTE is granted to `postgres` for existing postgres-owned SECURITY DEFINER callers, and revoked from service_role.
- Admin helper functions: authenticated access remains; direct service_role EXECUTE is revoked.
- Public download counter: anon/authenticated access remains; direct service_role EXECUTE is revoked.

A source scan of the browser clients and reviewed Edge Functions found that browser RPC requests use the signed-in user's JWT; the reviewed Edge Functions perform privileged Auth/table operations and do not directly call this RPC set. This is evidence for the reviewed call sites, not a substitute for rechecking every deployed function and external integration before production release.

The isolated ACL regression test now asserts the service_role denial for these classes. On candidate head `9b04f34fe4ef349bf3a0a3a17c087c24926b3643`, all five GitHub checks completed successfully: PostgreSQL RPC/RLS, GoTrue/PostgREST JWT integration, Deno, notification contract, and isolated browser preview.

This does not resolve the production migration-baseline blocker. PR #41 remains Draft and unmerged; no production migration or deployment was performed.


## 2026-11-26 product decision: public individual leaderboard

The project owner confirmed retaining the current individual public leaderboard design rather than replacing it with aggregate-only statistics. The intended public projection remains limited to:

- member nickname;
- attended count;
- late count;
- no-show count;
- activity points.

It continues to omit account IDs and internal check-in/completion point subtotals.

This is a product-design decision for the candidate only. It is not evidence that every member whose statistics may appear has been informed or has authorized publication. Before production release, the operator must provide a clear notice describing the public fields and obtain any required member/guardian/school authorization or opt-in, as applicable. If that cannot be established, do not enable the public view. No production schema or data has been changed.


## 2026-11-27 read-only reconciliation: public object inventory and exact-head CI

- Re-ran the public-schema inventory using both PostgreSQL catalogs and the Supabase table-list interface.
- PostgreSQL reports **44 ordinary tables and 1 view** in `public`.
- The Supabase table-list interface returned the same 44 table names; a name-by-name comparison found no missing or extra table. The earlier apparent 42-versus-44 discrepancy is therefore resolved as a stale/partial prior count, not a current inventory mismatch.
- All 44 returned public tables report RLS enabled. This confirms the RLS-enabled flag only; it does not prove that policies are correct or that every table has safe grants.
- The one public view is `activity_member_stats`. The candidate-only `activity_public_leaderboard` is not part of production inventory.
- Candidate head `4b5d85978de4122e8e564d7e3b96f633f7270a49`: both workflows completed successfully. Maintenance Edge Function Checks Run `45854369279` passed all 3 jobs (isolated PostgreSQL RPC/RLS and migration tests, Deno checks, GoTrue/PostgREST integration). Notification Page Checks Run `45854368962` passed both jobs (notification contracts and isolated browser preview). Total: **5/5 jobs passed on this exact commit**.
- The candidate remains Draft and unmerged. These isolated CI results and read-only catalog checks do not authorize production migration or deployment. Application migration provenance/baseline remains unresolved.


## 2026-11-27 read-only policy and helper-table follow-up

- The live public schema currently has 98 RLS policies across 42 of the 44 public tables. The two RLS-enabled tables with no policy rows are `member_no_counter` and `visitor_profiles`. RLS being enabled with no policies means ordinary Data API roles do not gain row access through a policy; it does not by itself establish that the tables are unused or safe to change.
- Current grants show `member_no_counter` is granted to `service_role` with broad table privileges, while `visitor_profiles` has broad grants to `anon`, `authenticated`, and `service_role`. Because `visitor_profiles` has RLS enabled and no policies, those grants alone do not make rows visible through RLS-protected access.
- The `member_no_counter` table has columns `id boolean`, `next_no integer`, `compacted boolean`, and `repair_version integer`. Its live database dependency is the SECURITY DEFINER trigger function `assign_member_no_and_nickname()`, attached as a BEFORE INSERT trigger on `public.profiles`; that function increments the counter when creating a visitor profile. The trigger function uses an empty search_path and schema-qualified table references.
- A read-only scan of public function definitions found no function reference to `visitor_profiles`; no trigger is attached to either helper table. This is not a complete proof that no frontend, Edge Function, or external integration accesses `visitor_profiles`.
- No grants, policies, tables, functions, or triggers were changed. Before narrowing `member_no_counter` grants or removing/retiring `visitor_profiles`, inspect all browser/Edge Function/external call sites and confirm the visitor-account creation flow end-to-end.

## Explicit non-actions

- No production migration was applied.
- No production data, RLS policy, grant, function, or schema was modified.
- PR #41 remains Draft and unmerged.
- GitHub Pages was not deployed.
- No paid service was enabled or purchased.

## 2026-11-27 visitor_profiles dependency follow-up

Read-only catalog checks of `public.visitor_profiles` confirmed:

- RLS is enabled, `FORCE ROW LEVEL SECURITY` is not enabled, and the table has **zero policies**.
- The table owner is `postgres`; current table ACL grants broad table privileges to `anon`, `authenticated`, and `service_role`. With no applicable RLS policy, the ordinary API roles do not receive row access through RLS; `service_role` is a privileged bypass role and must be considered separately.
- Columns are `id uuid`, `username text`, `active boolean`, and `created_at timestamptz`.
- The only catalog dependency found is its foreign key `id REFERENCES auth.users(id) ON DELETE CASCADE`. No view/materialized-view dependency, inbound foreign key, database function body reference, or trigger on this table was found in the inspected catalogs.
- Candidate-branch browser files `app.js` and `admin.js`, and the reviewed visitor-related Edge Functions, did not contain a direct `visitor_profiles` reference. GitHub code search on the repository's default branch also returned no matching source file. These searches are limited evidence; they do not rule out older branches, external integrations, manually issued SQL, or clients not represented in the inspected repository.

**Disposition:** do not delete the table or change grants/policies yet. First verify the deployed visitor-account lifecycle and check any external consumers. The table may be legacy, but the evidence is not sufficient to classify it as safely removable. No production object or data was changed.

## 2026-11-27 visitor-account lifecycle verification

A further read-only check of live database objects and the candidate visitor Edge Functions found:

- The deployed `visitor_accounts` table has an AFTER INSERT trigger `trg_visitor_accounts_profile` that calls `ensure_visitor_profile()`; that function inserts/upserts a visitor-role row into `public.profiles`.
- `public.profiles` also has a BEFORE INSERT trigger `trg_profiles_member_no` that assigns visitor member number/nickname using `member_no_counter`.
- The inspected candidate `create-visitor` and `reset-visitor-password` Edge Functions use `profiles` and `visitor_accounts`; neither uses `visitor_profiles`.
- This establishes that the inspected active visitor-account creation/reset path is centered on `profiles` + `visitor_accounts`, not `visitor_profiles`. It does not establish that all deployed clients or external integrations have stopped using the separate table.

**Updated assessment:** `visitor_profiles` appears disconnected from the currently inspected visitor-account lifecycle and is a plausible legacy table. Keep it in a **retirement candidate** state only. Before removal, confirm no live external consumer and preserve a rollback/export plan. Do not drop it or alter grants in this audit. No production changes were made.

## 2026-11-27 migration-sequence and live-artifact cross-check

A further read-only comparison was made between the two existing growth/default-ACL migrations (202611160001 and 202611170001), the five candidate migrations (202611250001–202611250005), and the current production function catalog.

### Expected artifacts from 202611160001

- The migration defines the internal helper public._refresh_growth_level_internal(uuid); that function is absent from the current production catalog.
- The migration replaces the growth RPC bodies and narrows their ACLs. The live catalog still shows API-role EXECUTE on the sampled functions:
  - admin_delete_growth_reward(uuid): anon, authenticated, service_role all true.
  - admin_upsert_growth_reward(...): anon, authenticated, service_role all true.
  - award_growth_points(...): anon and service_role true; authenticated false.
  - refresh_growth_level(uuid), complete_growth_task(text), check_growth_achievements(uuid), and check_activity_badges(uuid): anon, authenticated, service_role all true.
  - increment_download_count(uuid): anon, authenticated, service_role all true.
- This means the expected end-state of the inspected migration is not present in production. It does not establish whether the migration was never run, was partially applied, or was later changed manually; the missing application migration ledger prevents that historical conclusion.

### Expected artifacts from 202611170001

- The live postgres default ACLs in public still grant broad table, sequence, and function privileges to the API roles. The expected default-privilege tightening is therefore not reflected in the current catalog.
- The global default PUBLIC EXECUTE revoke appears in both 202611160001 and 202611170001. Repeating this revoke is idempotent, but it remains global for future postgres-owned functions across schemas.
- The new standalone and sequential CI probes now test that a newly created function in extensions does not inherit API EXECUTE, while the explicit Storage-specific function defaults remain intact. This tests the intended ACL behavior in disposable PostgreSQL; it does not predict every future extension vendor migration or prove managed-platform execution order.

### Sequencing disposition

- The candidate release sequence must treat 202611160001 and 202611170001 as separate prerequisite migrations, followed by candidate migrations 202611250001–202611250005, only after a trusted production baseline is established.
- Do not mark either prerequisite as applied based solely on its filename or repository presence.
- Do not replay either prerequisite against production until its exact SQL has been reconciled against live function definitions, grants, default ACLs, trigger bindings, and all external callers.
- The production application migration ledger remains absent; therefore the actual historical ordering remains unknown.

### Latest candidate verification

- Candidate head: 1753b1808344b77f6938064fb82a35936086f270.
- Maintenance Edge Function Checks Run #572: 3/3 jobs passed.
- Notification Page Checks Run #63: 2/2 jobs passed.
- Total: **5/5 jobs passed** on the exact candidate head after correcting the sequential fixture to create its extensions-schema probe before asserting its ACL.
- These are isolated CI results only. Production remains read-only, PR #41 remains Draft/unmerged, and no deployment occurred.

## 2026-11-27 growth SECURITY DEFINER function and caller audit

Read-only production function-definition checks were compared with migrations 202611160001 and 202611250001–202611250004, then cross-checked against app.js, admin.js, and the currently inspected Supabase Edge Function source files.

### Confirmed live authorization gaps addressed by candidate migrations

- public.admin_delete_growth_reward(uuid) and public.admin_upsert_growth_reward(...): current live bodies use `caller_role <> 'admin'`. When auth.uid() has no matching profile, caller_role is NULL and the IF condition is not true, so the check does not reject the caller. Migration 202611250002 changes this to an explicit non-null auth identity plus `IS DISTINCT FROM 'admin'`.
- public.check_growth_achievements(uuid): current live body accepts a caller-supplied p_user_id without first requiring auth.uid() or checking that the target is the caller/admin. Migration 202611250003 adds the authenticated identity and target-scope guard.
- public.check_activity_badges(uuid): current live body has a target-user/admin check and rejects a null target; migration 202611250003 makes the identity/target-scope checks explicit and consistent.

These are source-level findings from the current function definitions; no unauthenticated exploit test was run against production.

### Protected growth-field write paths

- The live function scan identified direct writes to profiles.growth_points/growth_level in admin_apply_competition_rewards, admin_settle_competition, admin_reset_growth_member, admin_mark_competition_member_attendance, award_growth_points, and refresh_growth_level. Some other flows call award_growth_points or refresh_growth_level rather than writing the profile columns themselves.
- Migration 202611250001 replaces the inspected competition/admin writer bodies so they call the restricted growth functions instead of directly updating protected profile columns. It also transfers award_growth_points and refresh_growth_level to the dedicated NOLOGIN BYPASSRLS role and restricts direct execution.
- The existing admin_adjust_growth_points path was found in admin.js; its exact database body and transaction/logging behavior remain a separate item to verify before release.

### Caller inventory and ACL compatibility

- Candidate ACL migration 202611250004's 36 named SECURITY DEFINER functions all currently exist exactly once in the production public schema, matching its expected inventory check.
- Browser call-site scan found member RPC calls in app.js for checkin_competition, close_my_support_ticket, join_competition_waitlist, record_growth_activity, complete_growth_task, check_growth_achievements, redeem_growth_reward, use_growth_coupon, and increment_download_count.
- Browser call-site scan found admin RPC calls in admin.js for admin_activity_analytics, admin_adjust_growth_points, admin_cancel_order, admin_complete_order, admin_delete_video, admin_grant_competition_reward, admin_mark_competition_member_attendance, admin_mark_order_paid, admin_promote_competition_waitlist, admin_reset_growth_member, admin_settle_competition, and admin_upsert_video.
- The audited Edge Function files did not contain direct calls to the 36 functions in the candidate ACL inventory. This is limited to the current repository source set and does not rule out external clients, older deployments, manual SQL, or integrations outside the repository.
- The public-facing RLS helper is_admin() must retain anon EXECUTE because six existing public-read policies invoke it; migration 004 explicitly preserves this narrow grant.

### Remaining release checks

- Inspect admin_adjust_growth_points and every remaining profile growth-field writer for transaction consistency, authorization, idempotency, and audit logging.
- Compare all 36 live function definitions with candidate replacements/guards and verify every browser call still uses the expected authenticated JWT.
- Confirm no external service_role or direct RPC consumers exist before relying on the final ACL allowlist.
- Do not apply migrations to production until the baseline/order issue is resolved and an exact managed-Supabase rehearsal is available.

### Scope

- All database checks in this section were read-only catalog/function-definition queries.
- No production data, function, grants, schema, or policy was changed. PR #41 remains Draft/unmerged and the website was not deployed.

### admin_adjust_growth_points follow-up

- The live `admin_adjust_growth_points(uuid, integer, text)` function checks `public.is_admin()`, rejects a blank reason, and delegates the point change to `public.award_growth_points(..., 'admin', ..., auth.uid())`; it does not directly update profiles itself.
- Its current ACL still permits anon, authenticated, and service_role EXECUTE. Migration 202611250004 places it in the admin allowlist, revoking PUBLIC/anon/service_role and granting authenticated execution. This preserves the intended admin UI call while removing direct anonymous/backend-role RPC exposure; the internal admin check remains necessary.
- The current `admin_apply_competition_rewards`, `admin_mark_competition_member_attendance`, `admin_settle_competition`, and `admin_reset_growth_member` bodies still contain direct growth_points/growth_level updates. Migration 202611250001 replaces these bodies with calls to award_growth_points/refresh_growth_level under the dedicated restricted owner. This is a material reason not to apply the field-protection trigger change without the corresponding writer rewrites in the same transaction.
- The browser admin UI calls admin_adjust_growth_points from admin.js using the authenticated request headers. No direct Edge Function call to this RPC was found in the audited current source set.
## 2026-11-27 frontend/RPC compatibility cross-check

### Browser RPC inventory

- Scanned app.js and admin.js for PostgREST /rest/v1/rpc calls. Found 18 distinct browser RPC names. Every one is represented in the candidate Migration 004 ACL allowlist: admin_activity_analytics, admin_adjust_growth_points, admin_delete_video, admin_grant_competition_reward, admin_mark_competition_member_attendance, admin_promote_competition_waitlist, admin_reset_growth_member, admin_settle_competition, admin_upsert_video, check_growth_achievements, checkin_competition, close_my_support_ticket, complete_growth_task, increment_download_count, join_competition_waitlist, record_growth_activity, redeem_growth_reward, and use_growth_coupon.
- The browser request payloads inspected match the live/candidate parameter names for the calls found, including p_competition_id, p_user_id, p_status, p_note, p_task_code, p_reward_id, p_coupon_id, and p_file_id.
- Candidate Migration 004 keeps authenticated execution for the browser's member/admin RPCs, removes anon and service_role execution for those allowlisted functions, and keeps anon execution only for increment_download_count and is_admin() where required by the existing public-facing policies.

### Signature and response-shape compatibility

- Read-only catalog comparison confirmed the live and candidate signatures/return types align for the inspected replacements: checkin_competition(uuid,text) -> jsonb; admin_apply_competition_rewards(uuid) -> jsonb; admin_mark_competition_member_attendance(uuid,uuid,text,text) -> jsonb; admin_reset_growth_member(uuid,text) -> jsonb; admin_settle_competition(uuid) -> jsonb; award_growth_points(uuid,integer,text,text,text,text,uuid) -> integer; admin_delete_growth_reward(uuid) -> jsonb; admin_upsert_growth_reward(19 parameters) -> jsonb; check_growth_achievements(uuid) -> integer; check_activity_badges(uuid) -> jsonb.
- The browser consumes the existing JSON keys from checkin_competition (already, points_awarded), admin_settle_competition (already, completed, no_show, completion_points), admin_mark_competition_member_attendance (status, points_awarded), and admin_reset_growth_member (reset_no, before_points, before_level). Candidate replacements preserve these keys.
- app.js member activity history selects attended_count, late_count, no_show_count, and activity_points from activity_member_stats. Migration 005 preserves those fields while restricting the view to authenticated/service_role SELECT and enabling security_invoker.
- app.js public leaderboard selects nickname, attended_count, late_count, no_show_count, and activity_points from activity_public_leaderboard. Candidate Migration 005 defines these exact columns and grants public SELECT to anon/authenticated/service_role. The view intentionally exposes nickname and activity aggregates; product/privacy approval is still required.

### Security findings validated against live definitions

- Live admin_delete_growth_reward and admin_upsert_growth_reward use caller_role <> 'admin'; if no profile row is found, caller_role is NULL and the IF condition does not reject. Candidate Migration 002 adds auth.uid() IS NULL and caller_role IS DISTINCT FROM 'admin'.
- Live check_growth_achievements accepts a supplied p_user_id without a self/admin target check. Candidate Migration 003 requires auth.uid() and rejects cross-user targets unless public.is_admin() is true. check_activity_badges receives the same explicit target-scope guard.
- Other inspected admin RPCs check the caller's profile role or is_admin/is_admin_user before mutating data. The two NULL-sensitive reward RPCs above are the identified exception addressed by Migration 002.
- The candidate growth executor's permission model is consistent with the inspected refresh_growth_level body: it needs SELECT on profiles/growth_levels and UPDATE of profiles.growth_level; award_growth_points additionally needs profile growth_points update, growth transaction SELECT/INSERT, and notifications INSERT. These are the privileges granted by Migration 001. The function owner transfer and trigger exception still require exact managed-Supabase rehearsal.

### Remaining compatibility gates

- No live production RPC was executed or mutated for this audit; function bodies and catalog metadata were read only.
- The 18-call inventory covers repository app.js/admin.js only. It does not prove the absence of external clients, older deployed bundles, scripts, or integrations using service_role or direct RPCs.
- Candidate Migration 004's allowlist is therefore compatible with the inspected current browser calls, but service_role revocation must remain pending until external consumers are confirmed absent or migrated.
- The public leaderboard requires an explicit product/privacy decision before release.
- This is a source/catalog compatibility review, not an end-to-end runtime test. Exact managed Supabase rehearsal and the production baseline/order gate remain open.

- PR #41 remains Draft/unmerged; no production SQL changes, deployment, or paid service occurred.

## 2026-11-28 CI completion and end-to-end migration coverage boundary

### Latest CI result

- PR documentation head: 110ae5f52812bfe7cc0829512e110098adbe2e89.
- Maintenance Edge Function Checks Run #46004850224: all 3 jobs completed successfully (Deno type check/tests, isolated PostgreSQL RPC/RLS tests, GoTrue-issued JWT/PostgREST integration).
- Notification Page Checks Run #46004850211: both jobs completed successfully (notification contract tests and isolated browser preview).
- Total: 5/5 workflow jobs passed on the latest documentation head.

### What the SQL tests cover

- The sequential test applies 202611160001 followed by 202611170001 in one disposable PostgreSQL 17 fixture and checks default ACLs, trigger side effects, visitor profile conflict behavior, registration rewards, result rewards, and trigger-function direct EXECUTE denial.
- The protected-profile regression test applies 202611250001 in a disposable fixture and checks protected-field writes, the dedicated growth executor role, and registration reward behavior.
- Separate disposable tests exercise 202611250002 (anonymous/member denial and admin reward CRUD), 202611250003 (achievement/badge target-user scope), 202611250004 (SECURITY DEFINER ACL classes, search_path, trigger dispatch, and anonymous RLS policies), and 202611250005 (invoker view, member/admin row scope, and public leaderboard output).

### Remaining integration gap

- The workflow does not currently apply the complete release chain 202611160001 -> 202611170001 -> 202611250001 -> 202611250002 -> 202611250003 -> 202611250004 -> 202611250005 in one coherent database fixture.
- The five 20261125 migrations are verified through separate disposable fixtures, not one single sequential run. Thus cross-migration interactions involving function ownership, ACL changes, trigger behavior, views, and later migrations have not yet been proven together.
- The fixtures use PostgreSQL 17 and selected managed-role simulations, but they are not an exact reproduction of the managed production Supabase role catalog, existing objects, extensions, and historical migration baseline.
- Before release, add a full sequential integration test using a sanitized production-like baseline and managed-role ordering. It must assert the final ACLs, trigger operation, browser RPC access, view visibility, idempotent point awards, and rollback behavior after each migration boundary.

### Release disposition

- CI is green, but this does not clear the production baseline or end-to-end migration gates.
- PR #41 remains Draft/unmerged. No production SQL, grants, policies, data, or deployment was changed.
## 2026-11-28 full release-chain integration result and executor corrections

### Integration issues found and corrected

- The first full-chain attempt exposed that the growth executor lacked USAGE on schema auth and EXECUTE on auth.uid(), even though refresh_growth_level() checks auth.uid(). Migration 202611250001 now grants only those two required capabilities.
- The next run showed that registration/result trigger rewards can run without a caller JWT, while the public refresh_growth_level() wrapper correctly requires an authenticated self/admin identity. award_growth_points() therefore must not call that wrapper for internal level synchronization.
- Migration 202611250001 now routes award_growth_points() directly to _refresh_growth_level_internal(uuid), and transfers that SECURITY DEFINER helper to growth_points_executor as well. The helper then runs with the same restricted current_user that the profile-protection trigger explicitly permits. The executor owns exactly three routines: award_growth_points, refresh_growth_level, and _refresh_growth_level_internal.
- The standalone protected-profile fixture now includes the prerequisite internal helper and authenticated wrapper from migration 202611160001, so it accurately represents the required precondition for migration 202611250001.
- The full-chain fixture also removes the temporary two-argument complete_growth_task overload used only by the earlier default-ACL probe before migration 004 checks the production function inventory. It runs in a dedicated PostgreSQL service because PostgreSQL roles are cluster-wide and the other CI databases intentionally create the same role name.

### Full sequential release-chain result

- Added `supabase/tests/sql/full-growth-release-sequential.test.sql` and a dedicated `full-growth-release-chain` CI job.
- The test applies 202611160001 -> 202611170001 -> 202611250001 -> 202611250002 -> 202611250003 -> 202611250004 -> 202611250005 in one disposable PostgreSQL 17 database.
- It verifies final ownership/ACLs, trigger dispatch after direct EXECUTE revocation, visitor profile creation, registration reward, check-in idempotency, settlement idempotency, member/admin invoker-view visibility, and the public leaderboard projection.
- Exact candidate head: `e2c58c37b1e61e9429177002e14588ff79f1fbce`.
- Maintenance Edge Function Checks Run #46137872546: 4/4 jobs passed, including the new full sequential release-chain job.
- Notification Page Checks Run #46137872538: 2/2 jobs passed.
- Total: **6/6 jobs passed** on the exact candidate head.

### Remaining release gates

- This is a sanitized PostgreSQL 17 fixture, not an exact managed Supabase production rehearsal. Production role ownership/default ACLs, extensions, and the historical schema baseline still require reconciliation.
- Production migration history remains unavailable; do not infer that prerequisite migrations are applied from filenames or CI.
- External service_role/direct-RPC consumers remain unverified; public leaderboard nickname/activity aggregation still needs explicit product/privacy approval.
- No production SQL or data was changed. PR #41 remains Draft/unmerged; no deployment occurred.

## 2026-11-28 in-repository service_role / RPC consumer inventory

- Scanned candidate-branch JavaScript, TypeScript, and HTML sources for `.rpc(`, `functions.invoke`, `SUPABASE_SERVICE_ROLE_KEY`, `service_role`, and `serviceRole`.
- No direct `.rpc()` or `functions.invoke()` call sites were found in the scanned browser or Edge Function sources.
- Three Edge Functions use `SUPABASE_SERVICE_ROLE_KEY`: `create-visitor`, `reset-visitor-password`, and `send-announcement-push`. The inspected call sites use table operations and/or Auth Admin operations; no direct invocation of the SECURITY DEFINER RPC set targeted by migration 004 was found.
- `create-visitor` writes `profiles` and `visitor_accounts`; the latter is attached to `ensure_visitor_profile()` trigger. `reset-visitor-password` reads `profiles` and `visitor_accounts` and uses Auth Admin. `send-announcement-push` reads/updates `announcements` and reads `device_push_tokens`.
- The full-chain CI test already verifies trigger dispatch after direct EXECUTE is revoked from trigger-only functions.
- This source scan does not cover third-party integrations, manually run SQL, other repositories, deployed code that differs from this branch, or untracked scripts. External `service_role` RPC consumers remain an explicit release gate.
- Production `list_migrations` still returns an empty application migration list. A catalog check found platform-owned `auth.schema_migrations`, `realtime.schema_migrations`, and `storage.migrations`, but no application `supabase_migrations.schema_migrations` relation. These platform migration tables do not establish the app's historical migration baseline.
- No production SQL or data was changed.