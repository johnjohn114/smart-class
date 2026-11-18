# Maintenance Architecture Decision v1.0

> Status: Proposed baseline for implementation review; not production approval.
> Date: 2026-11-18 (Asia/Taipei)
> Scope: Smart Class maintenance system v1 architecture.
> Safety: documentation-only change. No SQL execution, migration, production database change, Edge Function deployment, feature enablement, or paid resource creation.

## 1. Decision

For the current v1 maintenance implementation, use the **six-table private-schema architecture** and retain **SECURITY INVOKER** for all five RPCs.

This decision selects the current six-table source design as the implementation baseline. It does not assert that the design has passed production verification, and it does not authorize applying the migration.

## 2. Source basis

The decision is based on the current branch source files. The canonical SQL source is the development draft under `supabase/sql/`; no maintenance migration file is retained under `supabase/migrations/` until the production baseline and migration history have been reconciled:

- `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`
- `docs/maintenance-api-spec-v0.7.md` (latest API contract)
- `docs/maintenance-api-spec-v0.6.md` (previous contract version)
- `docs/maintenance-contract-sql-review-v0.1.md`
- `docs/maintenance-prelaunch-review-v0.1.md`

The earlier four-table review summary is not a complete replacement SQL schema. It names `maintenance_state`, `maintenance_events`, `maintenance_scopes`, and `maintenance_audit_logs`, but does not provide enough DDL, RPC signatures, policies, or migration details to treat it as a directly interchangeable implementation. Keep it as historical review input; do not merge its table names or assumptions into the six-table design without a separate schema change review.

## 3. Selected schema

The six tables are:

1. `private.maintenance_scopes`
2. `private.maintenance_events`
3. `private.maintenance_event_private_notes`
4. `private.maintenance_event_scopes`
5. `private.maintenance_audit_logs`
6. `private.maintenance_idempotency`

The design supports seven scope codes:

- `site_core`
- `announcements_info`
- `events_competitions`
- `video_content`
- `membership_growth`
- `store_support`
- `downloads_app`

The five RPCs are:

- `public.maintenance_status_public(jsonb)`
- `public.maintenance_admin_list(jsonb)`
- `public.maintenance_event_create(jsonb)`
- `public.maintenance_event_update(jsonb)`
- `public.maintenance_event_action(jsonb)`

## 4. Selected authorization model

### 4.1 SECURITY INVOKER

Retain SECURITY INVOKER for all five RPCs in v1.

Reasons:

- The current SQL and API contract are designed around the caller's JWT and PostgreSQL RLS.
- Management RPCs explicitly check `auth.uid()` and `public.is_admin()`.
- The Edge Functions validate the bearer token, while database RPC authorization remains authoritative and must re-check the caller.
- Changing to SECURITY DEFINER would introduce additional function-owner, RLS-bypass, search_path, and EXECUTE-ACL risks that are not necessary to resolve by assumption.

Do not change RPC security mode as a shortcut to removing table grants. Any future SECURITY DEFINER proposal requires a separate threat model, owner/role analysis, explicit ACL review, and isolated tests.

### 4.2 Private schema and Data API

The `private` schema must remain excluded from Supabase Data API Exposed schemas.

This is an additional exposure boundary, not a substitute for PostgreSQL grants and RLS. The actual production Dashboard setting has not yet been verified. Before release, record evidence that `private` is not exposed.

The current invoker design grants schema USAGE and limited table privileges to roles needed by the RPCs. Do not remove these grants without testing the resulting invoker behavior.

### 4.3 Direct table writes and RPC boundary

The current SQL grants some column-scoped direct writes to `authenticated` and relies on RLS admin policies. Therefore, the current design is **not a strict database-enforced RPC-only write model**.

For v1, this is a known limitation, not a claim that direct writes are impossible. Before release:

- Keep `private` excluded from Data API Exposed schemas.
- Keep RLS enabled on every private table.
- Keep grants column-scoped and least-privilege.
- Keep all management RPC authorization checks.
- Test direct PostgREST access and direct SQL privilege behavior using anon, ordinary authenticated, and admin identities.
- Verify that public status exposes only the documented response fields.
- Do not claim that grants/RLS can distinguish a write performed inside an invoker RPC from the same permitted SQL operation through another database path.

If the product requirement is strict RPC-only mutation, stop and produce a separate design. Do not silently switch to SECURITY DEFINER.

### 4.4 Audit log

The current v1 design keeps audit writes within the invoker/RLS model. It protects audit rows against UPDATE/DELETE and TRUNCATE using the existing trigger design, but an authorized authenticated admin still has a scoped INSERT privilege.

Consequently, do not describe the audit table as cryptographically immutable or as accepting inserts only from RPCs. The release review must test actor derivation from `auth.uid()`, direct insert constraints, and trigger protections.

## 5. Edge Function authorization

For management endpoints:

1. Validate the bearer token with Supabase Auth.
2. Do not trust a frontend-supplied user ID, actor ID, role, or admin flag.
3. The database management RPC must independently verify `auth.uid()` and `public.is_admin()`.
4. A future Edge-level admin precheck may be added as defense in depth, but it must not replace the database check and must not cache authorization decisions.

The public status endpoint remains optional-auth as specified by the API contract. Invalid optional credentials must not grant elevated behavior.

## 6. Required verification before release

The following are release gates, not claims of completed tests:

- Verify production Data API Exposed schemas exclude `private`.
- Verify actual anon, ordinary authenticated, and admin JWT behavior through PostgREST.
- Verify no management RPC is executable by anon or PUBLIC.
- Verify direct table reads/writes are constrained as documented for each role.
- Verify audit UPDATE/DELETE/TRUNCATE protections.
- Verify actor identity cannot be spoofed by request JSON.
- Verify public status response redaction and scope behavior.
- Verify scheduling overlap, advisory-lock concurrency, version conflict, idempotency replay/key reuse, and transaction rollback.
- Verify Edge Function CORS, environment variables, JWT handling, and deployed runtime behavior before enabling the feature.
- Resolve the documented rate-limit and audit/idempotency retention decisions.
- Reconcile the repository migration file and actual production migration history/baseline before any migration operation.

Existing CI and isolated-test reports are evidence only for the exact commit and environment identified in those reports. They are not proof of production Dashboard configuration or production runtime behavior. The full PostgreSQL restore test remains unverified where the project record says it was skipped.

## 7. Migration and production restrictions

This document does not authorize:

- `supabase db push`
- migration repair or replay
- production SQL/DDL/DML
- Edge Function deployment
- enabling the maintenance feature
- merging this branch into `main`
- creating paid resources

The production migration baseline/history issue must be independently resolved and approved before a separately reviewed migration is created or applied.

## 8. Decision summary

| Topic | v1 decision |
|---|---|
| Schema | Six private tables |
| Scope model | Seven defined scope codes |
| RPC count | Five |
| RPC security | SECURITY INVOKER |
| Authorization | JWT + database-side admin check |
| Private schema exposure | Excluded from Data API Exposed schemas |
| Direct writes | Known scoped privileges under RLS; not strict RPC-only |
| Audit | Trigger-protected against UPDATE/DELETE/TRUNCATE; direct INSERT limitation documented |
| Production migration | Not approved |

