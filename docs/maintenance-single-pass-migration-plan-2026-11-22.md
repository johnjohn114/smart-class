# Maintenance single-pass migration plan — 2026-11-22

## Scope and safety boundary

This branch is based on `integration/maintenance-pagination-hardening-main-20261121` at commit `5cd64d061768147cf0e57b4bf93f7902b3166b1b`.

This is a planning/review change only. It does not execute SQL, alter Supabase, deploy Edge Functions, change feature flags, merge PRs, or modify production data. No paid services or secrets are required.

## Verified repository findings

### 1. Maintenance currently has a two-migration bootstrap

- `supabase/migrations/20261117121103_maintenance_system_initial.sql` creates the private schema, six maintenance tables, RLS policies, direct authenticated mutation grants, public status RPC, and admin RPCs.
- `supabase/migrations/20261121140000_maintenance_rpc_least_privilege_upgrade.sql` then creates `maintenance_rpc_executor`, enables FORCE RLS, retargets mutation policies to that role, revokes authenticated write grants, changes admin RPCs to SECURITY DEFINER, and applies RPC execute ACLs.

This means the first migration alone represents an intermediate privilege model. If the first migration commits and the second migration fails, the database may remain in that intermediate state. The existing CI proves the ordered pair in its disposable test setup; it does not remove the operational risk of a separately committed first migration.

### 2. Candidate single-pass design

Before producing executable SQL, inspect all workflow/test references to both migration filenames and the RPC-owner model. Then prepare one clean-bootstrap migration that creates the final hardened model from the beginning:

- create the six private tables and seed the seven scopes;
- enable and FORCE RLS before exposing any table access;
- create policies with read access for intended roles and mutation access only for `maintenance_rpc_executor`;
- create the NOLOGIN/NOBYPASSRLS executor role and grant only the exact schema, table, and function privileges it needs;
- create admin write RPCs as SECURITY DEFINER owned by the executor role, with empty `search_path`;
- keep the public status RPC SECURITY INVOKER;
- revoke default PUBLIC execute and grant only the intended RPC execute privileges;
- retain audit immutability protections, including row mutation and TRUNCATE rejection;
- ensure no direct authenticated INSERT/UPDATE/DELETE grants are ever introduced, even temporarily.

Do not simply concatenate the two existing files. Their order, object ownership, policy targets, function definitions, grants, and role prerequisites must be reconciled deliberately. The final SQL must be tested as a single migration on a fresh disposable PostgreSQL/Supabase-compatible database.

### 3. Separate migration-history and schema-drift gate

Production introspection found no Maintenance objects and no visible Supabase migration tracking table/history. This does not prove that no migration was ever applied. Do not run `db push` or migration repair until the project baseline and actual schema drift have been reconciled.

The production database currently has an existing `public.app_releases` table. The two repository migrations that target it are not equivalent:

- `202610310001_app_releases.sql` defines `created_by` and does not define `is_latest`.
- `20261031_app_releases.sql` uses `CREATE TABLE IF NOT EXISTS`, then creates an index referencing `is_latest`; it does not add that missing column when the table already exists.

Therefore, the second file can fail on a database where the first schema already exists. This is a separate historical migration reconciliation task, not something to silently fold into the Maintenance migration. Preserve existing production data and determine the intended `is_latest` semantics before proposing any backfill or schema change.

## Required implementation and verification sequence

1. Map all references to both Maintenance migration filenames in CI workflows, shell scripts, tests, and docs.
2. Decide whether any non-production environment has recorded or applied either migration. Production currently shows no Maintenance objects, but that alone is not proof about every environment.
3. Build a single clean-bootstrap Maintenance migration from the final hardened design; do not run it against production.
4. Update disposable-database workflows and integration tests to apply that single migration and assert the final grants, ownership, RLS policies, RPC behavior, audit protections, idempotency, concurrency, and authorization boundaries.
5. Test failure/rollback behavior in the disposable environment, including role creation and function ownership changes.
6. Run the full existing CI suite and review the diff independently.
7. Only after all gates pass, prepare a separate production baseline/deployment/rollback proposal for explicit approval.

## Rollback posture

For production, do not plan a destructive DROP-based rollback for maintenance tables or append-only audit records. The initial release should remain feature-gated off. Prefer reverting the application/Edge Function release or applying a forward-fix migration. Any database rollback proposal must be based on the exact deployed schema and data state, and separately approved.

## Current status

- Branch created for isolated implementation planning.
- No executable migration changed in this commit.
- No production SQL executed.
- No migration applied.
- No Edge Function deployed.
- No feature flag enabled.
- No PR merged.
