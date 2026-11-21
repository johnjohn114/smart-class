# Maintenance backend readiness review — 2026-11-22

## Scope and safety

This is a review note only. It does not change application behavior, add a migration, deploy an Edge Function, or execute SQL against Supabase production.

Reviewed against `integration/maintenance-pagination-hardening-main-20261121`:
- Draft PR #31 and its current head commit `5cd64d061768147cf0e57b4bf93f7902b3166b1b`
- `supabase/functions/_shared/maintenance.ts`
- The five Maintenance Edge Function entry points
- The ordered Maintenance migrations and the separate private-schema/RPC development draft

## Current implementation found

### Request and identity path

- `maintenance-status` is GET with optional authentication.
- `maintenance-admin-list` is GET and requires authentication.
- `maintenance-event-create`, `maintenance-event-update`, and `maintenance-event-action` are POST and require authentication.
- The shared handler validates a required bearer token through Supabase Auth's `/auth/v1/user` endpoint. Invalid credentials fail with 401; an unavailable Auth service fails closed with 503.
- The admin RPCs independently require `auth.uid()` and `public.is_admin()`. The Edge Function's successful token validation is not treated as proof of administrator status.
- The shared request parser restricts methods, JSON size, UTF-8 decoding, accepted fields, UUIDs, timestamps, scope codes, and action names.

### Database protection and lifecycle

- The public status RPC is `SECURITY INVOKER`; the administrative RPCs are `SECURITY DEFINER` with an empty search path.
- The least-privilege upgrade creates `maintenance_rpc_executor` as NOLOGIN and NOBYPASSRLS, forces RLS on the six private tables, restricts mutation policies to that role, transfers the administrative RPC ownership to it, and removes PUBLIC/anon execution grants.
- The upgrade grants authenticated users SELECT but removes their direct table write privileges.
- Audit rows have UPDATE/DELETE rejection triggers and a TRUNCATE rejection trigger.
- Write RPCs use idempotency keys and event versions. The update/action RPCs lock the target event row and reject stale versions.
- Create, update, and schedule operations use a transaction-scoped advisory lock and check overlapping scheduled windows. A global event conflicts with all overlapping scopes; the `site_core` scope also conflicts broadly.
- Public maintenance state is derived from a scheduled event whose start/end window contains the database server time. The public status RPC does not depend on a separate mutable global on/off flag.

## Corrections to the earlier preliminary checklist

The earlier note described state consistency, schedule conflict handling, and administrator validation as still needing implementation. The current integration branch already contains mechanisms for all three:
1. State is derived from the event status and time window.
2. Overlapping schedules are checked under a shared advisory transaction lock.
3. Both the Edge Function path and the database RPC enforce identity/administrator checks.

These mechanisms still require end-to-end verification; source inspection alone does not prove production behavior.

## Remaining release gates

