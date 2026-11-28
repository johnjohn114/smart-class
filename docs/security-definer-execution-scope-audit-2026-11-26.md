# SECURITY DEFINER execution-scope audit — 2026-11-26

Read-only production inspection found 36 public SECURITY DEFINER functions. At audit time, 34 were executable by anon and 35 by authenticated. These are effective privilege counts, not proof that every function is exploitable.

## Candidate classification

- **16 admin RPCs:** admin_activity_analytics, admin_adjust_growth_points, admin_apply_competition_rewards, admin_cancel_order, admin_complete_order, admin_delete_growth_reward, admin_delete_video, admin_grant_competition_reward, admin_mark_competition_attendance, admin_mark_competition_member_attendance, admin_mark_order_paid, admin_promote_competition_waitlist, admin_reset_growth_member, admin_settle_competition, admin_upsert_growth_reward, admin_upsert_video. Revoke anon/PUBLIC; retain authenticated execution only with existing in-function admin checks.
- **10 member RPCs:** check_activity_badges, check_growth_achievements, checkin_competition, close_my_support_ticket, complete_growth_task, create_cash_order, join_competition_waitlist, record_growth_activity, redeem_growth_reward, use_growth_coupon. Revoke anon/PUBLIC; retain authenticated execution and per-user scope checks.
- **5 trigger entry points:** assign_member_no_and_nickname, check_competition_registration_rules, ensure_visitor_profile, growth_registration_reward, growth_result_reward. Revoke direct API-role execution; trigger dispatch remains available.
- **2 internal growth functions:** award_growth_points, refresh_growth_level. Revoke API-role execution; trusted DB-role grants must be validated alongside the dedicated growth executor ownership candidate.
- **2 admin helpers:** is_admin, is_admin_user. Revoke anon; retain authenticated.
- **1 public counter:** increment_download_count. Keep explicit anon/authenticated execution because public download counting uses it.
- **search_path hardening:** migrations 202611250001 and 202611250004 together pin all 36 functions to `pg_catalog, public, auth, pg_temp`, placing the temporary schema last. Migration 001 hardens `award_growth_points` and `refresh_growth_level` before transferring them to `growth_points_executor`; migration 004 hardens the remaining 34 functions. This ordering is required because the restricted executor role's SET privilege is deliberately revoked after ownership transfer. Production inspection found 34 of 36 using `search_path=public` (one function uses `public, auth`; two already use an empty path). This reduces temporary-object shadowing risk. The API roles lack CREATE on `public`; still, the temporary schema must be explicitly last for SECURITY DEFINER functions.

Migration 202611250004 and its disposable SQL test implement/test the ACL classification. This is a candidate only; function inventory counts fail closed if production differs.

### service_role compatibility decision

Migrations 202611250002 and 202611250003 temporarily grant `service_role` EXECUTE on four RPCs (`admin_delete_growth_reward`, `admin_upsert_growth_reward`, `check_growth_achievements`, and `check_activity_badges`). Migration 202611250004 intentionally supersedes those grants and removes direct `service_role` execution from all application RPCs. The intended caller is the signed-in user through the `authenticated` role, so the function's `auth.uid()` and admin/self-scope checks evaluate the actual user identity rather than a service key.

The candidate ACL regression test asserts that `service_role` cannot directly execute the admin/member RPC allowlist. The audited repository source set found no direct calls to these four RPCs from the reviewed service-role Edge Functions. Production `pg_stat_statements` shows activity for the member achievement/badge RPCs, but does not identify the caller role; external integrations and manually issued API calls are not covered. Therefore this is a deliberate least-privilege candidate policy, not proof that no external service-role dependency exists. Reconcile any external consumers before release.

## Function-body authorization and write-path review

A read-only review of the live definitions for the 16 admin RPCs and 10 member RPCs found the following candidate protections and remaining verification boundaries:

