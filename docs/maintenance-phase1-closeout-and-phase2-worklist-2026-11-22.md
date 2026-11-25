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

**Phase 2: in progress.** 使用者已明確確認沒有在其他 local/test/preview/staging/shared database 執行 Maintenance migrations；正式 production 的 migration ledger/schema baseline 仍未完成核對，故仍阻擋 migration history 改寫與正式部署。

No production readiness claim is made. No production changes are authorized by this document.

## Source note

The uploaded file `啟動第一步檢查.txt` records an earlier SQL review snapshot describing a four-table design and service-role grants. The current Maintenance implementation has since evolved to a private-schema design with six tables, five RPCs, and Edge Function wrappers. Use the current API v0.7, Edge Function development specification, SQL compatibility audit, and current single-pass migration plan as the working references; do not treat the earlier snapshot as the current schema specification.


## 2026-11-22 使用者環境確認補記

使用者已明確回答「無」：沒有在其他 local、test、preview、staging 或 shared database 執行過 Maintenance migrations。此回答更新本文件較早「未確認」的使用者回憶狀態。CI PostgreSQL/GoTrue/PostgREST 服務為 disposable 測試環境，不視為持續存在的使用者資料庫。

仍須區分：此回答不等同 production migration ledger 已修復。正式 Supabase 的 migration history/schema baseline 仍有獨立缺口；production catalog 未見 Maintenance objects 不能替代完整 baseline reconciliation。因此 timestamped migrations 先保持不動，不執行 production SQL、migration repair、Edge Function deploy、feature flag change 或 PR merge。


## 2026-11-23 Operational preflight audit

This is a read-only repository and project inventory update. It does not authorize deployment or any production change.

### Verified

- [x] Supabase project `private-website` is `ACTIVE_HEALTHY`, PostgreSQL 17.11, region `ap-northeast-1`.
- [x] Supabase currently lists no development branches.
- [x] Supabase currently lists no Maintenance Edge Functions. The five Maintenance functions remain repository-only; no hosted endpoint has been deployed.
- [x] Supabase migration listing remains empty. This is not a substitute for a reconstructed production migration baseline.
- [x] Repository config sets `maintenance-status` to `verify_jwt = false`; all four admin endpoints use `verify_jwt = true`.
- [x] Shared handler defaults CORS to the exact GitHub Pages origin `https://johnjohn114.github.io`; `MAINTENANCE_ALLOWED_ORIGINS` can explicitly override it with a comma-separated allowlist.
- [x] Deno tests cover the default allowed preflight origin and rejection of an unapproved origin.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key (prefers `SUPABASE_PUBLISHABLE_KEY`, with documented fallbacks). Secret values were not read, requested, or recorded.
- [x] A read-only SQL check of `current_setting('pgrst.db_schemas', true)` returned NULL; this does not reveal the hosted Data API Exposed schemas configuration.

### Still unverified / blocked

- [ ] Confirm the actual Data API Exposed schemas setting in the Supabase project configuration. The private Maintenance schema must remain unexposed; the required public RPC arrangement must be confirmed against the final SQL design.
- [ ] Confirm the deployed Edge Function environment contains the required built-in Supabase URL/key variables. Do not copy secret values into GitHub, chat, or documentation.
- [ ] Confirm the actual hosted CORS override, if any. The repository default is verified, but no Maintenance function is deployed to exercise hosted CORS.
- [ ] Run hosted-runtime smoke tests only after a separately approved non-production or production deployment. No free hosted non-production branch currently exists, and no paid branch/service will be created.

### Proposed release sequence (not authorization)

1. Reconcile the production migration baseline and finalize the exact timestamped migration source.
2. Apply the approved database migration to the specifically authorized target.
3. Deploy the five Edge Functions with the verified environment configuration.
4. Run hosted smoke tests for public status, admin authentication/authorization, lifecycle actions, pagination, idempotent retries, CORS, and Taiwan UTC+8 display.
5. Only after separate approval, integrate the frontend and consider enabling the feature flag. Keep `MAINTENANCE_FEATURE_ENABLED=false` until then.

No production SQL, migration repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used during this audit.


## 2026-11-23 Combined operational confirmation — results

This section records the requested combined read-only checks. No production configuration was changed.

### Confirmed from repository and Supabase project inventory

- [x] Repository `supabase/config.toml` defines five Maintenance Edge Functions:
  - `maintenance-status`: `verify_jwt = false` because the handler performs optional user-token validation itself.
  - `maintenance-admin-list`, `maintenance-event-create`, `maintenance-event-update`, `maintenance-event-action`: `verify_jwt = true`.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key. It prefers `SUPABASE_PUBLISHABLE_KEY`, with `SUPABASE_ANON_KEY` and JSON `SUPABASE_PUBLISHABLE_KEYS.default` fallbacks. These are read at runtime; no credential values were accessed or recorded.
- [x] CORS allowlist defaults to exactly `https://johnjohn114.github.io`. Optional `MAINTENANCE_ALLOWED_ORIGINS` overrides it as a comma-separated list. Automated tests verify allowed preflight and rejection of an unapproved origin.
- [x] Supabase inventory currently lists six Edge Functions, none of which is a Maintenance function.
- [x] Supabase inventory lists zero development branches and zero migrations.
- [x] Current production schema inventory contains no `private` schema. The role grants query only confirms `public` schema usage for API roles; it does not prove the Data API Exposed schemas setting.
- [x] Read-only `pg_db_role_setting` inspection found no `pgrst.db_schemas` setting on `authenticator`, `anon`, `authenticated`, or `service_role`. This is not authoritative evidence of the dashboard-level Data API Exposed schemas configuration.

### Explicit unresolved items

- [ ] The actual Supabase Dashboard setting under Data API → Exposed schemas cannot be read through the available project/database tools. It must be visually confirmed before any deployment. Expected target: keep `private` out of Exposed schemas; only expose `public` RPC wrappers if the final SQL architecture requires them.
- [ ] Actual deployed Edge Function environment configuration cannot be confirmed because the Maintenance functions are not deployed. At deployment time, verify built-in `SUPABASE_URL` and publishable/anon key availability; if overriding CORS, configure `MAINTENANCE_ALLOWED_ORIGINS=https://johnjohn114.github.io`. Do not paste or store secret values in source control.
- [ ] Hosted CORS cannot be smoke-tested until a Maintenance function is deployed to an explicitly authorized target.

### Current decision

Operational code-side prerequisites are documented and internally consistent. Dashboard Exposed schemas and hosted environment values remain unverified, so deployment remains blocked. No production SQL, migration, dashboard configuration, Edge Function deployment, feature-flag change, PR merge, or paid resource was used.


## 2026-11-23 Dashboard screenshot confirmation — Data API schemas

The user supplied a Supabase Dashboard → Integrations → Data API → Settings screenshot.

### Visually confirmed

- Exposed schemas shows `2 of 2 schemas exposed`.
- The only selected schemas shown are `graphql_public` and `public`.
- `private` is not in the exposed schema selection.
- Exposed functions shows `35 of 38 functions exposed`; the screenshot does not identify which three functions are disabled.
- “Automatically expose new tables” appears enabled (green toggle) in the screenshot. This setting should be reviewed before creating future tables; do not change it as part of this read-only audit.

### Impact on Maintenance release

- The screenshot confirms that `private` is not currently exposed through the Data API.
- It does not establish that the `private` schema already exists; the current database schema inventory did not list it.
- After the approved migration creates `private`, keep it out of Exposed schemas.
- Confirm which three existing functions are not exposed and verify the final five Maintenance RPC entry points against the intended API design before release. No Maintenance functions are currently deployed.
- No Dashboard setting was changed based on this screenshot.

This screenshot resolves the previously outstanding visual confirmation for the current Exposed schemas selection. Hosted function configuration and deployment smoke tests remain outstanding.


### Exposed functions — user supplied expanded-list screenshot and clarification

The three unchecked functions are identified as:

1. `public.assign_member_no_and_nickname()`
2. `public.award_growth_points(uuid,integer,text,text,text,text,uuid)`
3. `public.is_admin()`

Assessment against the current authorization design:

- Keep all three unchecked in Data API → Exposed functions.
- `assign_member_no_and_nickname()` is a trigger/internal helper and should not be callable as a public RPC.
- `award_growth_points(...)` is an internal point-awarding function. The authorization migration explicitly denies direct EXECUTE to anon and authenticated; it must not be exposed as an RPC.
- `is_admin()` is a SECURITY DEFINER authorization helper. It is used internally by RLS policies and Maintenance RPCs; the single-pass Maintenance SQL draft grants EXECUTE to `pg_database_owner` so the admin RPC owner can call it. This database EXECUTE grant does not require exposing `is_admin()` as a Data API RPC endpoint. Keep it unchecked in the Exposed functions list.
- The Dashboard exposure toggle and PostgreSQL EXECUTE ACL are separate controls. Do not enable a function in the Data API merely to satisfy an internal SQL EXECUTE dependency.

The screenshot therefore shows a suitable exposure posture for these three functions. This does not substitute for validating the full final function ACL matrix or applying the migration to an approved target.


## 2026-11-23 Review — Automatically expose new tables

The user agreed to review the Dashboard setting. This review was read-only; the toggle was not changed.

### Dashboard observation

- Screenshot shows “Automatically expose new tables” enabled.
- Dashboard text says it grants Data API role privileges to new tables by default.
- The Maintenance SQL draft creates its six tables under the separate `private` schema, not `public`.
- The confirmed exposed schema selection is only `public` and `graphql_public`; `private` is not exposed.

### Production catalog cross-check (read-only)

- Current production `pg_default_acl` contains explicit `postgres` defaults for tables, sequences and functions in `public` and `storage`; there is no global `postgres` default ACL row and no `private` schema default ACL.
- The `postgres` table default ACL for `public` currently grants broad table privileges to `anon`, `authenticated` and `service_role`. This is relevant to future tables created in `public`; it is not evidence that the Maintenance tables in `private` will be exposed.
- Existing default ACLs owned by Supabase-managed roles were not changed or recommended for modification.

### Maintenance draft review

- The draft explicitly creates `private`, keeps it out of the Data API exposed schema list, enables and FORCEs RLS on all six tables, and applies explicit table grants/policies.
- The draft revokes table privileges from `PUBLIC`, `anon` and `authenticated` before applying the narrow read/write grants. It does not include `service_role` in that table-level REVOKE statement; this should remain a focused ACL assertion in isolated tests before release.
- The dashboard auto-expose toggle is not a substitute for explicit PostgreSQL grants, RLS, and keeping `private` out of Exposed schemas.

### Recommendation and decision

- Recommended hardening: disable “Automatically expose new tables” to prevent accidental Data API grants when future tables are created in exposed schemas, then explicitly grant only the required roles for each new public table.
- This is a preventive project-wide workflow change, not a prerequisite for the current Maintenance draft because its tables are created in the unexposed `private` schema with explicit ACL/RLS design.
- Do not change the Dashboard toggle without separate explicit confirmation. No settings, grants, schemas, tables, or production data were changed during this review.

## 2026-11-24 CI rerun and backend contract review

This is a development-branch documentation update based on the current PR head. It does not authorize production changes.

### Latest CI evidence

- [x] GitHub Actions run #393 / run ID 45159850371 completed successfully: 4/4 jobs passed.
- [x] GoTrue-issued JWT + PostgREST integration for the single-pass draft passed, including the hosted-style non-superuser database-owner path, rollback after injected failure, and Deno Edge handler integration through disposable Auth/REST services.
- [x] Isolated PostgreSQL RPC/RLS tests passed, including growth-function authorization regressions, default-privilege/trigger regressions, sequential integration and PostgREST JWT/RLS/concurrency checks.
- [x] Legacy GoTrue/PostgREST compatibility path passed.
- [x] Deno type checks, request validation, feature gate, Playwright compatibility and SQL static guardrails passed.

These are disposable CI services. The Deno.serve harness is not a deployment test of Supabase's hosted Edge Runtime or gateway.

### Backend operation contract review

The current implementation remains aligned to API v0.7 and the single-pass SQL draft:

1. Edge handler checks origin, HTTP method, request shape and body size.
2. Admin endpoints validate the supplied bearer token with Supabase Auth; the original user JWT is forwarded to PostgREST.
3. Each endpoint calls only its matching RPC with one `p_request jsonb` argument.
4. Database RPC re-checks the JWT subject and `public.is_admin()`; client-supplied actor/role fields are not accepted.
5. Create/update/action operations keep event changes, scope links, audit snapshots and idempotency result in one database transaction.
6. Optimistic `expected_version` checks and transaction-scoped advisory locking protect concurrent lifecycle changes and overlap checks.
7. Public status returns a restricted response shape; private notes and audit details are only returned by the admin listing path.

