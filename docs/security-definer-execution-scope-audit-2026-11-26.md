# SECURITY DEFINER execution-scope audit — 2026-11-26

Read-only production inspection found 36 public SECURITY DEFINER functions. At audit time, 34 were executable by anon and 35 by authenticated. These are effective privilege counts, not proof that every function is exploitable.

## Candidate classification

- **16 admin RPCs:** admin_activity_analytics, admin_adjust_growth_points, admin_apply_competition_rewards, admin_cancel_order, admin_complete_order, admin_delete_growth_reward, admin_delete_video, admin_grant_competition_reward, admin_mark_competition_attendance, admin_mark_competition_member_attendance, admin_mark_order_paid, admin_promote_competition_waitlist, admin_reset_growth_member, admin_settle_competition, admin_upsert_growth_reward, admin_upsert_video. Revoke anon/PUBLIC; retain authenticated execution only with existing in-function admin checks.
- **10 member RPCs:** check_activity_badges, check_growth_achievements, checkin_competition, close_my_support_ticket, complete_growth_task, create_cash_order, join_competition_waitlist, record_growth_activity, redeem_growth_reward, use_growth_coupon. Revoke anon/PUBLIC; retain authenticated execution and per-user scope checks.
- **5 trigger entry points:** assign_member_no_and_nickname, check_competition_registration_rules, ensure_visitor_profile, growth_registration_reward, growth_result_reward. Revoke direct API-role execution; trigger dispatch remains available.
- **2 internal growth functions:** award_growth_points, refresh_growth_level. Revoke API-role execution; trusted DB-role grants must be validated alongside the dedicated growth executor ownership candidate.
- **2 admin helpers:** is_admin, is_admin_user. Revoke anon; retain authenticated.
- **1 public counter:** increment_download_count. Keep explicit anon/authenticated execution because public download counting uses it.

Migration 202611250004 and its disposable SQL test implement/test the ACL classification. This is a candidate only; function inventory counts fail closed if production differs.

### service_role compatibility decision

Migrations 202611250002 and 202611250003 temporarily grant `service_role` EXECUTE on four RPCs (`admin_delete_growth_reward`, `admin_upsert_growth_reward`, `check_growth_achievements`, and `check_activity_badges`). Migration 202611250004 intentionally supersedes those grants and removes direct `service_role` execution from all application RPCs. The intended caller is the signed-in user through the `authenticated` role, so the function's `auth.uid()` and admin/self-scope checks evaluate the actual user identity rather than a service key.

The candidate ACL regression test asserts that `service_role` cannot directly execute the admin/member RPC allowlist. The audited repository source set found no direct calls to these four RPCs from the reviewed service-role Edge Functions. Production `pg_stat_statements` shows activity for the member achievement/badge RPCs, but does not identify the caller role; external integrations and manually issued API calls are not covered. Therefore this is a deliberate least-privilege candidate policy, not proof that no external service-role dependency exists. Reconcile any external consumers before release.

## Preconditions and caveats

The check_growth_achievements and check_activity_badges target-user authorization fix is separately handled by migration 202611250003. ACL restrictions do not replace function-body checks. The test uses stub functions and verifies grants/trigger dispatch, not full business logic. The production migration ledger is still unresolved, and service_role dependencies/default privileges require separate review.

**No production DDL/DML, privilege changes, deployment, or PR merge was performed.** Do not apply until migration baseline and call sites are reconciled and all isolated tests pass.
