# activity_member_stats release sequence and rollback plan

**Status:** release planning only; no production change is authorized by this document.  
**PR:** #21 — Security: harden activity_member_stats view  
**Reviewed:** 2026-11-18  
**Target:** Supabase PostgreSQL 17.11

## 1. Scope and non-goals

This plan covers only the leaderboard/view security change in PR #21. It does not authorize changes to source-table RLS policies, source data, unrelated functions, Edge Functions, Data API settings, or other existing application features.

The candidate SQL files remain candidates until the migration baseline, deployment method, and rollback rehearsal are verified:

- `supabase/candidate_sql/activity_public_leaderboard_view.sql`
- `supabase/candidate_sql/activity_member_stats_view_hardening.sql`

Do not run either candidate file in production merely because this plan exists.

## 2. Preconditions (blocking release gates)

Before preparing a production migration:

1. Export and review the complete production schema/catalog baseline (views, view owners/options, grants, source-table grants, RLS policies, and relevant function definitions). Do not export member attendance/profile rows for this review.
2. Reconcile repository migration files with the live database. The read-only check on 2026-11-18 found no `supabase_migrations.schema_migrations` table, while the repository contains files under `supabase/migrations/`. Determine which files were actually applied and by what mechanism; do not infer applied status from filenames or Git history.
3. Confirm the public leaderboard privacy decision: public nicknames and the displayed attendance/late/no-show/activity-point aggregates remain visible, as they are today. The new projection omits account UUIDs and the two internal point subtotals, but the remaining aggregate data is still public.
4. Confirm the exact deployment/rollback operator, a maintenance window if needed, a pre-change backup or reproducible view definition, and a tested rollback procedure.
5. Run the disposable PostgreSQL integration tests and a production-like rehearsal against a sanitized clone. The existing CI test is synthetic and is not a production smoke test.
6. Confirm the frontend release artifact is ready and can be rolled back independently. Do not merge/release the frontend dependency before the public projection exists.

If any precondition is unmet, stop. Do not apply production SQL.

## 3. Recommended staged release order

### Stage A — Create the public projection

Apply the reviewed `activity_public_leaderboard` view candidate first, in a transaction, only after it has been converted into the approved, tracked migration format.

Verify before proceeding:

- `anon`, `authenticated`, and `service_role` can SELECT the projection as intended.
- The projection has exactly the five expected presentation columns: `nickname`, `attended_count`, `late_count`, `no_show_count`, and `activity_points`.
- It contains no `user_id`, `checkin_points`, or `completion_points` column.
- Synthetic/approved smoke-test results match expected aggregates; do not expose or copy production member rows into logs.
- The existing `activity_member_stats` view and its grants remain unchanged at this stage.

If Stage A fails, stop and remove/repair only the newly created projection after confirming no deployed client depends on it. Do not modify the original view.

### Stage B — Release the frontend reader

Release the `app.js` change that reads `activity_public_leaderboard`.

Verify:

- The public leaderboard loads without API errors.
- Ranking order, displayed labels, counts, and totals remain compatible with the existing UI.
- Member activity history and admin workflows still use their intended paths and remain functional.
- No unrelated UI or feature behavior changed.

If Stage B fails, roll the frontend back to the prior known-good artifact. The original view remains unchanged and available during Stages A and B.

### Stage C — Harden the member/admin view

Only after Stage B passes, apply the reviewed `activity_member_stats` hardening candidate in a tracked migration.

Verify:

- `anon` cannot SELECT `activity_member_stats`.
- `authenticated` can SELECT it, subject to the existing source-table RLS policies.
- A normal member sees only their own aggregate.
- An admin sees the aggregates permitted by the existing admin policies.
- `service_role` retains only the intended SELECT access to this view.
- The public projection continues to work for anonymous visitors.
- Member history, admin screens, and the public leaderboard have no new API errors.

Do not alter the existing source-table RLS policies as part of this release.

## 4. Rollback plan

Rollback is staged and must preserve least privilege wherever possible.

### If Stage A fails

- Stop the release.
- Leave the original `activity_member_stats` view untouched.
- If the new projection was created partially or incorrectly, inspect dependencies first, then remove or repair only that projection.
- Do not proceed to the frontend release.

### If Stage B fails

- Restore the previous known-good frontend artifact.
- Keep the original `activity_member_stats` view unchanged.
- Keep the new projection in place until it is confirmed that no deployed frontend version references it; then decide whether it is safe to remove.

### If Stage C fails after the hardening migration

Preferred recovery is to repair the new frontend/API path while keeping the hardened permissions. If emergency compatibility rollback is necessary:

1. Stop further rollout and restore the previous frontend artifact only if that artifact is required for service recovery.
2. Restore the captured pre-change view option/definition and grant **only the minimum SELECT privilege required** by the previous client, after explicitly accepting the temporary privacy exposure described below.
3. Do not restore broad `ALL` privileges, DML, `TRUNCATE`, or grants to `PUBLIC`.
4. Re-run the role-based checks and record the temporary exception and its removal deadline.
5. Re-apply hardening as soon as the compatible frontend is restored.

**Privacy warning:** the previous public client selected `user_id` from `activity_member_stats`. Re-granting anonymous SELECT to that original view can expose account UUIDs and internal point columns. This is an emergency compatibility rollback only, not an acceptable steady state. Prefer keeping the new public projection and rolling forward the frontend fix instead.

Never run a rollback based only on this prose. Generate and review exact rollback SQL from the captured production pre-change definition and ACL snapshot before the release window.

## 5. Acceptance checklist

Release is accepted only when all items are checked:

- [ ] Production migration baseline reconciled with repository files and live database state.
- [ ] Public nickname/aggregate visibility explicitly approved.
- [ ] Exact forward and rollback SQL reviewed and rehearsed on a sanitized clone.
- [ ] Stage A projection checks pass.
- [ ] Stage B frontend compatibility checks pass.
- [ ] Stage C RLS and privilege checks pass.
- [ ] Public leaderboard, member history, and admin workflows pass smoke tests.
- [ ] No unrelated existing features or source-table policies changed.
- [ ] Release evidence, operator, timestamp, and any exceptions recorded.

## 6. Current release decision

**Not approved for production execution, merge, or deployment yet.**

The read-only inspection on 2026-11-18 confirmed PostgreSQL 17.11, the original view's current definition/owner and broad effective grants, and the absence of the Supabase migration-history table queried above. These findings are not proof of which repository migration files have or have not been applied. The migration baseline and exact rollback SQL remain blocking items.

No production SQL, schema, data, RLS policy, Data API setting, Edge Function, or website deployment was changed while preparing this plan.
