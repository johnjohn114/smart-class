# Smart Class Maintenance — Phase 1 closeout and Phase 2 worklist

Date: 2026-11-22

## Purpose

Record the verified first-stage status and the remaining non-security work for the Maintenance feature. This is a planning document only. It does not authorize SQL execution, migration-history edits, deployment, feature-flag changes, PR retargeting, or merging.

## Phase 1 — completed items

- [x] Maintenance admin UI and lifecycle implementation are present in the integration work carried by PR #31/#34.
- [x] Public maintenance client and admin UI remain feature-gated; `MAINTENANCE_FEATURE_ENABLED` remains `false`.
- [x] Browser compatibility coverage exercises the page shell, default-off feature gate, public banner, admin create/edit/schedule/complete/cancel flows, pagination, and Taiwan UTC+8 conversion.
- [x] Isolated PostgreSQL tests exercise the single-pass development SQL draft.
- [x] GoTrue-issued JWT + PostgREST integration tests cover both the existing ordered two-migration path and the single-pass draft path in disposable CI services.
- [x] Deno validation/type checks, feature-gate tests, Playwright checks, and SQL static guardrails are included in CI.
- [x] GitHub Actions run #271 completed successfully with 4/4 jobs green: https://github.com/johnjohn114/smart-class/actions/runs/44998262133
- [x] API specification, Edge Function development specification, SQL compatibility audit, and migration planning/closeout notes have been updated in the working branch.
- [x] No production SQL or migration was executed; no Edge Function was deployed; no production data or feature flag was changed.

### Phase 1 limitations

- CI uses disposable PostgreSQL, GoTrue, and PostgREST services. It is not a hosted production Supabase test.
- Browser lifecycle tests use an in-memory API mock. They do not prove hosted Edge Runtime behavior.
- The successful CI run does not establish production readiness or authorize release.

## Phase 2 — remaining work, in order

### 1. Resolve migration/environment history

- [ ] Confirm whether any local, manually managed, preview, staging, or shared database has ever applied either timestamped Maintenance migration.
- [ ] Record the exact environments checked and the evidence for each.
- [ ] Keep the user's earlier recollection ("probably not applied") marked as unverified until explicitly confirmed.
- [ ] Only after evidence is complete, choose between a clean-bootstrap/squash approach for environments confirmed clean or a forward-upgrade approach for any environment that has already applied the old migrations.
- [ ] Do not rename, delete, reorder, replace, or apply migrations before this decision.

### 2. Confirm deployment prerequisites (operational scope only)

- [ ] Confirm the intended Data API exposed-schema configuration for the Maintenance private schema/RPC arrangement.
- [ ] Confirm the allowed website origin/CORS settings.
- [ ] Confirm the required Edge Function environment variables and how they will be supplied without exposing secrets.
- [ ] Document the deployment order for database objects, Edge Functions, and the frontend.
- [ ] Keep permission/RLS/security hardening review out of this phase; it remains scheduled for January 2027.

### 3. Plan a no-cost pre-release validation path

- [ ] Prefer existing free CI and disposable local tooling; do not create paid Supabase branches or paid services.
- [ ] If a non-production hosted environment is available at no cost, obtain explicit approval before deploying anything to it.
- [ ] After separately authorized deployment, run hosted smoke tests for public status, admin authentication/authorization, create/update/schedule/cancel/complete, pagination, idempotent retries, and Taiwan UTC+8 display.
- [ ] Record results and distinguish hosted tests from disposable CI results.

### 4. Prepare release and rollback proposal

- [ ] Write a deployment checklist and a forward-fix/application rollback plan based on the confirmed target schema.
- [ ] Keep the feature flag off until the user separately approves production readiness and release.
- [ ] Present the final diff, migration plan, test evidence, risks, and rollback plan for approval before any production action.

## Explicitly deferred

- January 2027 security review and any new security hardening scope.
- PR #31 merge or modification; it contains security-related changes and must remain unmerged pending the scheduled review.
- PR #34 merge or retargeting; it is stacked on PR #31 and remains Draft.
- Production SQL/migrations, Edge Function deployment, feature-flag enablement, and website release.

## Current disposition

**Phase 1 documentation and CI closeout: complete.**

**Phase 2: not started; migration/environment history is the first blocking decision.**

No production readiness claim is made. No production changes are authorized by this document.

## Source note

The uploaded file `啟動第一步檢查.txt` records an earlier SQL review snapshot describing a four-table design and service-role grants. The current Maintenance implementation has since evolved to a private-schema design with six tables, five RPCs, and Edge Function wrappers. Use the current API v0.7, Edge Function development specification, SQL compatibility audit, and current single-pass migration plan as the working references; do not treat the earlier snapshot as the current schema specification.