### Documentation precedence clarification

The historical Edge Functions development spec contains earlier design text referring to `maintenance_rpc_executor` and older SECURITY INVOKER assumptions. Those passages are historical only. The current single-pass SQL draft and API v0.7 govern the present branch: admin RPCs are SECURITY DEFINER owned by built-in `pg_database_owner`; public status is SECURITY INVOKER. Do not revive the historical executor role design.

### Remaining release blockers

- [ ] Production migration/schema baseline reconciliation remains unresolved. Production migration listing is empty and the environment has no verified complete baseline; do not repair or rewrite migration history by guesswork.
- [ ] No hosted free non-production Supabase branch is available; do not create paid resources.
- [ ] Actual deployed Edge Function environment and hosted CORS cannot be verified because Maintenance functions are not deployed.
- [ ] Supabase hosted Edge Runtime smoke tests remain a post-approval pre-release task.
- [ ] Keep PR #34 Draft/unmerged, Maintenance feature flag false, and production unchanged pending separate explicit approval.

No production SQL, migration repair, deployment, feature-flag change, PR merge, dashboard setting change or paid service was used for this review.

## 2026-11-24 production migration baseline read-only audit

### Production facts confirmed by Supabase read-only tools

- PostgreSQL version: 17.11.
- Non-system schemas currently present: `auth`, `extensions`, `graphql`, `graphql_public`, `public`, `realtime`, `storage`, `vault`.
- `public` currently contains 44 tables; all non-system schemas together contain 85 tables.
- The `private` schema does not currently exist.
- Supabase migration listing returns an empty array.
- The `supabase_migrations` schema does not exist, and therefore `supabase_migrations.schema_migrations` does not exist.
- No schema or migration-history object was created or changed by this audit.

### Repository migration inventory

The current development branch contains seven files under `supabase/migrations/`:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
7. `26.11.3_calendar_fields.sql`

The two app-releases files appear to be competing/overlapping migration entries and require a content-level reconciliation. The directory also mixes timestamp conventions. Do not reorder, rename, delete, or apply any of these files until their actual production effects are established.

### Maintenance migration track conflict

- The historical initial Maintenance migration describes SECURITY INVOKER/RLS and preconditions based on the earlier design.
- The historical least-privilege upgrade explicitly creates and uses `maintenance_rpc_executor`.
- The current PR #34 single-pass track instead uses the built-in `pg_database_owner` model and supersedes the earlier executor-role approach.
- Production currently has no `private` schema, so the current Maintenance schema has not been installed there. This does not establish whether any unrelated SQL files were previously run manually.

### Baseline decision

The production database is populated but has no readable Supabase migration ledger. Repository files alone cannot establish which SQL changes were manually applied or whether every file matches the live schema. A full, schema-only, reviewed export and object-by-object reconciliation are required before declaring a baseline.

The current tool environment does not provide a verified complete `pg_dump`/Supabase CLI export path. Do not simulate a dump from partial catalog queries. Do not create `supabase_migrations`, insert fabricated history rows, use `migration repair`, run `db push`, or apply any historical Maintenance migration as a shortcut.

### Next safe actions

1. Obtain a complete schema-only export through an approved read-only export path (or a local CLI/pg_dump environment with the required tools), without exporting production data or secrets.
2. Compare the export against all seven repository migration files and the current single-pass Maintenance draft.
3. Resolve duplicate/overlapping app-releases migration content and timestamp conventions in a separate development-only change.
4. Produce a reviewed baseline plan and isolated replay proof before any separately approved production operation.

No production DDL/DML, migration-history repair, data export, deployment, PR merge, feature-flag change, dashboard setting change, or paid service was used in this audit.

## 2026-11-24 App Releases migration content comparison

### Files compared

- `supabase/migrations/202610310001_app_releases.sql`
- `supabase/migrations/20261031_app_releases.sql`

These are not duplicate copies. They describe materially different schemas and authorization designs.

### First file: matches the observed production table shape

The first file defines `version_code` as UNIQUE, `published` default false, nullable `published_at`, and nullable `created_by` referencing `auth.users`. Its policies use direct `profiles.role = 'admin'` checks and it does not define `is_app_release_admin()`.

A read-only production catalog inspection found the same nine columns, matching defaults/nullability, a unique `version_code` index, and the five policy names/operations from this file. This is evidence of schema/content alignment, not proof of which SQL file was executed or when.

### Second file: incompatible with the observed production table

The second file adds `is_latest` to its index definition, but its own `CREATE TABLE IF NOT EXISTS` does not add that column to an already-existing table. The observed production table has no `is_latest` column. Therefore, applying this file against the observed production table would fail at the `app_releases_published_idx` creation step.

It also differs in defaults/nullability, omits `created_by`, omits a UNIQUE constraint on `version_code`, adds an HTTPS check, and defines a SECURITY DEFINER helper `is_app_release_admin()`. The helper is absent in the observed production catalog. These differences are not safe to reconcile by simply running both files.

### Additional live ACL finding

The read-only catalog query showed `anon` currently has table-level INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER grants on `public.app_releases`, in addition to SELECT. Current RLS policies do not define anon write policies, which currently blocks ordinary anon writes through RLS, but the broad table grants are unnecessary and should be reviewed as a separate least-privilege hardening item. Do not change production ACLs as part of this documentation-only task.

### Frontend compatibility

The current admin frontend writes `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_by`; it validates HTTPS URLs client-side. The public release center reads `id`, `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_at`. Neither current frontend file references `is_latest` or `is_app_release_admin()`.

### Decision

- Do not apply either App Releases SQL file to production during baseline reconciliation.
- Preserve both files for now; no rename/delete/reorder was made.
- Treat `202610310001_app_releases.sql` as the closer structural match to the observed live schema, but do not claim it is proven execution history.
- Keep the second file flagged as incompatible with the current live schema unless a separately reviewed migration is designed from verified requirements.
- Create a development-only follow-up to review and tighten the unnecessary `anon` table privileges, with isolated regression tests before any production approval.

This comparison used GitHub source reads, frontend source reads, and read-only production catalog queries only. No production SQL, data changes, deployment, PR merge, or paid service was used.

## 2026-11-24 App Releases anon ACL hardening candidate

### Live privilege confirmation

A second read-only production catalog check confirmed the effective `anon` privileges on `public.app_releases` are currently SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER. No anon column-level grants or role memberships were found. This supports a table-level least-privilege revoke without changing the published-release SELECT path.

### Candidate SQL

Added `supabase/candidate_sql/app_releases_anon_acl_hardening.sql`:

- Revoke INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER from `anon`.
- Preserve SELECT for the public release center.
- Do not change authenticated or service_role grants.
- Candidate only; not applied to production.

### Disposable regression test

Added `supabase/tests/sql/app-releases-anon-acl.test.sql` and wired it into the existing isolated PostgreSQL job in `.github/workflows/maintenance-edge-functions.yml`.

The test reproduces the observed broad grants, applies only the candidate SQL in a disposable database, verifies anon retains SELECT but loses all six unnecessary privileges, checks only published rows are visible, and confirms authenticated table grants remain unchanged.

### CI correction note

