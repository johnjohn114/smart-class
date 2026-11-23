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
