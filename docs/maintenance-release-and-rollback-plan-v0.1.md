# Maintenance release and rollback plan v0.1

> Date: 2026-11-25 (Asia/Taipei)  
> Status: planning proposal only — NOT approved for production execution.  
> Branch: `feature/maintenance-single-pass-migration-20261122`  
> PR: #34 (Draft, open, unmerged)  
> Current PR head reviewed: `e7f57b078a39e95fa4c7ef3efa806e6be3ddeb5d`

## 1. Executive decision

**Maintenance is not production-ready and must not be deployed yet.**

The latest disposable CI run [45598357283](https://github.com/johnjohn114/smart-class/actions/runs/45598357283) completed successfully with 4/4 jobs green. It includes the new real-SQL deployment-order checks:

- Maintenance single-pass SQL draft, then Growth authorization migration.
- Growth authorization migration, then Maintenance single-pass SQL draft.
- The four Maintenance admin RPCs retain the intended authenticated-only EXECUTE grants in both orders.

This is evidence for the tested disposable PostgreSQL fixtures only. It is not a production schema baseline, hosted Supabase Edge Runtime test, or production release approval.

## 2. Release blockers — all must close before production deployment

| Gate | Current evidence | Required closure |
|---|---|---|
| Production migration baseline | Supabase migration list is empty; `supabase_migrations` schema/table was not found. No full schema-only dump/rebuild has been completed. | Complete a local, schema-only capture and reconcile all application objects, ownership, grants, policies, triggers, extensions and existing migrations. Do not use `db pull`, `db push`, migration repair or a hand-written history ledger as a substitute. |
| Final migration artifact | Tested SQL remains `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`, marked DEVELOPMENT DRAFT ONLY. Two older timestamped Maintenance migrations remain in the migration folder. | Decide the clean-bootstrap vs forward-upgrade path from verified history; create one final timestamped migration only after the baseline decision. CI must test that exact final file, not merely a separate draft. |
| Environment inventory | User confirmed no known local, preview, staging, shared or other persistent database has run the Maintenance migrations. Production history is a separate unresolved issue. | Keep the confirmation scoped to known environments; record any newly discovered environment before changing migration history. |
| Data API configuration | Prior Dashboard screenshot showed only `public` and `graphql_public` exposed; `private` was not selected. | Reconfirm immediately before release that `private` remains excluded. Do not expose internal helper RPCs just to satisfy SQL EXECUTE dependencies. |
| Edge Function runtime | Five functions are repository-only; none is deployed. CI Deno/PostgREST harnesses pass. | Confirm deployed built-in `SUPABASE_URL` and publishable/anon key availability without copying values into chat or GitHub. Confirm the actual hosted CORS allowlist is `https://johnjohn114.github.io` (or an explicitly approved override). |
| Rate-limit contract | The prototype is not integrated; its current identity/policy/retention model has blockers. API v0.7 does not deliver an HTTP 429 limiter. | Make an explicit product decision before claiming or adding rate limiting. Do not silently integrate the prototype or change the API contract. |
| Retention/product decisions | Audit/idempotency retention, cleanup policy, final scope-code confirmation and future-scheduled status display remain open decisions in the review notes. | Resolve and document the decisions that affect launch acceptance and operational support. |
| Hosted smoke test | No Maintenance function is deployed; CI is disposable only. There is no known free non-production Supabase branch/project. | Do not create a paid environment. A hosted test requires an explicitly approved target and test-data plan; do not describe CI as hosted verification. |

## 3. Proposed deployment order (not authorization)

Do not start this sequence until all release blockers are closed and the user separately approves the named target and exact change set.

1. **Freeze the release candidate.** Record the exact PR commit, final migration checksum, Edge Function source revision, frontend revision, API contract and rollback commit.
2. **Database migration.** Apply only the approved final timestamped migration to the specifically authorized target, using the reviewed migration procedure. Capture preflight and postflight metadata. Stop on any unexpected object, owner, grant, policy or migration-history difference.
3. **Edge Functions.** Deploy the five reviewed function slugs from the same release candidate. Confirm JWT settings: `maintenance-status` uses `verify_jwt=false` with optional token validation in its handler; the four admin endpoints use `verify_jwt=true`.
4. **Hosted smoke tests while the feature remains off.** Verify CORS/preflight, anonymous public status response, expired/invalid token handling, non-admin denial, admin authentication, private schema non-exposure, and lifecycle operations using an approved test-data plan. Confirm internal notes and audit/idempotency records are not returned through public paths.
5. **Frontend.** Publish the feature-gated frontend only after database and Edge Function smoke tests pass. Keep `MAINTENANCE_FEATURE_ENABLED=false`; confirm the public client sends no Maintenance requests and the admin tab stays hidden.
6. **Separate launch approval.** Enable the feature flag only after the user reviews the evidence and explicitly approves activation. Flag activation is a separate release action, not part of migration deployment.

If there is no safe, no-cost hosted test target, stop after disposable CI and report hosted validation as unavailable. Do not substitute production for staging without explicit approval.

## 4. Preflight and postflight checklist

### Before any approved deployment

- [ ] Production schema-only baseline and migration-history reconciliation completed and independently reviewed.
- [ ] Exact final timestamped migration is generated from the approved source and CI tests that exact file.
- [ ] Fresh disposable PostgreSQL 17 replay and both relevant migration-order tests pass.
- [ ] GoTrue-issued JWT + PostgREST, RLS/RPC, rollback injection, Deno, browser compatibility and static guardrails pass.
- [ ] The target project, environment and intended release commit are written in the approval request.
- [ ] Pre-change schema metadata and an appropriate recovery point/backup availability are verified; do not assume backup/PITR entitlement.
- [ ] Dashboard confirms `private` is not exposed; exposed public RPC list is reviewed.
- [ ] Edge Function configuration, CORS origin and JWT verification settings are confirmed without disclosing secrets.
- [ ] Test accounts and disposable test records are approved; no real member data is used.
- [ ] Monitoring owner, observation window, stop conditions and contact path are defined.
- [ ] User separately approves the exact database/Edge/frontend operations.

### After deployment, before enabling the flag

- [ ] All six private tables exist with expected owners, RLS enabled and FORCE RLS enabled.
- [ ] Five RPC signatures, function owners, SECURITY modes, search paths and EXECUTE ACLs match the reviewed matrix.
- [ ] `private` is still absent from Data API Exposed schemas.
- [ ] Five Edge Functions are deployed and their gateway/JWT/CORS behavior matches configuration.
- [ ] Public status response contains only intended public fields.
- [ ] Anonymous and non-admin requests cannot use admin RPC paths.
- [ ] Admin list/create/update/schedule/cancel/complete flows pass with a real test admin JWT.
- [ ] Idempotency replay, key-reuse rejection, optimistic version conflict and schedule overlap checks pass.
- [ ] Taiwan UTC+8 display and pagination pass in the deployed frontend.
- [ ] No unexpected errors, privilege warnings or data exposure appear during the observation window.
- [ ] Feature flag remains off until a separate approval.

## 5. Rollback and recovery posture

**Default strategy: application rollback or forward-fix. Do not use a destructive DROP-based rollback as the normal recovery plan.**

### A. Migration fails before commit

The single-pass SQL is designed as one transaction. If a statement fails before COMMIT, stop immediately, preserve the complete error output (without secrets), and verify in the target that the transaction left no Maintenance schema/tables/RPCs behind. Do not retry blindly; investigate the exact failed precondition and compare the target to the preflight snapshot.

### B. Migration committed, but Edge Function or frontend deployment fails

- Keep `MAINTENANCE_FEATURE_ENABLED=false`.
- Do not publish/enable the Maintenance UI.
- Revert or redeploy the previously known-good Edge Function revision if a function deployment caused the failure.
- Leave the additive database objects in place while diagnosing; do not drop tables or audit records.
- Correct the deployment/configuration issue and use a forward-fix if the database itself needs adjustment.

### C. Hosted smoke test detects authorization, exposure or data-integrity failure

- Keep or set the feature flag to false (only after separate authorization for that operation).
- Stop Maintenance writes and further rollout.
- Preserve relevant logs and request IDs without copying tokens or personal data into the report.
- Do not broaden grants or expose `private` as an emergency workaround.
- Prepare a reviewed forward-fix migration and repeat the full disposable CI matrix before another deployment attempt.

### D. Frontend regression after launch

- Roll back the frontend to the last known-good GitHub Pages revision or restore the feature flag to false, according to the separately approved release procedure.
- Keep the database schema and audit history intact.
- If Edge Functions are implicated, redeploy the recorded last known-good function revision.
- Verify the old website works and Maintenance requests are no longer issued.

### E. Data corruption or suspected unauthorized access

- Stop Maintenance writes and keep the feature disabled.
- Preserve logs and the current database state for investigation.
- Check which backup/PITR recovery options are actually available on the account at that time; do not assume availability or create a paid resource.
- Any restore, point-in-time recovery, destructive SQL or data repair requires a separate explicit approval and a documented impact assessment.

### Prohibited automatic rollback actions

- No automatic `DROP SCHEMA private CASCADE`.
- No deleting audit logs or idempotency rows to make a failed release appear clean.
- No migration-history repair or fabricated ledger rows.
- No broad grants, RLS bypass, `service_role` substitution or Data API exposure changes as a workaround.
- No production retry loop after an unexpected failure.

## 6. Current status and next work

- [x] Latest PR #34 CI run 45598357283 passed 4/4 jobs, including both Maintenance/Growth migration-order permutations.
- [x] PR #34 remains Draft and unmerged.
- [x] Production has not been changed; no Maintenance migration or Edge Function has been deployed.
- [ ] Complete full production schema-only baseline capture/reconciliation.
- [ ] Decide the final migration-history path and produce the final timestamped migration.
- [ ] Close rate-limit, retention and remaining product decisions.
- [ ] Re-run CI against the final migration artifact.
- [ ] Obtain separate approval before any hosted or production action.

**This document is a release proposal, not an authorization to deploy.** No production SQL, migration repair, Edge Function deployment, feature-flag change, PR merge or paid resource is authorized by this plan.
