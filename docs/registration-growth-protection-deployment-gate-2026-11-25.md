# Registration Growth Protection — Deployment Gate

Date: 2026-11-25  
Related PR: https://github.com/johnjohn114/smart-class/pull/38  
Candidate branch: `fix/registration-protected-profile-growth-guard-20261125`  
Reviewed candidate head: `873b7411606e8f90b74501da39f58eb122faf360`

## Current decision: HOLD — not approved for production

This document is a release checklist, not deployment authorization.

- PR #38 must remain Draft and unmerged.
- No production SQL, migration, deployment, feature-flag change, or Supabase setting change is authorized by this document.
- Keep the solution on the existing free GitHub Actions / disposable CI path. Do not create paid branches or services.
- The production migration baseline is unresolved: the live database has no `supabase_migrations` schema/table, and a complete schema-only export plus clean-database reconstruction has not been completed.
- Do not apply this migration until the baseline and exact deployment order are independently verified.

## Verified issue

Production logs identified the failed registration path:

`competition_registrations INSERT` → `growth_registration_reward()` → `award_growth_points()` → update of `profiles.growth_points` → `protect_profile_fields()` exception.

The exception aborts the registration transaction, so the registration is rolled back.

## Candidate design review

The candidate migration:

- Creates a `NOLOGIN BYPASSRLS` role named `growth_points_executor`.
- Gives it narrowly scoped table/column privileges and makes it owner of only `award_growth_points()` and `refresh_growth_level()`.
- Removes its `CREATE` privilege on the `public` schema after ownership transfer.
- Uses `current_user = 'growth_points_executor'` in the profile trigger guard, not a caller-settable custom GUC.
- Leaves identity and authorization fields (`id`, `role`, `member_no`, `created_at`) protected.
- Revokes direct execution of the growth routines from `PUBLIC`, `anon`, and `authenticated` as applicable; grants the server role the intended execution permission.
- Routes registration, check-in, reward, reset, and settlement growth updates through the controlled routines.

Security caveat: `BYPASSRLS` is a powerful attribute. It is acceptable only if the role remains NOLOGIN, is not granted to application roles, owns only the two reviewed functions, has no schema CREATE privilege, and has only the reviewed object privileges. Recheck all of these against the actual target database immediately before any eventual deployment.

## CI evidence