1. **Keep PR #31 as Draft until review is complete.** Its branch is ahead of main and is not production code yet.
2. **Run/confirm the complete isolated CI suite** on the exact head commit, including SQL migration tests, RPC privilege tests, Edge Function tests, and browser compatibility tests.
3. **Review the exact migration pair in order**:
   - `20261117121103_maintenance_system_initial.sql`
   - `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
   Confirm that the first migration cannot be accidentally treated as the final secure state without the upgrade.
4. **Use a disposable database for integration tests** with anon, authenticated non-admin, authenticated admin, and missing/invalid JWT cases. Verify direct table writes are denied, admin RPC writes succeed only for admins, public status reveals no internal notes, and Auth outages fail closed.
5. **Verify the production preflight read-only** before any migration: `public.is_admin()`, existing schema/table/function/role names, exposed schemas, current grants, and migration history must match the migration assumptions.
6. **Deploy only after separate approval**, in a controlled order: migrations, Edge Functions, smoke tests with the feature flag still disabled, then a separately approved feature-flag enablement.
7. **Prepare rollback steps** for both database objects and Edge Functions before any production change.

## Explicitly not done

- No Supabase production SQL was run.
- No migration was applied.
- No Edge Function was deployed.
- No production feature flag was enabled.
- No PR was merged and no deployment was triggered.


## Production read-only preflight — 2026-11-22

The following checks were run against the production Supabase project using metadata queries and SELECT-only SQL. No DDL/DML was executed.

### Verified production facts

- Project is ACTIVE_HEALTHY on PostgreSQL 17.11.
- public.is_admin() exists as a SECURITY DEFINER SQL function with an empty search_path; it checks profiles.id = auth.uid() and profiles.role = 'admin'. The observed ACL grants EXECUTE to authenticated and service_role, not anon.
- The private schema does not exist.
- None of the six current Maintenance tables exists: maintenance_scopes, maintenance_events, maintenance_event_private_notes, maintenance_event_scopes, maintenance_audit_logs, or maintenance_idempotency.
- No Maintenance-named database routines or Maintenance Edge Functions were found.
- maintenance_rpc_executor does not exist.
- Supabase's migration listing returned no migrations, and supabase_migrations.schema_migrations does not exist.
- The live public.app_releases columns match 202610310001_app_releases.sql (including published_at and created_by, and no is_latest).
- The four calendar columns from 26.11.3_calendar_fields.sql already exist on public.announcements.

### Migration baseline blocker

The integration branch currently contains seven migration files. The two app_releases migrations are not compatible with each other when applied in sequence: the first creates the live table shape without is_latest; the later file uses CREATE TABLE IF NOT EXISTS and then creates an index referencing is_latest. On a database with the live shape above, that later index statement cannot succeed because the column is absent.

Because the production migration history is absent, a normal supabase db push must not be run against the current repository as-is. It may try to replay historical migrations against a database that already contains their effects, and the conflicting app-release scripts are a concrete failure point. Before any push, reconcile all seven files against the live schema and define a reviewed baseline/history-repair procedure. Do not mark migrations as applied merely to silence the CLI; each one needs evidence that its effects are already present and equivalent.

### Security ordering blocker in the Maintenance migration pair

The initial Maintenance migration is not the final least-privilege state. It grants authenticated direct INSERT/UPDATE/DELETE capabilities on several private tables, and its admin write RPCs are SECURITY INVOKER. The second migration later creates the NOBYPASSRLS executor role, forces RLS, moves mutation policies to that role, removes direct authenticated write grants, and changes the administrative RPCs to SECURITY DEFINER.

Therefore the initial migration must never be treated as a completed release state. If migration one succeeds and migration two fails, the database is left in an intermediate state with direct authenticated table writes allowed by admin RLS policies, which can bypass the RPC-level audit/idempotency/version workflow. Before production use, restructure the pair so the secure state is installed as one reviewed deployment unit (preferably a single migration or a secure initial migration with no temporary direct-write grants), then rerun the isolated tests.

### Exposed schemas and rollback

- The database catalog confirms that a private schema is not currently present; it cannot confirm the Supabase Dashboard Data API Exposed schemas setting for a future schema. Before release, verify that private remains excluded from Exposed schemas in the Dashboard. Schema grants alone are not a substitute for this API boundary.
- Rollback must be forward-safe. Before any Maintenance event exists, a reviewed down-plan may remove newly created objects after confirming no deployed code depends on them. Once event/audit/idempotency records exist, do not drop the schema or tables as routine rollback: disable the application feature/Edge Function route while preserving records, then apply a reviewed forward fix. Keep the production feature flag disabled until smoke tests pass.
- Edge Function deployment and feature-flag enablement remain separate approval gates.

### Supabase Advisor baseline observed

The production Security Advisor reported two INFO findings for RLS-enabled tables without policies, one ERROR for public.activity_member_stats being a SECURITY DEFINER view, 34 anon-executable SECURITY DEFINER function warnings, 34 authenticated-executable SECURITY DEFINER function warnings, and one Auth leaked-password-protection warning. These are existing project-wide findings, not Maintenance objects. They need a separate triage; do not silently modify unrelated functions/views as part of the Maintenance rollout.

### Updated release decision

**BLOCKED — do not run supabase db push, apply either Maintenance migration, deploy Maintenance Edge Functions, merge PR #31, or enable the feature flag yet.**

Required order:
1. Reconcile all seven historical migrations with the live schema; resolve the duplicate/conflicting app-release migration and establish a trustworthy migration baseline.
2. Restructure the Maintenance migration pair so no intermediate direct-write state can be left behind.
3. Verify Data API Exposed schemas and rerun the full disposable-database CI suite against the final migration sequence.
4. Prepare a schema backup, event-data retention plan, and tested rollback/forward-fix runbook.
5. Only then request separate approval for production migration, Edge Function deployment, smoke tests, and feature-flag activation.

This addendum records review findings only. It does not modify runtime code or production Supabase.


## Historical migration-by-migration reconciliation — 2026-11-22

The following comparison adds catalog evidence from production. It remains read-only.

| Repository migration file | Live evidence | Assessment |
|---|---|---|
| 202610310001_app_releases.sql | The live app_releases columns, constraints, unique version index, and five RLS policies match this file's shape and policy model. | Strong match, but do not mark applied until every grant/default and table property is compared. |
| 20261031_app_releases.sql | Live app_releases has no is_latest column, no is_app_release_admin() helper, and no published index referencing is_latest. | Not equivalent to live schema. Its index statement would fail against the current table shape. The filename also does not follow the documented 14-digit timestamp convention; validate CLI recognition before any migration operation. |
| 202611160001_growth_function_authorization_hardening.sql | Several target growth functions exist, but live public default function privileges still grant anon/authenticated EXECUTE, and sampled functions such as admin_delete_growth_reward and refresh_growth_level still have anon EXECUTE. | The hardening effects are not present as a complete set. Do not mark applied. The function definitions and all ACLs need a per-function diff before deciding whether any parts were applied manually. |
| 202611170001_default_privileges_and_trigger_hardening.sql | Live postgres default ACLs in public still grant anon/authenticated/service_role table privileges, sequence privileges, and function EXECUTE. | The intended default-privilege hardening is not present. Do not mark applied. |
| 20261117121103_maintenance_system_initial.sql | private schema, all six Maintenance tables, Maintenance RPCs, and supporting role/policies are absent. | Not applied. |
| 20261121140000_maintenance_rpc_least_privilege_upgrade.sql | maintenance_rpc_executor, Maintenance tables, and Maintenance RPCs are absent. | Not applied; it depends on the initial Maintenance migration. |
| 26.11.3_calendar_fields.sql | All four calendar columns, both named check constraints, and the partial calendar index exist with matching definitions. | Strong match, but do not mark applied until the full ALTER/index effects and migration filename recognition are verified. |

### Important baseline conclusion

A migration file's apparent match to the live schema is not sufficient evidence to mark it applied. The live project has no visible migration history table, while at least two migration files do not match the live schema and two hardening migrations' intended ACL/default-ACL effects are absent. The baseline must be reconstructed from a full schema-only comparison and file-by-file evidence; no blanket migration repair status applied operation is safe.

### CLI documentation note

Current Supabase CLI documentation explains that migration repair changes only the migration-history records and does not execute or reverse SQL. Therefore it must only be used after independently proving that each migration's effects are already present (or absent for a reverted status). CLI v3 also changed hosted-command targeting and confirmation behavior; any later operator run must use explicit remote targeting and inspect the installed CLI version first.

No migration history was repaired and no remote command was run.


## Proposed migration cleanup plan — review only

This section is a plan, not an instruction to run SQL. No historical migration file or runtime code was changed as part of this review.

### A. Preserve history; do not silently rewrite old files

1. Keep the seven existing SQL files intact while reconstructing their actual execution history and effects.
2. Treat the two app-release scripts as competing historical definitions, not as sequential migrations:
   - `202610310001_app_releases.sql` is the best match for the current live table shape and current five policies.
   - `20261031_app_releases.sql` describes a different table contract (`is_latest`, HTTPS URL check, helper function and different policy names). It is not a safe follow-on migration for the current live table.
3. Before any CLI history operation, confirm the installed Supabase CLI version and how it parses the non-standard eight-digit filename `20261031_app_releases.sql` and the dotted filename `26.11.3_calendar_fields.sql`. Do not rename them in place until their source-control and deployment history is understood.
4. The calendar migration's columns, constraints and index are present in production. Capture a full schema-only definition and verify grants, RLS state, and exact constraint/index definitions before considering a history baseline entry.
5. The two hardening migrations are not equivalent to the current live ACL/default-ACL state. Do not mark them applied. Review their complete function definitions, object ACLs, and default ACL side effects before applying them in an isolated clone.

### B. Establish a trustworthy baseline

1. Export a schema-only snapshot from production using a trusted Supabase backup/export process; do not include row data or secrets in the public GitHub repository.
2. Compare all seven files with the live catalog, including table columns/defaults/constraints/indexes, RLS and policies, function bodies/security modes/search_path/ACLs, triggers, sequences, and default privileges.
3. Build an evidence table for each file with one of: fully present and equivalent, partially present/drifted, absent, or not safely classifiable.
4. Only fully present and equivalent files may be considered for a migration-history repair entry. Partially present/drifted files must be split into a reviewed forward-fix migration; absent files may be scheduled as new migrations after their dependencies are validated.
5. Never use a blanket repair-all-applied operation. Never use history repair as a substitute for executing SQL.

### C. Resolve the app-release migration conflict

1. Keep the live `app_releases` contract as the source of truth unless a separately approved product change requires a schema redesign.
2. Do not apply the legacy `is_latest` script to production. First determine whether any client code or historical release notes depend on `is_latest`, `is_app_release_admin()`, or its alternate policy names.
3. If the second script is obsolete, move it out of the active migration queue only through a reviewed repository change that preserves the original SQL in an archival location and documents why it is not runnable against the live contract. Do not delete the historical source.
4. Confirm migration filename/version conventions with the actual CLI before choosing an archive or replacement filename.

### D. Harden existing application permissions separately from Maintenance

1. Review the growth hardening migration function-by-function against production definitions. In particular, compare every `CREATE OR REPLACE FUNCTION` body, SECURITY DEFINER/INVOKER mode, `search_path`, owner, and EXECUTE ACL.
2. Review the default-privilege migration as a separate, high-impact change: it changes future object defaults for the postgres owner in public and removes direct API-role EXECUTE from several trigger functions. Test new table/sequence/function creation and all affected app workflows in an isolated PostgreSQL 17 environment.
3. Preserve Supabase-managed schemas and defaults; do not expand the change to storage or other platform-owned schemas without a separate review.
4. Run regression tests for visitor creation, profile triggers, growth tasks/rewards, registration, announcements, app releases, and all RPCs before approving these hardening migrations.

### E. Rebuild Maintenance as one secure release unit

1. Produce one final initial Maintenance migration whose first committed state already has the executor role, FORCE RLS, restricted table grants, safe mutation policies, and SECURITY DEFINER admin RPCs.
2. Remove the temporary direct authenticated INSERT/UPDATE/DELETE grants and temporary SECURITY INVOKER write-RPC state from the initial deployment path. The least-privilege upgrade migration must not be required to make the initial deployment safe.
3. Keep the public status RPC SECURITY INVOKER and keep the private schema excluded from Data API Exposed schemas.
4. Run the existing disposable PostgreSQL + GoTrue/PostgREST + Deno/Playwright test suite against only the final migration sequence. Include a failure-injection check proving that no partially applied intermediate state can be committed.
5. Keep production deployment, Edge Function deployment, feature-flag activation, and PR merge as separate approval gates.

### F. Next implementation sequence

- Step 1: Complete the schema-only production export and the exact per-function/default-ACL diff. Read-only only.
- Step 2: Prepare a repository-only migration archive/baseline proposal with a file-by-file evidence ledger; do not run remote migration repair.
- Step 3: Create a separate integration branch change for the app-release conflict and secure Maintenance migration consolidation.
- Step 4: Run isolated tests and compare the resulting schema/ACLs with the approved target.
- Step 5: Present the diff and test results for review before any production operation.

**Current permission boundary:** this approval covers analysis and repository review planning only. It does not authorize production SQL, migration repair, Edge Function deployment, feature flag changes, PR merge, or changes to the live site.