- Admin RPCs use either a direct `profiles.id = auth.uid() AND role = 'admin'` check or the `is_admin()` / `is_admin_user()` helper. The two growth-reward administration RPCs previously used a nullable role comparison; migration 202611250002 changes this to an explicit non-null identity check plus `IS DISTINCT FROM 'admin'`, preventing SQL NULL from bypassing the rejection condition.
- The member RPCs derive the acting member from `auth.uid()` or constrain writes to that identity. The two RPCs accepting a target user ID (`check_growth_achievements` and `check_activity_badges`) are hardened by migration 202611250003 to require a non-null authenticated identity and permit a different target only for an administrator.
- Production `checkin_competition` directly updates protected `profiles.growth_points`. Migration 202611250001 replaces this write with `award_growth_points()`. The same migration routes the other competition reward, settlement, attendance and growth-reset writers through the dedicated executor, so those paths do not bypass the protected-profile trigger.
- The protected-profile regression test covers registration's five-point reward, member check-in and duplicate check-in, admin reward grant, reset, badge-only level synchronization, settlement idempotency, denial of direct member edits to protected fields, and denial of direct API execution of the internal award/refresh functions.
- Six production policies granted to PUBLIC call `is_admin()`. Production currently denies anon direct EXECUTE on that helper, while migration 202611250004 deliberately grants anon only this boolean helper so public RLS policy evaluation can proceed; the isolated test checks that anonymous users see only published/active rows and cannot write admin-only rows.

These findings are based on the inspected live function definitions, policy catalog, candidate migrations and disposable test coverage. They do not establish that every external client or manual SQL integration has been inventoried, nor do isolated tests substitute for a production-baseline rehearsal.

## Production baseline reconciliation — read-only, 2026-11-27

The Supabase migration-list API currently returns an empty migration list. The expected application migration ledger relation `supabase_migrations.schema_migrations` is also absent. Consequently, repository migration filenames cannot be treated as proof of what ran in production.

Observed production catalog facts:

- Public schema currently contains 44 tables and one view. All 44 tables have RLS enabled; none has FORCE ROW LEVEL SECURITY. The single view is `activity_member_stats`.
- `activity_member_stats` currently has no `security_invoker=true` option and its view definition exposes `user_id`, attendance totals, check-in points, completion points and activity points. The current role grants include every table privilege (including SELECT, INSERT, UPDATE, DELETE and TRUNCATE) for `anon`, `authenticated` and `service_role`. Candidate migration 202611250005 is intended to revoke access to this internal view and replace public access with a narrower leaderboard projection. This production exposure must be treated as a release blocker until the migration is safely rehearsed and its public data disclosure is approved.
- `activity_public_leaderboard` does not currently exist. The `growth_points_executor` role does not currently exist. The `private` maintenance schema and its maintenance tables do not currently exist.
- The live `app_releases` table matches the shape and policies in `202610310001_app_releases.sql` (including `created_by`, and without `is_latest`). The separate `20261031_app_releases.sql` file defines a conflicting shape and must not be applied as a second migration.
- PostgreSQL default privileges for owner `postgres` in `public` still grant table, sequence and function privileges to API roles. This does not match the intended revocations in repository migrations `202611160001_growth_function_authorization_hardening.sql` and `202611170001_default_privileges_and_trigger_hardening.sql`. The live defaults need explicit reconciliation; do not infer either migration was applied from its presence in Git.
- The live `activity_member_stats` view is not security-invoker, and the above API-role grants remain broad. This independently confirms that the candidate view-hardening migration has not been applied.

Release gates:

1. Obtain an authoritative schema-only production dump or equivalent complete catalog snapshot and preserve it as the baseline.
2. Reconcile the duplicate app-release migration pair; retain the live-matching migration as the canonical history and mark the conflicting variant as non-applicable.
3. Reconcile the observed default ACLs and current trigger/function definitions with migrations 202611160001 and 202611170001, including which statements were applied manually, partially, or not at all.
4. Rehearse candidate migrations 001–005 against a disposable PostgreSQL/Supabase-compatible baseline that reproduces the live schema, roles, ownership, ACLs, triggers, views and RLS policies.
5. Decide and document consent/notice for the intentionally public per-member leaderboard before making its view available.

These observations are read-only. No production SQL, ACL, schema, data, deployment or PR merge was changed.

## Preconditions and caveats

The check_growth_achievements and check_activity_badges target-user authorization fix is separately handled by migration 202611250003. ACL restrictions do not replace function-body checks. The test uses stub functions and verifies grants/trigger dispatch, not full business logic. The production migration ledger is still unresolved, and service_role dependencies/default privileges require separate review.

**No production DDL/DML, privilege changes, deployment, or PR merge was performed.** Do not apply until migration baseline and call sites are reconciled and all isolated tests pass.