The first test attempt exposed a quoting error in the test-only `auth.uid()` fixture (dollar-quote delimiter was malformed). This was a test harness issue, not a production SQL issue. The fixture was corrected to use a named dollar-quote delimiter (`$body# Smart Class Maintenance — Phase 1 closeout and Phase 2 worklist

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

**Phase 2: in progress.** 使用者已明確確認沒有在其他 local/test/preview/staging/shared database 執行 Maintenance migrations；正式 production 的 migration ledger/schema baseline 仍未完成核對，故仍阻擋 migration history 改寫與正式部署。

No production readiness claim is made. No production changes are authorized by this document.

## Source note

The uploaded file `啟動第一步檢查.txt` records an earlier SQL review snapshot describing a four-table design and service-role grants. The current Maintenance implementation has since evolved to a private-schema design with six tables, five RPCs, and Edge Function wrappers. Use the current API v0.7, Edge Function development specification, SQL compatibility audit, and current single-pass migration plan as the working references; do not treat the earlier snapshot as the current schema specification.


## 2026-11-22 使用者環境確認補記

使用者已明確回答「無」：沒有在其他 local、test、preview、staging 或 shared database 執行過 Maintenance migrations。此回答更新本文件較早「未確認」的使用者回憶狀態。CI PostgreSQL/GoTrue/PostgREST 服務為 disposable 測試環境，不視為持續存在的使用者資料庫。

仍須區分：此回答不等同 production migration ledger 已修復。正式 Supabase 的 migration history/schema baseline 仍有獨立缺口；production catalog 未見 Maintenance objects 不能替代完整 baseline reconciliation。因此 timestamped migrations 先保持不動，不執行 production SQL、migration repair、Edge Function deploy、feature flag change 或 PR merge。


## 2026-11-23 Operational preflight audit

This is a read-only repository and project inventory update. It does not authorize deployment or any production change.

### Verified

- [x] Supabase project `private-website` is `ACTIVE_HEALTHY`, PostgreSQL 17.11, region `ap-northeast-1`.
- [x] Supabase currently lists no development branches.
- [x] Supabase currently lists no Maintenance Edge Functions. The five Maintenance functions remain repository-only; no hosted endpoint has been deployed.
- [x] Supabase migration listing remains empty. This is not a substitute for a reconstructed production migration baseline.
- [x] Repository config sets `maintenance-status` to `verify_jwt = false`; all four admin endpoints use `verify_jwt = true`.
- [x] Shared handler defaults CORS to the exact GitHub Pages origin `https://johnjohn114.github.io`; `MAINTENANCE_ALLOWED_ORIGINS` can explicitly override it with a comma-separated allowlist.
- [x] Deno tests cover the default allowed preflight origin and rejection of an unapproved origin.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key (prefers `SUPABASE_PUBLISHABLE_KEY`, with documented fallbacks). Secret values were not read, requested, or recorded.
- [x] A read-only SQL check of `current_setting('pgrst.db_schemas', true)` returned NULL; this does not reveal the hosted Data API Exposed schemas configuration.

### Still unverified / blocked

- [ ] Confirm the actual Data API Exposed schemas setting in the Supabase project configuration. The private Maintenance schema must remain unexposed; the required public RPC arrangement must be confirmed against the final SQL design.
- [ ] Confirm the deployed Edge Function environment contains the required built-in Supabase URL/key variables. Do not copy secret values into GitHub, chat, or documentation.
- [ ] Confirm the actual hosted CORS override, if any. The repository default is verified, but no Maintenance function is deployed to exercise hosted CORS.
- [ ] Run hosted-runtime smoke tests only after a separately approved non-production or production deployment. No free hosted non-production branch currently exists, and no paid branch/service will be created.

### Proposed release sequence (not authorization)

1. Reconcile the production migration baseline and finalize the exact timestamped migration source.
2. Apply the approved database migration to the specifically authorized target.
3. Deploy the five Edge Functions with the verified environment configuration.
4. Run hosted smoke tests for public status, admin authentication/authorization, lifecycle actions, pagination, idempotent retries, CORS, and Taiwan UTC+8 display.
5. Only after separate approval, integrate the frontend and consider enabling the feature flag. Keep `MAINTENANCE_FEATURE_ENABLED=false` until then.

No production SQL, migration repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used during this audit.


## 2026-11-23 Combined operational confirmation — results

This section records the requested combined read-only checks. No production configuration was changed.

### Confirmed from repository and Supabase project inventory

- [x] Repository `supabase/config.toml` defines five Maintenance Edge Functions:
  - `maintenance-status`: `verify_jwt = false` because the handler performs optional user-token validation itself.
  - `maintenance-admin-list`, `maintenance-event-create`, `maintenance-event-update`, `maintenance-event-action`: `verify_jwt = true`.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key. It prefers `SUPABASE_PUBLISHABLE_KEY`, with `SUPABASE_ANON_KEY` and JSON `SUPABASE_PUBLISHABLE_KEYS.default` fallbacks. These are read at runtime; no credential values were accessed or recorded.
- [x] CORS allowlist defaults to exactly `https://johnjohn114.github.io`. Optional `MAINTENANCE_ALLOWED_ORIGINS` overrides it as a comma-separated list. Automated tests verify allowed preflight and rejection of an unapproved origin.
- [x] Supabase inventory currently lists six Edge Functions, none of which is a Maintenance function.
- [x] Supabase inventory lists zero development branches and zero migrations.
- [x] Current production schema inventory contains no `private` schema. The role grants query only confirms `public` schema usage for API roles; it does not prove the Data API Exposed schemas setting.
- [x] Read-only `pg_db_role_setting` inspection found no `pgrst.db_schemas` setting on `authenticator`, `anon`, `authenticated`, or `service_role`. This is not authoritative evidence of the dashboard-level Data API Exposed schemas configuration.

### Explicit unresolved items

- [ ] The actual Supabase Dashboard setting under Data API → Exposed schemas cannot be read through the available project/database tools. It must be visually confirmed before any deployment. Expected target: keep `private` out of Exposed schemas; only expose `public` RPC wrappers if the final SQL architecture requires them.
- [ ] Actual deployed Edge Function environment configuration cannot be confirmed because the Maintenance functions are not deployed. At deployment time, verify built-in `SUPABASE_URL` and publishable/anon key availability; if overriding CORS, configure `MAINTENANCE_ALLOWED_ORIGINS=https://johnjohn114.github.io`. Do not paste or store secret values in source control.
- [ ] Hosted CORS cannot be smoke-tested until a Maintenance function is deployed to an explicitly authorized target.

### Current decision

Operational code-side prerequisites are documented and internally consistent. Dashboard Exposed schemas and hosted environment values remain unverified, so deployment remains blocked. No production SQL, migration, dashboard configuration, Edge Function deployment, feature-flag change, PR merge, or paid resource was used.


## 2026-11-23 Dashboard screenshot confirmation — Data API schemas

The user supplied a Supabase Dashboard → Integrations → Data API → Settings screenshot.

### Visually confirmed

- Exposed schemas shows `2 of 2 schemas exposed`.
- The only selected schemas shown are `graphql_public` and `public`.
- `private` is not in the exposed schema selection.
- Exposed functions shows `35 of 38 functions exposed`; the screenshot does not identify which three functions are disabled.
- “Automatically expose new tables” appears enabled (green toggle) in the screenshot. This setting should be reviewed before creating future tables; do not change it as part of this read-only audit.

### Impact on Maintenance release

- The screenshot confirms that `private` is not currently exposed through the Data API.
- It does not establish that the `private` schema already exists; the current database schema inventory did not list it.
- After the approved migration creates `private`, keep it out of Exposed schemas.
- Confirm which three existing functions are not exposed and verify the final five Maintenance RPC entry points against the intended API design before release. No Maintenance functions are currently deployed.
- No Dashboard setting was changed based on this screenshot.

This screenshot resolves the previously outstanding visual confirmation for the current Exposed schemas selection. Hosted function configuration and deployment smoke tests remain outstanding.


### Exposed functions — user supplied expanded-list screenshot and clarification

The three unchecked functions are identified as:

1. `public.assign_member_no_and_nickname()`
2. `public.award_growth_points(uuid,integer,text,text,text,text,uuid)`
3. `public.is_admin()`

Assessment against the current authorization design:

- Keep all three unchecked in Data API → Exposed functions.
- `assign_member_no_and_nickname()` is a trigger/internal helper and should not be callable as a public RPC.
- `award_growth_points(...)` is an internal point-awarding function. The authorization migration explicitly denies direct EXECUTE to anon and authenticated; it must not be exposed as an RPC.
- `is_admin()` is a SECURITY DEFINER authorization helper. It is used internally by RLS policies and Maintenance RPCs; the single-pass Maintenance SQL draft grants EXECUTE to `pg_database_owner` so the admin RPC owner can call it. This database EXECUTE grant does not require exposing `is_admin()` as a Data API RPC endpoint. Keep it unchecked in the Exposed functions list.
- The Dashboard exposure toggle and PostgreSQL EXECUTE ACL are separate controls. Do not enable a function in the Data API merely to satisfy an internal SQL EXECUTE dependency.

The screenshot therefore shows a suitable exposure posture for these three functions. This does not substitute for validating the full final function ACL matrix or applying the migration to an approved target.


## 2026-11-23 Review — Automatically expose new tables

The user agreed to review the Dashboard setting. This review was read-only; the toggle was not changed.

### Dashboard observation

- Screenshot shows “Automatically expose new tables” enabled.
- Dashboard text says it grants Data API role privileges to new tables by default.
- The Maintenance SQL draft creates its six tables under the separate `private` schema, not `public`.
- The confirmed exposed schema selection is only `public` and `graphql_public`; `private` is not exposed.

### Production catalog cross-check (read-only)

- Current production `pg_default_acl` contains explicit `postgres` defaults for tables, sequences and functions in `public` and `storage`; there is no global `postgres` default ACL row and no `private` schema default ACL.
- The `postgres` table default ACL for `public` currently grants broad table privileges to `anon`, `authenticated` and `service_role`. This is relevant to future tables created in `public`; it is not evidence that the Maintenance tables in `private` will be exposed.
- Existing default ACLs owned by Supabase-managed roles were not changed or recommended for modification.

### Maintenance draft review

- The draft explicitly creates `private`, keeps it out of the Data API exposed schema list, enables and FORCEs RLS on all six tables, and applies explicit table grants/policies.
- The draft revokes table privileges from `PUBLIC`, `anon` and `authenticated` before applying the narrow read/write grants. It does not include `service_role` in that table-level REVOKE statement; this should remain a focused ACL assertion in isolated tests before release.
- The dashboard auto-expose toggle is not a substitute for explicit PostgreSQL grants, RLS, and keeping `private` out of Exposed schemas.

### Recommendation and decision

- Recommended hardening: disable “Automatically expose new tables” to prevent accidental Data API grants when future tables are created in exposed schemas, then explicitly grant only the required roles for each new public table.
- This is a preventive project-wide workflow change, not a prerequisite for the current Maintenance draft because its tables are created in the unexposed `private` schema with explicit ACL/RLS design.
- Do not change the Dashboard toggle without separate explicit confirmation. No settings, grants, schemas, tables, or production data were changed during this review.

## 2026-11-24 CI rerun and backend contract review

This is a development-branch documentation update based on the current PR head. It does not authorize production changes.

### Latest CI evidence

- [x] GitHub Actions run #393 / run ID 45159850371 completed successfully: 4/4 jobs passed.
- [x] GoTrue-issued JWT + PostgREST integration for the single-pass draft passed, including the hosted-style non-superuser database-owner path, rollback after injected failure, and Deno Edge handler integration through disposable Auth/REST services.
- [x] Isolated PostgreSQL RPC/RLS tests passed, including growth-function authorization regressions, default-privilege/trigger regressions, sequential integration and PostgREST JWT/RLS/concurrency checks.
- [x] Legacy GoTrue/PostgREST compatibility path passed.
- [x] Deno type checks, request validation, feature gate, Playwright compatibility and SQL static guardrails passed.

These are disposable CI services. The Deno.serve harness is not a deployment test of Supabase's hosted Edge Runtime or gateway.

### Backend operation contract review

The current implementation remains aligned to API v0.7 and the single-pass SQL draft:

1. Edge handler checks origin, HTTP method, request shape and body size.
2. Admin endpoints validate the supplied bearer token with Supabase Auth; the original user JWT is forwarded to PostgREST.
3. Each endpoint calls only its matching RPC with one `p_request jsonb` argument.
4. Database RPC re-checks the JWT subject and `public.is_admin()`; client-supplied actor/role fields are not accepted.
5. Create/update/action operations keep event changes, scope links, audit snapshots and idempotency result in one database transaction.
6. Optimistic `expected_version` checks and transaction-scoped advisory locking protect concurrent lifecycle changes and overlap checks.
7. Public status returns a restricted response shape; private notes and audit details are only returned by the admin listing path.

### Documentation precedence clarification

The historical Edge Functions development spec contains earlier design text referring to `maintenance_rpc_executor` and older SECURITY INVOKER assumptions. Those passages are historical only. The current single-pass SQL draft and API v0.7 govern the present branch: admin RPCs are SECURITY DEFINER owned by built-in `pg_database_owner`; public status is SECURITY INVOKER. Do not revive the historical executor role design.

### Remaining release blockers

- [ ] Production migration/schema baseline reconciliation remains unresolved. Production migration listing is empty and the environment has no verified complete baseline; do not repair or rewrite migration history by guesswork.
- [ ] No hosted free non-production Supabase branch is available; do not create paid resources.
- [ ] Actual deployed Edge Function environment and hosted CORS cannot be verified because Maintenance functions are not deployed.
- [ ] Supabase hosted Edge Runtime smoke tests remain a post-approval pre-release task.
- [ ] Keep PR #34 Draft/unmerged, Maintenance feature flag false, and production unchanged pending separate explicit approval.

No production SQL, migration repair, deployment, feature-flag change, PR merge, dashboard setting change or paid service was used for this review.

## 2026-11-24 production migration baseline read-only audit

### Production facts confirmed by Supabase read-only tools

- PostgreSQL version: 17.11.
- Non-system schemas currently present: `auth`, `extensions`, `graphql`, `graphql_public`, `public`, `realtime`, `storage`, `vault`.
- `public` currently contains 44 tables; all non-system schemas together contain 85 tables.
- The `private` schema does not currently exist.
- Supabase migration listing returns an empty array.
- The `supabase_migrations` schema does not exist, and therefore `supabase_migrations.schema_migrations` does not exist.
- No schema or migration-history object was created or changed by this audit.

### Repository migration inventory

The current development branch contains seven files under `supabase/migrations/`:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
7. `26.11.3_calendar_fields.sql`

The two app-releases files appear to be competing/overlapping migration entries and require a content-level reconciliation. The directory also mixes timestamp conventions. Do not reorder, rename, delete, or apply any of these files until their actual production effects are established.

### Maintenance migration track conflict

- The historical initial Maintenance migration describes SECURITY INVOKER/RLS and preconditions based on the earlier design.
- The historical least-privilege upgrade explicitly creates and uses `maintenance_rpc_executor`.
- The current PR #34 single-pass track instead uses the built-in `pg_database_owner` model and supersedes the earlier executor-role approach.
- Production currently has no `private` schema, so the current Maintenance schema has not been installed there. This does not establish whether any unrelated SQL files were previously run manually.

### Baseline decision

The production database is populated but has no readable Supabase migration ledger. Repository files alone cannot establish which SQL changes were manually applied or whether every file matches the live schema. A full, schema-only, reviewed export and object-by-object reconciliation are required before declaring a baseline.

The current tool environment does not provide a verified complete `pg_dump`/Supabase CLI export path. Do not simulate a dump from partial catalog queries. Do not create `supabase_migrations`, insert fabricated history rows, use `migration repair`, run `db push`, or apply any historical Maintenance migration as a shortcut.

### Next safe actions

1. Obtain a complete schema-only export through an approved read-only export path (or a local CLI/pg_dump environment with the required tools), without exporting production data or secrets.
2. Compare the export against all seven repository migration files and the current single-pass Maintenance draft.
3. Resolve duplicate/overlapping app-releases migration content and timestamp conventions in a separate development-only change.
4. Produce a reviewed baseline plan and isolated replay proof before any separately approved production operation.

No production DDL/DML, migration-history repair, data export, deployment, PR merge, feature-flag change, dashboard setting change, or paid service was used in this audit.

## 2026-11-24 App Releases migration content comparison

### Files compared

- `supabase/migrations/202610310001_app_releases.sql`
- `supabase/migrations/20261031_app_releases.sql`

These are not duplicate copies. They describe materially different schemas and authorization designs.

### First file: matches the observed production table shape

The first file defines `version_code` as UNIQUE, `published` default false, nullable `published_at`, and nullable `created_by` referencing `auth.users`. Its policies use direct `profiles.role = 'admin'` checks and it does not define `is_app_release_admin()`.

A read-only production catalog inspection found the same nine columns, matching defaults/nullability, a unique `version_code` index, and the five policy names/operations from this file. This is evidence of schema/content alignment, not proof of which SQL file was executed or when.

### Second file: incompatible with the observed production table

The second file adds `is_latest` to its index definition, but its own `CREATE TABLE IF NOT EXISTS` does not add that column to an already-existing table. The observed production table has no `is_latest` column. Therefore, applying this file against the observed production table would fail at the `app_releases_published_idx` creation step.

It also differs in defaults/nullability, omits `created_by`, omits a UNIQUE constraint on `version_code`, adds an HTTPS check, and defines a SECURITY DEFINER helper `is_app_release_admin()`. The helper is absent in the observed production catalog. These differences are not safe to reconcile by simply running both files.

### Additional live ACL finding

The read-only catalog query showed `anon` currently has table-level INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER grants on `public.app_releases`, in addition to SELECT. Current RLS policies do not define anon write policies, which currently blocks ordinary anon writes through RLS, but the broad table grants are unnecessary and should be reviewed as a separate least-privilege hardening item. Do not change production ACLs as part of this documentation-only task.

### Frontend compatibility

The current admin frontend writes `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_by`; it validates HTTPS URLs client-side. The public release center reads `id`, `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_at`. Neither current frontend file references `is_latest` or `is_app_release_admin()`.

### Decision

- Do not apply either App Releases SQL file to production during baseline reconciliation.
- Preserve both files for now; no rename/delete/reorder was made.
- Treat `202610310001_app_releases.sql` as the closer structural match to the observed live schema, but do not claim it is proven execution history.
- Keep the second file flagged as incompatible with the current live schema unless a separately reviewed migration is designed from verified requirements.
- Create a development-only follow-up to review and tighten the unnecessary `anon` table privileges, with isolated regression tests before any production approval.

This comparison used GitHub source reads, frontend source reads, and read-only production catalog queries only. No production SQL, data changes, deployment, PR merge, or paid service was used.

## 2026-11-24 App Releases anon ACL hardening candidate

### Live privilege confirmation

A second read-only production catalog check confirmed the effective `anon` privileges on `public.app_releases` are currently SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER. No anon column-level grants or role memberships were found. This supports a table-level least-privilege revoke without changing the published-release SELECT path.

### Candidate SQL

Added `supabase/candidate_sql/app_releases_anon_acl_hardening.sql`:

- Revoke INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER from `anon`.
- Preserve SELECT for the public release center.
- Do not change authenticated or service_role grants.
- Candidate only; not applied to production.

### Disposable regression test

Added `supabase/tests/sql/app-releases-anon-acl.test.sql` and wired it into the existing isolated PostgreSQL job in `.github/workflows/maintenance-edge-functions.yml`.

The test reproduces the observed broad grants, applies only the candidate SQL in a disposable database, verifies anon retains SELECT but loses all six unnecessary privileges, checks only published rows are visible, and confirms authenticated table grants remain unchanged.

### CI correction note

The first test attempt exposed a quoting error in the test-only `auth.uid()` fixture (dollar-quote delimiter was malformed). This was a test harness issue, not a production SQL issue. The fixture was corrected to use a named dollar-quote delimiter (`$body# Smart Class Maintenance — Phase 1 closeout and Phase 2 worklist

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

**Phase 2: in progress.** 使用者已明確確認沒有在其他 local/test/preview/staging/shared database 執行 Maintenance migrations；正式 production 的 migration ledger/schema baseline 仍未完成核對，故仍阻擋 migration history 改寫與正式部署。

No production readiness claim is made. No production changes are authorized by this document.

## Source note

The uploaded file `啟動第一步檢查.txt` records an earlier SQL review snapshot describing a four-table design and service-role grants. The current Maintenance implementation has since evolved to a private-schema design with six tables, five RPCs, and Edge Function wrappers. Use the current API v0.7, Edge Function development specification, SQL compatibility audit, and current single-pass migration plan as the working references; do not treat the earlier snapshot as the current schema specification.


## 2026-11-22 使用者環境確認補記

使用者已明確回答「無」：沒有在其他 local、test、preview、staging 或 shared database 執行過 Maintenance migrations。此回答更新本文件較早「未確認」的使用者回憶狀態。CI PostgreSQL/GoTrue/PostgREST 服務為 disposable 測試環境，不視為持續存在的使用者資料庫。

仍須區分：此回答不等同 production migration ledger 已修復。正式 Supabase 的 migration history/schema baseline 仍有獨立缺口；production catalog 未見 Maintenance objects 不能替代完整 baseline reconciliation。因此 timestamped migrations 先保持不動，不執行 production SQL、migration repair、Edge Function deploy、feature flag change 或 PR merge。


## 2026-11-23 Operational preflight audit

This is a read-only repository and project inventory update. It does not authorize deployment or any production change.

### Verified

- [x] Supabase project `private-website` is `ACTIVE_HEALTHY`, PostgreSQL 17.11, region `ap-northeast-1`.
- [x] Supabase currently lists no development branches.
- [x] Supabase currently lists no Maintenance Edge Functions. The five Maintenance functions remain repository-only; no hosted endpoint has been deployed.
- [x] Supabase migration listing remains empty. This is not a substitute for a reconstructed production migration baseline.
- [x] Repository config sets `maintenance-status` to `verify_jwt = false`; all four admin endpoints use `verify_jwt = true`.
- [x] Shared handler defaults CORS to the exact GitHub Pages origin `https://johnjohn114.github.io`; `MAINTENANCE_ALLOWED_ORIGINS` can explicitly override it with a comma-separated allowlist.
- [x] Deno tests cover the default allowed preflight origin and rejection of an unapproved origin.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key (prefers `SUPABASE_PUBLISHABLE_KEY`, with documented fallbacks). Secret values were not read, requested, or recorded.
- [x] A read-only SQL check of `current_setting('pgrst.db_schemas', true)` returned NULL; this does not reveal the hosted Data API Exposed schemas configuration.

### Still unverified / blocked

- [ ] Confirm the actual Data API Exposed schemas setting in the Supabase project configuration. The private Maintenance schema must remain unexposed; the required public RPC arrangement must be confirmed against the final SQL design.
- [ ] Confirm the deployed Edge Function environment contains the required built-in Supabase URL/key variables. Do not copy secret values into GitHub, chat, or documentation.
- [ ] Confirm the actual hosted CORS override, if any. The repository default is verified, but no Maintenance function is deployed to exercise hosted CORS.
- [ ] Run hosted-runtime smoke tests only after a separately approved non-production or production deployment. No free hosted non-production branch currently exists, and no paid branch/service will be created.

### Proposed release sequence (not authorization)

1. Reconcile the production migration baseline and finalize the exact timestamped migration source.
2. Apply the approved database migration to the specifically authorized target.
3. Deploy the five Edge Functions with the verified environment configuration.
4. Run hosted smoke tests for public status, admin authentication/authorization, lifecycle actions, pagination, idempotent retries, CORS, and Taiwan UTC+8 display.
5. Only after separate approval, integrate the frontend and consider enabling the feature flag. Keep `MAINTENANCE_FEATURE_ENABLED=false` until then.

No production SQL, migration repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used during this audit.


## 2026-11-23 Combined operational confirmation — results

This section records the requested combined read-only checks. No production configuration was changed.

### Confirmed from repository and Supabase project inventory

- [x] Repository `supabase/config.toml` defines five Maintenance Edge Functions:
  - `maintenance-status`: `verify_jwt = false` because the handler performs optional user-token validation itself.
  - `maintenance-admin-list`, `maintenance-event-create`, `maintenance-event-update`, `maintenance-event-action`: `verify_jwt = true`.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key. It prefers `SUPABASE_PUBLISHABLE_KEY`, with `SUPABASE_ANON_KEY` and JSON `SUPABASE_PUBLISHABLE_KEYS.default` fallbacks. These are read at runtime; no credential values were accessed or recorded.
- [x] CORS allowlist defaults to exactly `https://johnjohn114.github.io`. Optional `MAINTENANCE_ALLOWED_ORIGINS` overrides it as a comma-separated list. Automated tests verify allowed preflight and rejection of an unapproved origin.
- [x] Supabase inventory currently lists six Edge Functions, none of which is a Maintenance function.
- [x] Supabase inventory lists zero development branches and zero migrations.
- [x] Current production schema inventory contains no `private` schema. The role grants query only confirms `public` schema usage for API roles; it does not prove the Data API Exposed schemas setting.
- [x] Read-only `pg_db_role_setting` inspection found no `pgrst.db_schemas` setting on `authenticator`, `anon`, `authenticated`, or `service_role`. This is not authoritative evidence of the dashboard-level Data API Exposed schemas configuration.

### Explicit unresolved items

- [ ] The actual Supabase Dashboard setting under Data API → Exposed schemas cannot be read through the available project/database tools. It must be visually confirmed before any deployment. Expected target: keep `private` out of Exposed schemas; only expose `public` RPC wrappers if the final SQL architecture requires them.
- [ ] Actual deployed Edge Function environment configuration cannot be confirmed because the Maintenance functions are not deployed. At deployment time, verify built-in `SUPABASE_URL` and publishable/anon key availability; if overriding CORS, configure `MAINTENANCE_ALLOWED_ORIGINS=https://johnjohn114.github.io`. Do not paste or store secret values in source control.
- [ ] Hosted CORS cannot be smoke-tested until a Maintenance function is deployed to an explicitly authorized target.

### Current decision

Operational code-side prerequisites are documented and internally consistent. Dashboard Exposed schemas and hosted environment values remain unverified, so deployment remains blocked. No production SQL, migration, dashboard configuration, Edge Function deployment, feature-flag change, PR merge, or paid resource was used.


## 2026-11-23 Dashboard screenshot confirmation — Data API schemas

The user supplied a Supabase Dashboard → Integrations → Data API → Settings screenshot.

### Visually confirmed

- Exposed schemas shows `2 of 2 schemas exposed`.
- The only selected schemas shown are `graphql_public` and `public`.
- `private` is not in the exposed schema selection.
- Exposed functions shows `35 of 38 functions exposed`; the screenshot does not identify which three functions are disabled.
- “Automatically expose new tables” appears enabled (green toggle) in the screenshot. This setting should be reviewed before creating future tables; do not change it as part of this read-only audit.

### Impact on Maintenance release

- The screenshot confirms that `private` is not currently exposed through the Data API.
- It does not establish that the `private` schema already exists; the current database schema inventory did not list it.
- After the approved migration creates `private`, keep it out of Exposed schemas.
- Confirm which three existing functions are not exposed and verify the final five Maintenance RPC entry points against the intended API design before release. No Maintenance functions are currently deployed.
- No Dashboard setting was changed based on this screenshot.

This screenshot resolves the previously outstanding visual confirmation for the current Exposed schemas selection. Hosted function configuration and deployment smoke tests remain outstanding.


### Exposed functions — user supplied expanded-list screenshot and clarification

The three unchecked functions are identified as:

1. `public.assign_member_no_and_nickname()`
2. `public.award_growth_points(uuid,integer,text,text,text,text,uuid)`
3. `public.is_admin()`

Assessment against the current authorization design:

- Keep all three unchecked in Data API → Exposed functions.
- `assign_member_no_and_nickname()` is a trigger/internal helper and should not be callable as a public RPC.
- `award_growth_points(...)` is an internal point-awarding function. The authorization migration explicitly denies direct EXECUTE to anon and authenticated; it must not be exposed as an RPC.
- `is_admin()` is a SECURITY DEFINER authorization helper. It is used internally by RLS policies and Maintenance RPCs; the single-pass Maintenance SQL draft grants EXECUTE to `pg_database_owner` so the admin RPC owner can call it. This database EXECUTE grant does not require exposing `is_admin()` as a Data API RPC endpoint. Keep it unchecked in the Exposed functions list.
- The Dashboard exposure toggle and PostgreSQL EXECUTE ACL are separate controls. Do not enable a function in the Data API merely to satisfy an internal SQL EXECUTE dependency.

The screenshot therefore shows a suitable exposure posture for these three functions. This does not substitute for validating the full final function ACL matrix or applying the migration to an approved target.


## 2026-11-23 Review — Automatically expose new tables

The user agreed to review the Dashboard setting. This review was read-only; the toggle was not changed.

### Dashboard observation

- Screenshot shows “Automatically expose new tables” enabled.
- Dashboard text says it grants Data API role privileges to new tables by default.
- The Maintenance SQL draft creates its six tables under the separate `private` schema, not `public`.
- The confirmed exposed schema selection is only `public` and `graphql_public`; `private` is not exposed.

### Production catalog cross-check (read-only)

- Current production `pg_default_acl` contains explicit `postgres` defaults for tables, sequences and functions in `public` and `storage`; there is no global `postgres` default ACL row and no `private` schema default ACL.
- The `postgres` table default ACL for `public` currently grants broad table privileges to `anon`, `authenticated` and `service_role`. This is relevant to future tables created in `public`; it is not evidence that the Maintenance tables in `private` will be exposed.
- Existing default ACLs owned by Supabase-managed roles were not changed or recommended for modification.

### Maintenance draft review

- The draft explicitly creates `private`, keeps it out of the Data API exposed schema list, enables and FORCEs RLS on all six tables, and applies explicit table grants/policies.
- The draft revokes table privileges from `PUBLIC`, `anon` and `authenticated` before applying the narrow read/write grants. It does not include `service_role` in that table-level REVOKE statement; this should remain a focused ACL assertion in isolated tests before release.
- The dashboard auto-expose toggle is not a substitute for explicit PostgreSQL grants, RLS, and keeping `private` out of Exposed schemas.

### Recommendation and decision

- Recommended hardening: disable “Automatically expose new tables” to prevent accidental Data API grants when future tables are created in exposed schemas, then explicitly grant only the required roles for each new public table.
- This is a preventive project-wide workflow change, not a prerequisite for the current Maintenance draft because its tables are created in the unexposed `private` schema with explicit ACL/RLS design.
- Do not change the Dashboard toggle without separate explicit confirmation. No settings, grants, schemas, tables, or production data were changed during this review.

## 2026-11-24 CI rerun and backend contract review

This is a development-branch documentation update based on the current PR head. It does not authorize production changes.

### Latest CI evidence

- [x] GitHub Actions run #393 / run ID 45159850371 completed successfully: 4/4 jobs passed.
- [x] GoTrue-issued JWT + PostgREST integration for the single-pass draft passed, including the hosted-style non-superuser database-owner path, rollback after injected failure, and Deno Edge handler integration through disposable Auth/REST services.
- [x] Isolated PostgreSQL RPC/RLS tests passed, including growth-function authorization regressions, default-privilege/trigger regressions, sequential integration and PostgREST JWT/RLS/concurrency checks.
- [x] Legacy GoTrue/PostgREST compatibility path passed.
- [x] Deno type checks, request validation, feature gate, Playwright compatibility and SQL static guardrails passed.

These are disposable CI services. The Deno.serve harness is not a deployment test of Supabase's hosted Edge Runtime or gateway.

### Backend operation contract review

The current implementation remains aligned to API v0.7 and the single-pass SQL draft:

1. Edge handler checks origin, HTTP method, request shape and body size.
2. Admin endpoints validate the supplied bearer token with Supabase Auth; the original user JWT is forwarded to PostgREST.
3. Each endpoint calls only its matching RPC with one `p_request jsonb` argument.
4. Database RPC re-checks the JWT subject and `public.is_admin()`; client-supplied actor/role fields are not accepted.
5. Create/update/action operations keep event changes, scope links, audit snapshots and idempotency result in one database transaction.
6. Optimistic `expected_version` checks and transaction-scoped advisory locking protect concurrent lifecycle changes and overlap checks.
7. Public status returns a restricted response shape; private notes and audit details are only returned by the admin listing path.

### Documentation precedence clarification

The historical Edge Functions development spec contains earlier design text referring to `maintenance_rpc_executor` and older SECURITY INVOKER assumptions. Those passages are historical only. The current single-pass SQL draft and API v0.7 govern the present branch: admin RPCs are SECURITY DEFINER owned by built-in `pg_database_owner`; public status is SECURITY INVOKER. Do not revive the historical executor role design.

### Remaining release blockers

- [ ] Production migration/schema baseline reconciliation remains unresolved. Production migration listing is empty and the environment has no verified complete baseline; do not repair or rewrite migration history by guesswork.
- [ ] No hosted free non-production Supabase branch is available; do not create paid resources.
- [ ] Actual deployed Edge Function environment and hosted CORS cannot be verified because Maintenance functions are not deployed.
- [ ] Supabase hosted Edge Runtime smoke tests remain a post-approval pre-release task.
- [ ] Keep PR #34 Draft/unmerged, Maintenance feature flag false, and production unchanged pending separate explicit approval.

No production SQL, migration repair, deployment, feature-flag change, PR merge, dashboard setting change or paid service was used for this review.

## 2026-11-24 production migration baseline read-only audit

### Production facts confirmed by Supabase read-only tools

- PostgreSQL version: 17.11.
- Non-system schemas currently present: `auth`, `extensions`, `graphql`, `graphql_public`, `public`, `realtime`, `storage`, `vault`.
- `public` currently contains 44 tables; all non-system schemas together contain 85 tables.
- The `private` schema does not currently exist.
- Supabase migration listing returns an empty array.
- The `supabase_migrations` schema does not exist, and therefore `supabase_migrations.schema_migrations` does not exist.
- No schema or migration-history object was created or changed by this audit.

### Repository migration inventory

The current development branch contains seven files under `supabase/migrations/`:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
7. `26.11.3_calendar_fields.sql`

The two app-releases files appear to be competing/overlapping migration entries and require a content-level reconciliation. The directory also mixes timestamp conventions. Do not reorder, rename, delete, or apply any of these files until their actual production effects are established.

### Maintenance migration track conflict

- The historical initial Maintenance migration describes SECURITY INVOKER/RLS and preconditions based on the earlier design.
- The historical least-privilege upgrade explicitly creates and uses `maintenance_rpc_executor`.
- The current PR #34 single-pass track instead uses the built-in `pg_database_owner` model and supersedes the earlier executor-role approach.
- Production currently has no `private` schema, so the current Maintenance schema has not been installed there. This does not establish whether any unrelated SQL files were previously run manually.

### Baseline decision

The production database is populated but has no readable Supabase migration ledger. Repository files alone cannot establish which SQL changes were manually applied or whether every file matches the live schema. A full, schema-only, reviewed export and object-by-object reconciliation are required before declaring a baseline.

The current tool environment does not provide a verified complete `pg_dump`/Supabase CLI export path. Do not simulate a dump from partial catalog queries. Do not create `supabase_migrations`, insert fabricated history rows, use `migration repair`, run `db push`, or apply any historical Maintenance migration as a shortcut.

### Next safe actions

1. Obtain a complete schema-only export through an approved read-only export path (or a local CLI/pg_dump environment with the required tools), without exporting production data or secrets.
2. Compare the export against all seven repository migration files and the current single-pass Maintenance draft.
3. Resolve duplicate/overlapping app-releases migration content and timestamp conventions in a separate development-only change.
4. Produce a reviewed baseline plan and isolated replay proof before any separately approved production operation.

No production DDL/DML, migration-history repair, data export, deployment, PR merge, feature-flag change, dashboard setting change, or paid service was used in this audit.

## 2026-11-24 App Releases migration content comparison

### Files compared

- `supabase/migrations/202610310001_app_releases.sql`
- `supabase/migrations/20261031_app_releases.sql`

These are not duplicate copies. They describe materially different schemas and authorization designs.

### First file: matches the observed production table shape

The first file defines `version_code` as UNIQUE, `published` default false, nullable `published_at`, and nullable `created_by` referencing `auth.users`. Its policies use direct `profiles.role = 'admin'` checks and it does not define `is_app_release_admin()`.

A read-only production catalog inspection found the same nine columns, matching defaults/nullability, a unique `version_code` index, and the five policy names/operations from this file. This is evidence of schema/content alignment, not proof of which SQL file was executed or when.

### Second file: incompatible with the observed production table

The second file adds `is_latest` to its index definition, but its own `CREATE TABLE IF NOT EXISTS` does not add that column to an already-existing table. The observed production table has no `is_latest` column. Therefore, applying this file against the observed production table would fail at the `app_releases_published_idx` creation step.

It also differs in defaults/nullability, omits `created_by`, omits a UNIQUE constraint on `version_code`, adds an HTTPS check, and defines a SECURITY DEFINER helper `is_app_release_admin()`. The helper is absent in the observed production catalog. These differences are not safe to reconcile by simply running both files.

### Additional live ACL finding

The read-only catalog query showed `anon` currently has table-level INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER grants on `public.app_releases`, in addition to SELECT. Current RLS policies do not define anon write policies, which currently blocks ordinary anon writes through RLS, but the broad table grants are unnecessary and should be reviewed as a separate least-privilege hardening item. Do not change production ACLs as part of this documentation-only task.

### Frontend compatibility

The current admin frontend writes `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_by`; it validates HTTPS URLs client-side. The public release center reads `id`, `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_at`. Neither current frontend file references `is_latest` or `is_app_release_admin()`.

### Decision

- Do not apply either App Releases SQL file to production during baseline reconciliation.
- Preserve both files for now; no rename/delete/reorder was made.
- Treat `202610310001_app_releases.sql` as the closer structural match to the observed live schema, but do not claim it is proven execution history.
- Keep the second file flagged as incompatible with the current live schema unless a separately reviewed migration is designed from verified requirements.
- Create a development-only follow-up to review and tighten the unnecessary `anon` table privileges, with isolated regression tests before any production approval.

This comparison used GitHub source reads, frontend source reads, and read-only production catalog queries only. No production SQL, data changes, deployment, PR merge, or paid service was used.

## 2026-11-24 App Releases anon ACL hardening candidate

### Live privilege confirmation

A second read-only production catalog check confirmed the effective `anon` privileges on `public.app_releases` are currently SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER. No anon column-level grants or role memberships were found. This supports a table-level least-privilege revoke without changing the published-release SELECT path.

### Candidate SQL

Added `supabase/candidate_sql/app_releases_anon_acl_hardening.sql`:

- Revoke INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER from `anon`.
- Preserve SELECT for the public release center.
- Do not change authenticated or service_role grants.
- Candidate only; not applied to production.

### Disposable regression test

Added `supabase/tests/sql/app-releases-anon-acl.test.sql` and wired it into the existing isolated PostgreSQL job in `.github/workflows/maintenance-edge-functions.yml`.

The test reproduces the observed broad grants, applies only the candidate SQL in a disposable database, verifies anon retains SELECT but loses all six unnecessary privileges, checks only published rows are visible, and confirms authenticated table grants remain unchanged.

### CI correction note

The first test attempt exposed a quoting error in the test-only `auth.uid()` fixture (dollar-quote delimiter was malformed). This was a test harness issue, not a production SQL issue. The fixture was corrected to use a named dollar-quote delimiter (`$body# Smart Class Maintenance — Phase 1 closeout and Phase 2 worklist

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

**Phase 2: in progress.** 使用者已明確確認沒有在其他 local/test/preview/staging/shared database 執行 Maintenance migrations；正式 production 的 migration ledger/schema baseline 仍未完成核對，故仍阻擋 migration history 改寫與正式部署。

No production readiness claim is made. No production changes are authorized by this document.

## Source note

The uploaded file `啟動第一步檢查.txt` records an earlier SQL review snapshot describing a four-table design and service-role grants. The current Maintenance implementation has since evolved to a private-schema design with six tables, five RPCs, and Edge Function wrappers. Use the current API v0.7, Edge Function development specification, SQL compatibility audit, and current single-pass migration plan as the working references; do not treat the earlier snapshot as the current schema specification.


## 2026-11-22 使用者環境確認補記

使用者已明確回答「無」：沒有在其他 local、test、preview、staging 或 shared database 執行過 Maintenance migrations。此回答更新本文件較早「未確認」的使用者回憶狀態。CI PostgreSQL/GoTrue/PostgREST 服務為 disposable 測試環境，不視為持續存在的使用者資料庫。

仍須區分：此回答不等同 production migration ledger 已修復。正式 Supabase 的 migration history/schema baseline 仍有獨立缺口；production catalog 未見 Maintenance objects 不能替代完整 baseline reconciliation。因此 timestamped migrations 先保持不動，不執行 production SQL、migration repair、Edge Function deploy、feature flag change 或 PR merge。


## 2026-11-23 Operational preflight audit

This is a read-only repository and project inventory update. It does not authorize deployment or any production change.

### Verified

- [x] Supabase project `private-website` is `ACTIVE_HEALTHY`, PostgreSQL 17.11, region `ap-northeast-1`.
- [x] Supabase currently lists no development branches.
- [x] Supabase currently lists no Maintenance Edge Functions. The five Maintenance functions remain repository-only; no hosted endpoint has been deployed.
- [x] Supabase migration listing remains empty. This is not a substitute for a reconstructed production migration baseline.
- [x] Repository config sets `maintenance-status` to `verify_jwt = false`; all four admin endpoints use `verify_jwt = true`.
- [x] Shared handler defaults CORS to the exact GitHub Pages origin `https://johnjohn114.github.io`; `MAINTENANCE_ALLOWED_ORIGINS` can explicitly override it with a comma-separated allowlist.
- [x] Deno tests cover the default allowed preflight origin and rejection of an unapproved origin.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key (prefers `SUPABASE_PUBLISHABLE_KEY`, with documented fallbacks). Secret values were not read, requested, or recorded.
- [x] A read-only SQL check of `current_setting('pgrst.db_schemas', true)` returned NULL; this does not reveal the hosted Data API Exposed schemas configuration.

### Still unverified / blocked

- [ ] Confirm the actual Data API Exposed schemas setting in the Supabase project configuration. The private Maintenance schema must remain unexposed; the required public RPC arrangement must be confirmed against the final SQL design.
- [ ] Confirm the deployed Edge Function environment contains the required built-in Supabase URL/key variables. Do not copy secret values into GitHub, chat, or documentation.
- [ ] Confirm the actual hosted CORS override, if any. The repository default is verified, but no Maintenance function is deployed to exercise hosted CORS.
- [ ] Run hosted-runtime smoke tests only after a separately approved non-production or production deployment. No free hosted non-production branch currently exists, and no paid branch/service will be created.

### Proposed release sequence (not authorization)

1. Reconcile the production migration baseline and finalize the exact timestamped migration source.
2. Apply the approved database migration to the specifically authorized target.
3. Deploy the five Edge Functions with the verified environment configuration.
4. Run hosted smoke tests for public status, admin authentication/authorization, lifecycle actions, pagination, idempotent retries, CORS, and Taiwan UTC+8 display.
5. Only after separate approval, integrate the frontend and consider enabling the feature flag. Keep `MAINTENANCE_FEATURE_ENABLED=false` until then.

No production SQL, migration repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used during this audit.


## 2026-11-23 Combined operational confirmation — results

This section records the requested combined read-only checks. No production configuration was changed.

### Confirmed from repository and Supabase project inventory

- [x] Repository `supabase/config.toml` defines five Maintenance Edge Functions:
  - `maintenance-status`: `verify_jwt = false` because the handler performs optional user-token validation itself.
  - `maintenance-admin-list`, `maintenance-event-create`, `maintenance-event-update`, `maintenance-event-action`: `verify_jwt = true`.
- [x] Shared handler requires `SUPABASE_URL` and a publishable/anon key. It prefers `SUPABASE_PUBLISHABLE_KEY`, with `SUPABASE_ANON_KEY` and JSON `SUPABASE_PUBLISHABLE_KEYS.default` fallbacks. These are read at runtime; no credential values were accessed or recorded.
- [x] CORS allowlist defaults to exactly `https://johnjohn114.github.io`. Optional `MAINTENANCE_ALLOWED_ORIGINS` overrides it as a comma-separated list. Automated tests verify allowed preflight and rejection of an unapproved origin.
- [x] Supabase inventory currently lists six Edge Functions, none of which is a Maintenance function.
- [x] Supabase inventory lists zero development branches and zero migrations.
- [x] Current production schema inventory contains no `private` schema. The role grants query only confirms `public` schema usage for API roles; it does not prove the Data API Exposed schemas setting.
- [x] Read-only `pg_db_role_setting` inspection found no `pgrst.db_schemas` setting on `authenticator`, `anon`, `authenticated`, or `service_role`. This is not authoritative evidence of the dashboard-level Data API Exposed schemas configuration.

### Explicit unresolved items

- [ ] The actual Supabase Dashboard setting under Data API → Exposed schemas cannot be read through the available project/database tools. It must be visually confirmed before any deployment. Expected target: keep `private` out of Exposed schemas; only expose `public` RPC wrappers if the final SQL architecture requires them.
- [ ] Actual deployed Edge Function environment configuration cannot be confirmed because the Maintenance functions are not deployed. At deployment time, verify built-in `SUPABASE_URL` and publishable/anon key availability; if overriding CORS, configure `MAINTENANCE_ALLOWED_ORIGINS=https://johnjohn114.github.io`. Do not paste or store secret values in source control.
- [ ] Hosted CORS cannot be smoke-tested until a Maintenance function is deployed to an explicitly authorized target.

### Current decision

Operational code-side prerequisites are documented and internally consistent. Dashboard Exposed schemas and hosted environment values remain unverified, so deployment remains blocked. No production SQL, migration, dashboard configuration, Edge Function deployment, feature-flag change, PR merge, or paid resource was used.


## 2026-11-23 Dashboard screenshot confirmation — Data API schemas

The user supplied a Supabase Dashboard → Integrations → Data API → Settings screenshot.

### Visually confirmed

- Exposed schemas shows `2 of 2 schemas exposed`.
- The only selected schemas shown are `graphql_public` and `public`.
- `private` is not in the exposed schema selection.
- Exposed functions shows `35 of 38 functions exposed`; the screenshot does not identify which three functions are disabled.
- “Automatically expose new tables” appears enabled (green toggle) in the screenshot. This setting should be reviewed before creating future tables; do not change it as part of this read-only audit.

### Impact on Maintenance release

- The screenshot confirms that `private` is not currently exposed through the Data API.
- It does not establish that the `private` schema already exists; the current database schema inventory did not list it.
- After the approved migration creates `private`, keep it out of Exposed schemas.
- Confirm which three existing functions are not exposed and verify the final five Maintenance RPC entry points against the intended API design before release. No Maintenance functions are currently deployed.
- No Dashboard setting was changed based on this screenshot.

This screenshot resolves the previously outstanding visual confirmation for the current Exposed schemas selection. Hosted function configuration and deployment smoke tests remain outstanding.


### Exposed functions — user supplied expanded-list screenshot and clarification

The three unchecked functions are identified as:

1. `public.assign_member_no_and_nickname()`
2. `public.award_growth_points(uuid,integer,text,text,text,text,uuid)`
3. `public.is_admin()`

Assessment against the current authorization design:

- Keep all three unchecked in Data API → Exposed functions.
- `assign_member_no_and_nickname()` is a trigger/internal helper and should not be callable as a public RPC.
- `award_growth_points(...)` is an internal point-awarding function. The authorization migration explicitly denies direct EXECUTE to anon and authenticated; it must not be exposed as an RPC.
- `is_admin()` is a SECURITY DEFINER authorization helper. It is used internally by RLS policies and Maintenance RPCs; the single-pass Maintenance SQL draft grants EXECUTE to `pg_database_owner` so the admin RPC owner can call it. This database EXECUTE grant does not require exposing `is_admin()` as a Data API RPC endpoint. Keep it unchecked in the Exposed functions list.
- The Dashboard exposure toggle and PostgreSQL EXECUTE ACL are separate controls. Do not enable a function in the Data API merely to satisfy an internal SQL EXECUTE dependency.

The screenshot therefore shows a suitable exposure posture for these three functions. This does not substitute for validating the full final function ACL matrix or applying the migration to an approved target.


## 2026-11-23 Review — Automatically expose new tables

The user agreed to review the Dashboard setting. This review was read-only; the toggle was not changed.

### Dashboard observation

- Screenshot shows “Automatically expose new tables” enabled.
- Dashboard text says it grants Data API role privileges to new tables by default.
- The Maintenance SQL draft creates its six tables under the separate `private` schema, not `public`.
- The confirmed exposed schema selection is only `public` and `graphql_public`; `private` is not exposed.

### Production catalog cross-check (read-only)

- Current production `pg_default_acl` contains explicit `postgres` defaults for tables, sequences and functions in `public` and `storage`; there is no global `postgres` default ACL row and no `private` schema default ACL.
- The `postgres` table default ACL for `public` currently grants broad table privileges to `anon`, `authenticated` and `service_role`. This is relevant to future tables created in `public`; it is not evidence that the Maintenance tables in `private` will be exposed.
- Existing default ACLs owned by Supabase-managed roles were not changed or recommended for modification.

### Maintenance draft review

- The draft explicitly creates `private`, keeps it out of the Data API exposed schema list, enables and FORCEs RLS on all six tables, and applies explicit table grants/policies.
- The draft revokes table privileges from `PUBLIC`, `anon` and `authenticated` before applying the narrow read/write grants. It does not include `service_role` in that table-level REVOKE statement; this should remain a focused ACL assertion in isolated tests before release.
- The dashboard auto-expose toggle is not a substitute for explicit PostgreSQL grants, RLS, and keeping `private` out of Exposed schemas.

### Recommendation and decision

- Recommended hardening: disable “Automatically expose new tables” to prevent accidental Data API grants when future tables are created in exposed schemas, then explicitly grant only the required roles for each new public table.
- This is a preventive project-wide workflow change, not a prerequisite for the current Maintenance draft because its tables are created in the unexposed `private` schema with explicit ACL/RLS design.
- Do not change the Dashboard toggle without separate explicit confirmation. No settings, grants, schemas, tables, or production data were changed during this review.

## 2026-11-24 CI rerun and backend contract review

This is a development-branch documentation update based on the current PR head. It does not authorize production changes.

### Latest CI evidence

- [x] GitHub Actions run #393 / run ID 45159850371 completed successfully: 4/4 jobs passed.
- [x] GoTrue-issued JWT + PostgREST integration for the single-pass draft passed, including the hosted-style non-superuser database-owner path, rollback after injected failure, and Deno Edge handler integration through disposable Auth/REST services.
- [x] Isolated PostgreSQL RPC/RLS tests passed, including growth-function authorization regressions, default-privilege/trigger regressions, sequential integration and PostgREST JWT/RLS/concurrency checks.
- [x] Legacy GoTrue/PostgREST compatibility path passed.
- [x] Deno type checks, request validation, feature gate, Playwright compatibility and SQL static guardrails passed.

These are disposable CI services. The Deno.serve harness is not a deployment test of Supabase's hosted Edge Runtime or gateway.

### Backend operation contract review

The current implementation remains aligned to API v0.7 and the single-pass SQL draft:

1. Edge handler checks origin, HTTP method, request shape and body size.
2. Admin endpoints validate the supplied bearer token with Supabase Auth; the original user JWT is forwarded to PostgREST.
3. Each endpoint calls only its matching RPC with one `p_request jsonb` argument.
4. Database RPC re-checks the JWT subject and `public.is_admin()`; client-supplied actor/role fields are not accepted.
5. Create/update/action operations keep event changes, scope links, audit snapshots and idempotency result in one database transaction.
6. Optimistic `expected_version` checks and transaction-scoped advisory locking protect concurrent lifecycle changes and overlap checks.
7. Public status returns a restricted response shape; private notes and audit details are only returned by the admin listing path.

### Documentation precedence clarification

The historical Edge Functions development spec contains earlier design text referring to `maintenance_rpc_executor` and older SECURITY INVOKER assumptions. Those passages are historical only. The current single-pass SQL draft and API v0.7 govern the present branch: admin RPCs are SECURITY DEFINER owned by built-in `pg_database_owner`; public status is SECURITY INVOKER. Do not revive the historical executor role design.

### Remaining release blockers

- [ ] Production migration/schema baseline reconciliation remains unresolved. Production migration listing is empty and the environment has no verified complete baseline; do not repair or rewrite migration history by guesswork.
- [ ] No hosted free non-production Supabase branch is available; do not create paid resources.
- [ ] Actual deployed Edge Function environment and hosted CORS cannot be verified because Maintenance functions are not deployed.
- [ ] Supabase hosted Edge Runtime smoke tests remain a post-approval pre-release task.
- [ ] Keep PR #34 Draft/unmerged, Maintenance feature flag false, and production unchanged pending separate explicit approval.

No production SQL, migration repair, deployment, feature-flag change, PR merge, dashboard setting change or paid service was used for this review.

## 2026-11-24 production migration baseline read-only audit

### Production facts confirmed by Supabase read-only tools

- PostgreSQL version: 17.11.
- Non-system schemas currently present: `auth`, `extensions`, `graphql`, `graphql_public`, `public`, `realtime`, `storage`, `vault`.
- `public` currently contains 44 tables; all non-system schemas together contain 85 tables.
- The `private` schema does not currently exist.
- Supabase migration listing returns an empty array.
- The `supabase_migrations` schema does not exist, and therefore `supabase_migrations.schema_migrations` does not exist.
- No schema or migration-history object was created or changed by this audit.

### Repository migration inventory

The current development branch contains seven files under `supabase/migrations/`:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
7. `26.11.3_calendar_fields.sql`

The two app-releases files appear to be competing/overlapping migration entries and require a content-level reconciliation. The directory also mixes timestamp conventions. Do not reorder, rename, delete, or apply any of these files until their actual production effects are established.

### Maintenance migration track conflict

- The historical initial Maintenance migration describes SECURITY INVOKER/RLS and preconditions based on the earlier design.
- The historical least-privilege upgrade explicitly creates and uses `maintenance_rpc_executor`.
- The current PR #34 single-pass track instead uses the built-in `pg_database_owner` model and supersedes the earlier executor-role approach.
- Production currently has no `private` schema, so the current Maintenance schema has not been installed there. This does not establish whether any unrelated SQL files were previously run manually.

### Baseline decision

The production database is populated but has no readable Supabase migration ledger. Repository files alone cannot establish which SQL changes were manually applied or whether every file matches the live schema. A full, schema-only, reviewed export and object-by-object reconciliation are required before declaring a baseline.

The current tool environment does not provide a verified complete `pg_dump`/Supabase CLI export path. Do not simulate a dump from partial catalog queries. Do not create `supabase_migrations`, insert fabricated history rows, use `migration repair`, run `db push`, or apply any historical Maintenance migration as a shortcut.

### Next safe actions

1. Obtain a complete schema-only export through an approved read-only export path (or a local CLI/pg_dump environment with the required tools), without exporting production data or secrets.
2. Compare the export against all seven repository migration files and the current single-pass Maintenance draft.
3. Resolve duplicate/overlapping app-releases migration content and timestamp conventions in a separate development-only change.
4. Produce a reviewed baseline plan and isolated replay proof before any separately approved production operation.

No production DDL/DML, migration-history repair, data export, deployment, PR merge, feature-flag change, dashboard setting change, or paid service was used in this audit.

## 2026-11-24 App Releases migration content comparison

### Files compared

- `supabase/migrations/202610310001_app_releases.sql`
- `supabase/migrations/20261031_app_releases.sql`

These are not duplicate copies. They describe materially different schemas and authorization designs.

### First file: matches the observed production table shape

The first file defines `version_code` as UNIQUE, `published` default false, nullable `published_at`, and nullable `created_by` referencing `auth.users`. Its policies use direct `profiles.role = 'admin'` checks and it does not define `is_app_release_admin()`.

A read-only production catalog inspection found the same nine columns, matching defaults/nullability, a unique `version_code` index, and the five policy names/operations from this file. This is evidence of schema/content alignment, not proof of which SQL file was executed or when.

### Second file: incompatible with the observed production table

The second file adds `is_latest` to its index definition, but its own `CREATE TABLE IF NOT EXISTS` does not add that column to an already-existing table. The observed production table has no `is_latest` column. Therefore, applying this file against the observed production table would fail at the `app_releases_published_idx` creation step.

It also differs in defaults/nullability, omits `created_by`, omits a UNIQUE constraint on `version_code`, adds an HTTPS check, and defines a SECURITY DEFINER helper `is_app_release_admin()`. The helper is absent in the observed production catalog. These differences are not safe to reconcile by simply running both files.

### Additional live ACL finding

The read-only catalog query showed `anon` currently has table-level INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER grants on `public.app_releases`, in addition to SELECT. Current RLS policies do not define anon write policies, which currently blocks ordinary anon writes through RLS, but the broad table grants are unnecessary and should be reviewed as a separate least-privilege hardening item. Do not change production ACLs as part of this documentation-only task.

### Frontend compatibility

The current admin frontend writes `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_by`; it validates HTTPS URLs client-side. The public release center reads `id`, `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `published_at`, and `created_at`. Neither current frontend file references `is_latest` or `is_app_release_admin()`.

### Decision

- Do not apply either App Releases SQL file to production during baseline reconciliation.
- Preserve both files for now; no rename/delete/reorder was made.
- Treat `202610310001_app_releases.sql` as the closer structural match to the observed live schema, but do not claim it is proven execution history.
- Keep the second file flagged as incompatible with the current live schema unless a separately reviewed migration is designed from verified requirements.
- Create a development-only follow-up to review and tighten the unnecessary `anon` table privileges, with isolated regression tests before any production approval.

This comparison used GitHub source reads, frontend source reads, and read-only production catalog queries only. No production SQL, data changes, deployment, PR merge, or paid service was used.

## 2026-11-24 App Releases anon ACL hardening candidate

### Live privilege confirmation

A second read-only production catalog check confirmed the effective `anon` privileges on `public.app_releases` are currently SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER. No anon column-level grants or role memberships were found. This supports a table-level least-privilege revoke without changing the published-release SELECT path.

### Candidate SQL

Added `supabase/candidate_sql/app_releases_anon_acl_hardening.sql`:

- Revoke INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER from `anon`.
- Preserve SELECT for the public release center.
- Do not change authenticated or service_role grants.
- Candidate only; not applied to production.

### Disposable regression test

Added `supabase/tests/sql/app-releases-anon-acl.test.sql` and wired it into the existing isolated PostgreSQL job in `.github/workflows/maintenance-edge-functions.yml`.

The test reproduces the observed broad grants, applies only the candidate SQL in a disposable database, verifies anon retains SELECT but loses all six unnecessary privileges, checks only published rows are visible, and confirms authenticated table grants remain unchanged.

### CI correction note

The first test attempt exposed a quoting error in the test-only `auth.uid()` fixture (dollar-quote delimiter was malformed). ). The fresh PR CI run #414 (run ID `45407105455`) completed successfully: all 4 jobs passed, including the App Releases anonymous ACL regression test. The earlier failed run is retained as test-harness debugging evidence; the corrected run is the validation result.

No production SQL/ACL change, data mutation, deployment, merge, or paid service was used.

## 2026-11-24 expanded live catalog inventory and baseline reconciliation plan

### Read-only live catalog inventory

The Supabase table inventory and catalog aggregate confirm the following non-system schema object counts:

| Schema | Tables | Views | Functions | Sequences |
|---|---:|---:|---:|---:|
| auth | 27 | 0 | 4 | 1 |
| extensions | 0 | 2 | 55 | 0 |
| graphql | 0 | 0 | 0 | 0 |
| graphql_public | 0 | 0 | 1 | 0 |
| public | 44 | 1 | 38 | 2 |
| realtime | 3 | 0 | 19 | 1 |
| storage | 10 | 0 | 24 | 0 |
| vault | 1 | 1 | 5 | 0 |
| **Total** | **85** | **4** | **146** | **4** |

Additional observed catalog facts:

- All 44 current `public` tables have RLS enabled; none currently has FORCE ROW LEVEL SECURITY.
- The `public` schema has 98 RLS policies and 7 non-internal triggers.
- Twelve enum types and five installed extensions are present.
- The `private` schema is absent.
- Supabase project migration history remains empty and `supabase_migrations.schema_migrations` is absent.
- `auth.schema_migrations` does exist as an Auth-internal table. It is not the project-level Supabase migration ledger and must not be treated as one.

This inventory is a catalog summary, not a complete schema dump. It does not include all function bodies, view definitions, grants, default ACLs, policies' full expressions, trigger definitions, or every constraint definition.

### Repository migration file classification

1. `202610310001_app_releases.sql`: structurally closest to the live `public.app_releases` table and its observed policies; execution history is still unproven.
2. `20261031_app_releases.sql`: incompatible with the live table (references absent `is_latest` in an index and has materially different columns/defaults/policies); do not apply.
3. `202611160001_growth_function_authorization_hardening.sql`: replaces multiple live Growth RPC definitions and changes function default ACLs; requires a full per-function live-definition and ACL diff before any use.
4. `202611170001_default_privileges_and_trigger_hardening.sql`: changes defaults and replaces trigger functions; its global and schema-specific effects require separate ACL/trigger reconciliation.
5. `20261117121103_maintenance_system_initial.sql`: creates the six Maintenance tables and five RPCs using the earlier SECURITY INVOKER/direct-RLS model; production has no `private` schema, so this exact schema has not been installed there.
6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`: depends on the earlier Maintenance schema and creates `maintenance_rpc_executor`; it is superseded by the current PR #34 single-pass design using built-in `pg_database_owner`. Do not apply this legacy upgrade.
7. `26.11.3_calendar_fields.sql`: adds four calendar columns, two checks and one partial index to `public.announcements`; compare those exact objects to the live catalog before deciding whether it was manually applied.

Several historical migration files contain comments directing a one-time manual execution in Supabase SQL Editor. This is another reason the empty project migration ledger cannot be used as evidence that none of these SQL changes were applied.

### Baseline reconciliation conclusions

- There is no safe basis to create a new project migration ledger or replay all seven files in order.
- The current Maintenance single-pass draft is a new deployment candidate, not a verified production baseline.
- The old Maintenance initial + upgrade pair must not be combined with the new single-pass SQL.
- App Releases, Growth authorization, default ACL/trigger hardening, and calendar fields each need object-level comparisons against live definitions and ACLs.
- Managed schemas (`auth`, `storage`, `realtime`, `extensions`, `vault`) must not be blindly reconstructed or replayed as application migrations.

### Next-stage export and diff requirements

A trustworthy baseline package must be generated from a schema-only source using an approved local Supabase CLI/pg_dump path, with credentials kept local and never pasted into chat. It must capture application-owned schema objects and relevant managed dependencies without exporting production row data or secrets. The package must include definitions and metadata for tables, columns, constraints, indexes, sequences, views, functions, triggers, RLS policies, grants, default privileges, types, and extensions.

The current assistant execution environment still has no verified `supabase` CLI, `pg_dump`, or Docker path. Therefore no full dump is claimed. Catalog queries above are partial evidence only. Do not synthesize a fake dump from catalog summaries.

After a reviewed schema-only artifact is available:
1. Generate an object inventory and compare it against repository migrations.
2. Mark each object as live-match, live-drift, absent, or ambiguous.
3. Separate verified historical changes from the proposed Maintenance single-pass change.
4. Build and replay a clean baseline only in disposable local CI.
5. Obtain separate explicit approval before any production migration, deployment, PR merge, or ACL change.

No production DDL/DML, data export, migration-history repair, deployment, PR merge, feature-flag change, dashboard setting change, or paid service was used for this inventory.

## 2026-11-24 targeted live-vs-migration object comparison

### Calendar migration

Read-only production catalog comparison confirms all objects defined by `26.11.3_calendar_fields.sql` currently exist on `public.announcements`:

- Columns: `event_date`, `event_end_date`, `event_date_source`, `event_date_confirmed`.
- Checks: `announcements_event_date_source_check` and `announcements_event_date_range_check`, with definitions matching the migration's intended constraints.
- Partial index: `announcements_calendar_event_date_idx`, on `event_date` where `published = true AND event_date_confirmed = true`.

This is a live structural match. Since the project migration ledger is absent, it does not prove that this exact file was executed; the SQL may have been applied manually or the same objects created through another path. Treat this migration's effects as present when planning a baseline; do not replay it blindly.

### Growth authorization migration

The live catalog currently has 36 public SECURITY DEFINER functions, including five trigger-returning functions, and 31 non-trigger routines. Among the 31 non-trigger routines, 30 currently grant effective EXECUTE to `anon` and 30 to `authenticated`. The only non-trigger SECURITY DEFINER routine not executable by anon is `public.is_admin()`; this helper remains intentionally callable by anon for RLS policy evaluation.

The eight function signatures specifically inspected from `202611160001_growth_function_authorization_hardening.sql` show:
- Seven functions exist in production: `admin_delete_growth_reward`, `admin_upsert_growth_reward`, `refresh_growth_level`, `complete_growth_task`, `award_growth_points`, `check_growth_achievements`, and `check_activity_badges`.
- `public._refresh_growth_level_internal(uuid)` is absent in production; the candidate migration creates it.
- The live Growth authorization hardening has not been applied: broad anon EXECUTE remains on the live privileged routines. The candidate migration's intended fail-closed ACL matrix is not the current production ACL state.
- The candidate test suite explicitly treats `service_role` as a trusted server-side role for future non-trigger functions; trigger functions are denied direct EXECUTE for API roles. Do not describe the design as revoking every non-trigger function from `service_role`.

### Default privileges

A read-only inspection of `pg_default_acl` confirms that postgres-owned defaults in `public` currently grant:
- Tables: `anon`, `authenticated`, and `service_role` broad table privileges.
- Sequences: `anon`, `authenticated`, and `service_role` sequence privileges.
- Functions: `anon`, `authenticated`, and `service_role` EXECUTE.

The same explicit defaults also exist in `storage`. The proposed default-privilege migration is scoped to `public` for schema-specific revokes, while its global PUBLIC function revoke affects future postgres-owned functions across schemas. Existing explicit storage grants are not removed by that global PUBLIC change. This migration's live effect is not present in the observed `public` defaults; it remains a candidate requiring full review.

### Reconciliation status

| Migration | Live evidence | Current disposition |
|---|---|---|
| `26.11.3_calendar_fields.sql` | All four columns, both checks, and partial index exist | Live structural match; execution provenance unknown; do not replay |
| `202611160001_growth_function_authorization_hardening.sql` | Target functions mostly exist, internal helper absent, anon EXECUTE still broad | Candidate ACL hardening not applied; requires object/definition/ACL review |
| `202611170001_default_privileges_and_trigger_hardening.sql` | Public postgres defaults still grant API roles broad table/sequence/function privileges | Candidate default hardening not applied; preserve managed-schema boundaries |

No production SQL, migration-history repair, data export, deployment, PR merge, feature-flag change, or paid service was used for this comparison.

## 2026-11-24 Growth RPC frontend compatibility and authorization review

### Frontend RPC compatibility

A repository-wide scan of the current browser JavaScript found 19 distinct direct RPC endpoints. All Growth-related/member endpoints and admin Growth/competition-reward endpoints are present in the candidate migration's authenticated allowlist:

- Member: `record_growth_activity()`, `complete_growth_task(text)`, `check_growth_achievements(uuid)`, `refresh_growth_level(uuid)`, `redeem_growth_reward(uuid)`, `use_growth_coupon(uuid)`.
- Admin Growth: `admin_adjust_growth_points(uuid,integer,text)`, `admin_reset_growth_member(uuid,text)`, `admin_activity_analytics()`.
- Competition reward administration: `admin_grant_competition_reward(uuid,text,text,text,integer,uuid)`.

The remaining browser RPCs in the scan are also represented in the same allowlist: `admin_delete_video`, `admin_mark_competition_member_attendance`, `admin_promote_competition_waitlist`, `admin_settle_competition`, `admin_upsert_video`, `checkin_competition`, `close_my_support_ticket`, `increment_download_count`, and `join_competition_waitlist`.

The member Growth UI calls `record_growth_activity()` first, then loops through active task records and calls `complete_growth_task(code)`, then calls achievement and level refresh with the current member ID. The candidate versions retain these call signatures and enforce that a member can only inspect/update their own Growth state; admins may target another member where required. The reward redemption and coupon-use functions remain self-scoped.

### Live authorization defects confirmed

The production function definitions and current broad anon EXECUTE grants expose several concrete issues that the candidate addresses:

1. `award_growth_points(uuid,integer,text,text,text,text,uuid)` currently has no caller authorization check. Because anon and authenticated currently have EXECUTE, it is directly callable as an arbitrary-member points mutation. Candidate removes direct API-role EXECUTE while retaining owner-internal calls from trusted SECURITY DEFINER routines.
2. `check_growth_achievements(uuid)` currently accepts an arbitrary target user ID without verifying it matches `auth.uid()`; candidate adds self-or-admin authorization.
3. `refresh_growth_level(uuid)` currently updates an arbitrary target member's level without checking caller identity; candidate adds self-or-admin authorization and routes through a private internal helper.
4. `check_activity_badges(uuid)` currently has a NULL-comparison authorization gap: when `auth.uid()` is NULL but a non-NULL target ID is supplied, the comparison can evaluate NULL rather than TRUE. Candidate explicitly rejects a NULL caller before allowing self-or-admin target access.
5. `admin_delete_growth_reward(uuid)` and `admin_upsert_growth_reward(...)` currently compare a possibly NULL role with `<>`; SQL three-valued logic means a NULL role does not enter the IF branch. Candidate changes this to an explicit NULL-safe admin check.

### is_admin() handling

The existing `public.is_admin()` definition is SECURITY DEFINER with an empty search_path and fully-qualified `public.profiles` reference. The candidate allowlist explicitly preserves EXECUTE for `anon` and `authenticated` on this helper, because public RLS policies rely on it. It returns false when `auth.uid()` is NULL. This helper is not removed from the public RLS evaluation path.

### Compatibility and remaining scope

- No direct browser Growth RPC signature found in the current source is missing from the candidate authenticated allowlist.
- The candidate does not change the frontend RPC argument names or response shapes for the reviewed calls.
- Admin-only allowlisted functions inspected in production contain explicit admin checks; the ACL allowlist alone is not being treated as a substitute for those checks.
- The SQL regression suite exercises member self-only behavior, admin cross-member operations, JWT-less denial, internal points award denial, and the exhaustive SECURITY DEFINER EXECUTE matrix.
- This is source and catalog compatibility review, not a live application smoke test. Do not apply the migration to production until the full schema baseline and hosted Supabase runtime validation are complete.

No production SQL, data mutation, deployment, merge, feature-flag change, or paid service was used.

## 2026-11-24 integrated isolated CI validation (Growth + default ACL + Maintenance)

The current PR head `1a1e3b852779446b2e391ac3e58a3aaa102b0354` completed GitHub Actions run `45409464308` with all four jobs successful:

- Deno type checks, Edge Function validation tests, feature gate checks, browser compatibility tests, and SQL static guardrails.
- GoTrue-issued JWT + PostgREST integration against the legacy migration track.
- GoTrue-issued JWT + PostgREST integration against the Maintenance single-pass draft, including injected late-failure rollback, non-superuser database-owner application, executor ownership/privilege cleanup, Edge runtime, JWT/RPC/RLS and concurrency.
- Isolated PostgreSQL RPC/RLS tests, including App Releases anonymous ACL hardening, Growth authorization, default privileges/trigger side effects, the sequential Growth + default-privilege migration test, activity-member-stats view security, and PostgREST JWT/RLS/concurrency.

The sequential Growth/default-privilege SQL test applies both actual hardening migrations to one coherent disposable PostgreSQL fixture. The Maintenance single-pass draft is validated in its own isolated PostgreSQL/GoTrue tracks because it has a distinct database-owner and JWT/RLS harness. Thus the CI workflow validates the interacting release components and sequential Growth/default migration pair, but does not yet apply all three migration tracks in one shared database fixture. Do not overstate this as a single-database three-migration replay.

### Result and boundaries

- CI run `45409464308`: all 4 jobs passed.
- PR #34 remains Draft and unmerged.
- All database execution occurred in disposable GitHub Actions PostgreSQL services; no production Supabase SQL was executed.
- No production data was exported or changed; no deployment or feature-flag change occurred; no paid service was used.

This is a strong isolated validation result, not a substitute for full production schema export/reconciliation or hosted Supabase production approval.

## 2026-11-24 final Maintenance compatibility gate review

### Latest CI for current PR head

Current PR #34 head `8db388d50849e8dd4ec19ab3991bd90fd660536e` completed GitHub Actions run `45410008351` successfully: all four jobs passed.

- Isolated PostgreSQL RPC/RLS and regression tests.
- Deno type checks, Maintenance validation, feature gate, Playwright browser compatibility and SQL static guardrails.
- GoTrue-issued JWT + PostgREST integration for the single-pass draft.
- GoTrue-issued JWT + PostgREST integration for the legacy migration path.

The run validates disposable test services. It is not a production Supabase smoke test, not a production schema dump, and not a single shared database replay of all Growth, default-privilege, and Maintenance migration tracks.

### Maintenance SQL / Edge contract review

The current single-pass SQL draft and five Edge Function entrypoints were rechecked:

- Six private tables are present and use FORCE RLS.
- Five public RPC names align with the five Edge Function entrypoints; all calls use the single `p_request jsonb` argument.
- Admin RPCs use `SECURITY DEFINER` with empty `search_path`, are owned by `pg_database_owner`, and re-check `auth.uid()` plus `public.is_admin()`.
- Public status RPC is `SECURITY INVOKER`; optional user JWT validation is performed by the Edge Function, and an invalid optional token does not create an admin session.
- Audit log has row mutation and TRUNCATE protection.
- Disposable tests cover RLS, private-note isolation, audit/idempotency atomicity, rollback, lifecycle transitions, scope/global schedule overlap, concurrency and JWT/RPC access.

### Remaining release blockers found

1. **No final timestamped single-pass migration exists.** The tested SQL is still `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`, explicitly marked development-only. The two older timestamped Maintenance migrations remain in `supabase/migrations/`. The current workflow still validates both the legacy migration path and the single-pass draft path. A future migration-directory change must be coordinated with all workflow, SQL harness, script, and documentation references; do not add a third migration after the old initial migration and assume it removes the intermediate privilege window.
2. **Data API exposure is not verifiable from the current repository/catalog evidence.** The SQL comment instructs that `private` must remain excluded from Data API Exposed schemas, but that setting must be confirmed in Supabase Dashboard before deployment.
3. **Rate limiting is not implemented.** The Edge Functions validate request shape, JWT and payload size, but the shared handler has no rate-limit/throttle implementation and does not emit a business `429 RATE_LIMITED` response. The API spec's 429 entry must be treated as a future requirement, not a delivered capability. Choose and test a free-compatible limit strategy before production launch, or revise the API contract and acceptance criteria explicitly.
4. **Production baseline is still incomplete.** Production migration listing remains empty and no full schema-only export/rebuild has been performed. Catalog summaries do not establish every object definition, grant, policy, trigger, default ACL or historical migration provenance.
5. **Hosted production smoke test is outstanding.** Disposable GoTrue/PostgREST/Deno integration passed, but no Maintenance Edge Function has been deployed and no hosted runtime test has been run.
6. **Feature gate remains off.** Do not enable `MAINTENANCE_FEATURE_ENABLED` until the previous gates are closed.

### Legacy uploaded SQL review note

The uploaded `啟動第一步檢查.txt` describes an earlier four-table, `service_role`-oriented design. It is not the current v0.7 six-table private-schema + user-JWT / `pg_database_owner` single-pass design, and it is not SQL source. Retain it as historical review context only; do not use its table model or grants as the implementation source of truth.

### Current decision

- PR #34 remains Draft and unmerged.
- Latest current-head CI is 4/4 successful.
- The SQL draft is validated in disposable environments but is not a deployable migration.
- No production SQL, data export, migration-history repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used.
- Continue with production schema-only baseline capture/reconciliation and the rate-limit design decision. Keep production release blocked until both are resolved.

## 2026-11-24 additional read-only Supabase metadata capture

Supabase read-only project tools were used to supplement the SQL catalog summary:

- 85 tables across application and managed schemas: `auth` 27, `public` 44, `storage` 10, `realtime` 3, `vault` 1.
- 806 table columns and 162 foreign-key relationships in the verbose table inventory.
- Generated 63,093 characters of current TypeScript database types for the exposed public API schema. This is useful for application table/view/RPC type compatibility, but it is not a complete SQL schema dump and does not contain full policy expressions, trigger bodies, default ACLs, grants, all constraints/index DDL, or managed schema definitions.
- The Supabase extension catalog lists 78 available extensions; this is an availability catalog, not the installed-extension count. The installed extension list from `pg_extension` remains the source for what is actually installed.
- Current production Edge Function inventory contains six active functions; none of the five Maintenance function slugs are deployed. This matches the release boundary: Maintenance has not been deployed.

### What this does and does not establish

The expanded table inventory gives column and foreign-key coverage, and generated public TypeScript types provide an additional application-facing cross-check. Neither output is a schema-only backup or a replayable baseline. Do not infer that the production schema has been fully exported, and do not use generated TypeScript types as a replacement for SQL DDL.

### Next safe baseline step

A full schema-only dump still requires a supported local `supabase db dump --schema-only` / `pg_dump --schema-only` path using a local credential flow, or a reviewed catalog extraction process that captures every required object definition. Credentials must remain local and must never be pasted into chat, committed to GitHub, or printed in CI logs. Avoid exporting table data, auth users, vault contents, or secrets.

No production DDL/DML, data export, migration-history repair, Edge Function deployment, feature-flag change, PR merge, or paid service was used for this metadata capture.


## 2026-11-25 local schema-only export runbook

### Purpose and safety boundary

Prepare a reproducible, free local workflow to capture the production application's database definitions for comparison. This is a schema-only capture, not a migration, restore, or deployment operation.

- Keep database credentials on the user's own computer. Never paste passwords, connection strings, access tokens, or API keys into chat, commit them, or place them in command-line arguments or CI logs.
- Save the dump outside the Git repository first. Review it locally before deciding whether any sanitized excerpt belongs in GitHub.
- Do not include table data, Auth user records, Vault contents, storage object contents, or secrets.
- Do not run `supabase db push`, `supabase db reset`, `supabase migration repair`, or any SQL against production as part of this capture.
- Do not add a migration-history row or treat the dump as proof of migration provenance.

### Preferred CLI route

Use an up-to-date Supabase CLI on the user's own computer. The current CLI supports `supabase db dump --remote`; the default dump is schema-oriented and excludes Supabase-managed schemas such as Auth, Storage, and extension-created schemas. It does not include data or custom roles unless the corresponding opt-in flags are supplied.

1. Install/update the Supabase CLI and Docker Desktop (the CLI dump uses a containerized pg_dump).
2. Authenticate locally and link the intended project only after checking that the project reference is the expected production project.
3. Create a local folder outside the repository, for example `$HOME/supabase-private-review/`.
4. Run:

```sh
supabase db dump --remote -f "$HOME/supabase-private-review/production-schema.sql"
```

5. Confirm the CLI's printed `Target:` identifies the intended project before treating the output as valid.
6. Keep the SQL file local and private. Do not commit it or upload it to chat until it has been reviewed for sensitive definitions.

Do not add `--data-only` or `--role-only`. The command is an export; it does not apply SQL to the remote database.

### If Docker is unavailable

Do not attempt to install or run Docker inside GitHub Actions for this task. A local PostgreSQL client route can be evaluated separately, but it must explicitly enumerate the application-owned schemas and preserve the object definitions needed for review. Do not use a partial `public`-only dump as proof of a complete baseline. Before using direct `pg_dump`, confirm the installed client version, TLS connection settings, schema list, and permissions locally; keep the connection string out of shell history and process arguments.

### Local validation checklist

- Confirm the file exists and is non-empty.
- Confirm it contains DDL definitions, not table data statements such as `COPY ... FROM stdin` or bulk `INSERT INTO` rows.
- Confirm the expected application schemas and objects are represented.
- Record the CLI version, dump date/time, project reference (not credentials), and command used in a separate local note.
- Compare tables, columns, constraints, indexes, functions, triggers, RLS policies, grants, and default privileges against the repository's migrations and candidate Maintenance SQL.
- Treat missing objects or permission-denied omissions as unresolved; do not infer they do not exist.

### Release gate

A schema dump is evidence for reconciliation only. It does not authorize migration execution. Production remains unchanged; PR #34 remains Draft; Maintenance remains disabled and undeployed.