For the current candidate head `873b7411606e8f90b74501da39f58eb122faf360`, workflow run [45614991398](https://github.com/johnjohn114/smart-class/actions/runs/45614991398) completed successfully. It ran all three jobs on this exact head; the earlier run [45613974577](https://github.com/johnjohn114/smart-class/actions/runs/45613974577) belongs to the previous candidate head and is historical evidence only.

The three jobs passed:
1. Deno type check and tests.
2. GoTrue-issued JWT and PostgREST integration.
3. Isolated PostgreSQL RPC and RLS tests, including the protected-profile growth regression test.

CI success proves the tested disposable environment passed. It does not prove the production migration baseline, production ACL state, or deployment safety.

## Mandatory release gates

Do not merge or deploy until every item is checked:

1. Obtain a complete, read-only schema-only export of the production database using a supported method; do not use `db pull` if it mutates remote migration history.
2. Reconstruct the exported schema in a fresh disposable PostgreSQL/Supabase-compatible database.
3. Compare the candidate migration's assumptions against that reconstructed schema, including exact function definitions, owners, ACLs, trigger definitions, dependencies, extensions, and default privileges.
4. Resolve why the production migration history is absent and establish an auditable migration baseline. Do not infer migration application from matching object fingerprints alone.
5. Re-run all relevant CI tests against the final PR head after any changes.
6. Review the target role and function ACLs: executor role attributes, memberships, owned-function count, schema privileges, table/column privileges, function EXECUTE ACLs, and trigger enabled state.
7. Confirm a current backup/recovery point and a tested recovery procedure.
8. Obtain explicit user approval for the specific production deployment. A general acknowledgement or approval to prepare this checklist is not deployment authorization.

## Deployment sequence — only after all gates and explicit approval

1. Freeze unrelated schema/function changes during the release window.
2. Verify the exact production project, database version, backup/recovery point, and migration baseline.
3. Apply the reviewed migration once, through the agreed migration mechanism, with failure-on-error enabled and transaction handling verified.
4. Immediately inspect the created role, its memberships and owned functions, all grants, the profile trigger definition/enabled state, and the final function owners.
5. Run a controlled registration test using an approved test account and test competition. Confirm registration persists and exactly one five-point ledger entry is created.
6. Verify ordinary members still cannot change protected profile fields.
7. Verify check-in, admin reward, reset, and settlement paths, including no duplicate point transactions.
8. Check application and database logs for new errors before reopening normal use.

Do not use ad-hoc SQL edits in the production Dashboard as a shortcut around the migration baseline.

## Stop conditions

Stop and do not continue if:
- the live schema differs from the reviewed baseline;
- the executor role already exists or has unexpected memberships/privileges;
- the migration fails or any post-deploy assertion differs;
- registration still fails or points are duplicated;
- the recovery point or rollback procedure cannot be verified.

## Recovery / rollback policy

No automatic rollback SQL is approved yet. This migration changes function definitions, function ownership, role grants, and the profile trigger. A safe rollback must restore the exact pre-deployment function bodies, owners, ACLs, trigger definition, and role state from a verified production snapshot/baseline.

If deployment ever begins and a check fails:
1. Stop further writes/deployment steps and preserve the error logs.
2. Do not blindly drop `growth_points_executor`; it may own functions.
3. Do not disable or remove `protect_profile_fields()`, and do not grant broad profile update privileges.
4. Use only a rollback script derived from the verified pre-deployment schema and tested in the disposable reconstruction.
5. If exact restoration cannot be demonstrated, stop and prepare a forward corrective migration instead of improvising production SQL.

## Cost and scope

Use the existing free CI workflow and disposable CI database only. No paid Supabase branch, paid test database, or new paid service is required for the current review. Production remains unchanged while this gate is on HOLD.


## Additional read-only security findings (2026-11-25)

These findings were confirmed against the live catalog after the original PR #38 gate was written. They are separate from the registration rollback root cause and remain unresolved; production was not modified.

1. `public.admin_delete_growth_reward(uuid)` and `public.admin_upsert_growth_reward(...)` are SECURITY DEFINER functions. Their live bodies use `IF caller_role <> 'admin'`. When `auth.uid()` has no matching profile, `caller_role` is NULL and the IF condition is not TRUE. Both functions are executable by anon in the live ACL. Candidate migration `202611250002_admin_growth_reward_null_auth_guard.sql` adds explicit missing-identity/NULL-safe rejection and revokes anon/PUBLIC EXECUTE.
2. `public.activity_member_stats` is a postgres-owned view with no `security_invoker=true` option and broad SELECT privileges including anon. A read-only test under the anon role returned aggregate view rows while direct reads of the underlying attendance/profile tables were denied. This confirms an anonymous aggregate-data exposure; review whether any public visibility is intended before choosing a least-privilege correction.
3. Default privileges for both `postgres` and `supabase_admin` in schema `public` grant future tables broad DML privileges and future functions EXECUTE to anon/authenticated/service_role; future sequences also have broad privileges. This is a separate hardening task. RLS remains relevant for tables, so the default ACL finding is not by itself proof that all future data is readable or writable.
4. The managed production `postgres` role is not a superuser, but it has CREATEROLE and BYPASSRLS. After ownership of the two growth functions is transferred to `growth_points_executor`, existing postgres-owned SECURITY DEFINER routines still need explicit EXECUTE on those functions. Candidate migration `202611250001_protect_profile_fields_growth_system_updates.sql` now grants EXECUTE to postgres and service_role, and its regression test checks the explicit ACL entry rather than relying only on `has_function_privilege` (which a superuser CI role could mask).

## Combined candidate

- Integration PR: https://github.com/johnjohn114/smart-class/pull/41
- Candidate migration order:
  1. `202611250001_protect_profile_fields_growth_system_updates.sql`
  2. `202611250002_admin_growth_reward_null_auth_guard.sql`
- PR #41 combines these changes and their isolated tests. Keep it Draft and unmerged until the current head's CI finishes and the separate view/default-privilege findings have their own reviewed remediation plan.
- CI uses disposable GitHub Actions services; no paid database is required.


## Candidate-chain reconciliation — 2026-11-28

The 2026-11-25 finding above remains a real production issue: the live reward RPC definitions still need a reviewed NULL-auth guard, and no production migration has been applied.

During the later candidate-chain review, the same explicit identity check and `IS DISTINCT FROM 'admin'` guard were found already present in `202611160001_growth_function_authorization_hardening.sql`. Therefore `202611250002_admin_growth_reward_null_auth_guard.sql` duplicated the function bodies when the complete candidate chain was applied in sequence. It also temporarily granted `service_role` EXECUTE, which the final ACL migration subsequently removed.

**Candidate-only cleanup:** migration 002 and its duplicate standalone test fixtures were removed from the follow-up branch. The NULL-auth behavior remains covered by `growth-function-authorization.test.sql`, which applies 160001 and checks that both admin reward RPCs reject an authenticated database role with no user identity. This does not fix production by itself; the candidate migration remains unapplied and release remains HOLD.

The remaining candidate sequence after 160001 and 170001 is:
1. `202611250001_protect_profile_fields_growth_system_updates.sql`
2. `202611250003_growth_achievement_user_scope_guard.sql`
3. `202611250004_security_definer_execution_scope_guard.sql`
4. `202611250005_activity_member_stats_and_public_leaderboard.sql`

Migration 003's explicit NULL target behavior is now covered by a dedicated regression: a signed-in member or admin passing NULL resolves to their own identity; anon cannot invoke either RPC; members cannot target another member. Migration 004 now rejects any unreviewed public SECURITY DEFINER function name and verifies that each expected function name has exactly one SECURITY DEFINER overload before changing ACLs.

This addendum is a candidate-source/test update only. It does not alter production SQL, the release gate, or the approval requirements above.
