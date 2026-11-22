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


## Follow-up inspection — existing single-pass draft discovered

The integration branch already contains `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`, a development-only single-pass draft. It creates the executor role before the tables/RPCs, establishes FORCE RLS and executor-targeted mutation policies, creates the public SECURITY INVOKER status RPC and SECURITY DEFINER admin RPCs, then transfers admin RPC ownership to the dedicated executor and applies explicit execute ACLs. It is materially closer to the intended final bootstrap than concatenating the two migration files.

The draft is not yet approved as an executable migration. It needs a full static review and disposable-database test, including function ownership/CREATE privilege transitions, role memberships and grants, policy behavior under real JWT claims, public Data API schema exposure assumptions, and all RPC/error/concurrency cases.

### Critical migration-history constraint

The two existing Maintenance files remain under `supabase/migrations/`. Adding a third single-pass migration does not prevent the existing initial migration from running first. It would preserve the intermediate-privilege window and defeat the purpose of a single-pass bootstrap.

Before changing the migration directory, establish whether either old Maintenance migration has been applied in any shared, preview, staging, or developer database. If all target environments are confirmed clean and unapplied, the correct approach may be to replace/squash the unapplied migration files and update every CI/test/script reference together. If any environment has applied them, do not rewrite migration history there; prepare a forward-upgrade path instead. Production having no Maintenance objects is not sufficient evidence about all environments.

### CI reference inspection status

The Playwright browser compatibility test was inspected and exercises the feature gate, idempotency key persistence, and cursor pagination using a stubbed maintenance request. It does not execute SQL or establish database migration compatibility. The exact workflow file path and all migration filename references still need to be enumerated from the integration branch before editing CI. A guessed workflow path returned 404 and was not treated as evidence.

## Updated status

- Existing single-pass SQL draft located and reviewed in sections.
- No new executable migration created yet; this is intentional pending migration-history and CI-reference checks.
- No production SQL executed, no deployment, no feature flag change, no merge.


## CI and repository reference inventory — 2026-11-22

Inspected the recursive Git tree at integration commit `5cd64d061768147cf0e57b4bf93f7902b3166b1b`, the workflow directory, SQL test directory, and relevant test runner files.

### Direct references to the two current Maintenance migration files

1. `.github/workflows/maintenance-edge-functions.yml`
   - GoTrue/PostgREST job applies both files sequentially with explicit `psql -f` commands.
2. `supabase/tests/sql/maintenance-postgres-isolated.test.sql`
   - Includes both files using psql `\\ir` directives.
3. `supabase/migrations/`
   - Both migration files are present as ordered migration history entries.

### Draft-based static guardrail references

- `scripts/verify_maintenance_sql_draft.py` reads `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`.
- `tests/test_verify_maintenance_sql_draft.py` tests that static verifier; it does not itself directly name either timestamped migration.
- `maintenance-edge-functions.yml` runs both the verifier and its unit tests, and watches changes under `supabase/sql/**` and `supabase/migrations/**`.

### Separate migration-generation workflow

- `.github/workflows/generate-maintenance-v1-migration.yml` generates a timestamped shell on the separate branch `migration/maintenance-v1-20261117`. It does not apply either current Maintenance migration in the integration workflow, but its branch-specific behavior should be checked before retiring or reusing that migration branch.

### Important environment-history limitation

Repository and CI inspection cannot establish whether a migration has been applied to a developer, preview, staging, or other shared database. The production read-only inspection found no Maintenance objects, but that is only evidence about the inspected production project. Before squashing/replacing timestamped migration files, obtain an explicit inventory of all databases/environments and their migration history. If any environment has applied either file, preserve its history and use a forward-upgrade path for that environment.

### Required coordinated edits once history is known

If all target environments are confirmed clean and unapplied, update together:
- replace/squash the two timestamped migration files with the final single-pass bootstrap (preserving a clear migration timestamp);
- change the two direct apply references in the workflow and isolated SQL harness to the single new file;
- retain/update static draft verification so the tested SQL source and migration cannot silently drift (prefer testing the actual migration file or asserting byte-for-byte generation/source parity);
- run both PostgreSQL isolated and GoTrue/PostgREST integration jobs, plus Deno, feature-gate, Playwright, and static SQL checks.

If any environment has applied the old pair, do not rewrite its history; write a forward migration and retain the old migration references for fresh installs unless a carefully coordinated baseline/squash strategy is documented for every environment.

## Updated status

- Exact direct migration references identified: 2 execution locations plus migration directory entries.
- Static draft verifier reference identified.
- No SQL or CI files changed in this review step.
- No evidence yet about migration history in non-production environments; this remains the decision gate before executable edits.


## Environment inventory check — 2026-11-22

Read-only account inventory found:
- Supabase account exposes one project: `private-website` (`fsoowongtavlsrwvzbze`).
- That project has no Supabase-managed development branches.
- Repository history document `docs/migration-history-reconciliation-v0.2.md` explicitly states Git commit history cannot prove SQL execution, and that Dashboard SQL Editor / deployment records had not been obtained.
- Existing repository documentation records no Supabase CLI, Docker, psql, or pg_dump in the earlier local verification environment.

This narrows the known Supabase-managed environment inventory to one production project, but does not prove that no external/local/manual PostgreSQL database exists or that no one has run the Maintenance migrations there. User confirmation is still required before rewriting the timestamped migration history.

No additional Supabase project or branch was created. No SQL was executed.


## Isolated draft test alignment — 2026-11-22

Updated `supabase/tests/sql/maintenance-postgres-isolated.test.sql` so its ephemeral PostgreSQL harness applies the exact single-pass development draft:

`supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`

This separates two distinct test purposes:
- PostgreSQL-only isolated harness: validates the single-pass draft's schema, grants, ownership, RLS, RPC behavior, audit protections, and lifecycle behavior using test-only auth stubs.
- GoTrue/PostgREST integration harness: continues to exercise the currently committed two-migration legacy path with real GoTrue-issued JWTs. This is retained as a compatibility/forward-upgrade baseline until the migration-history decision is evidence-based.

The old timestamped migrations were not edited or deleted. No production SQL was executed, no migration was applied, and no Supabase environment or paid branch was created.

This edit only changes the isolated test harness include target; a successful GitHub Actions run is still required before claiming the draft passes database integration tests.


## First-stage closeout review — 2026-11-22

### Latest CI result

GitHub Actions run [#270](https://github.com/johnjohn114/smart-class/actions/runs/44997928704), commit `182eef7377a313c3f98431410daee2608aef1f73`, completed successfully with all four jobs green:

- Isolated PostgreSQL RPC/RLS and regression suite.
- GoTrue-issued JWT + PostgREST integration against the legacy two-migration path.
- GoTrue-issued JWT + PostgREST integration against the single-pass draft.
- Deno type check, 27 validation tests, feature-gate checks, Playwright browser compatibility/lifecycle tests, and SQL static guardrails.

The browser suite verifies the existing homepage shell and default-off behavior, admin login shell and hidden maintenance tab, public maintenance banner rendering, admin create/edit/schedule/complete/cancel flows, cursor pagination, and Taipei UTC+8 conversion. The browser lifecycle operations use an in-memory API mock; the separate GoTrue/PostgREST jobs exercise the Edge handler and database behavior in disposable CI services. Neither path is a hosted production Supabase test.

### Integration and release posture

- `MAINTENANCE_FEATURE_ENABLED` remains `false`; the production maintenance tab stays hidden and the public client does not issue maintenance-status requests while disabled.
- The maintenance implementation remains behind the feature gate. No production SQL, migration, Edge Function deployment, feature flag change, or production data modification occurred.
- PR #31 and PR #34 remain open Draft pull requests; neither is merged.
- PR #34 remains stacked on PR #31's integration branch; it has not been retargeted to `main`.

### Remaining release gates

1. Confirm whether any local, manual, preview, staging, or shared database has ever applied either timestamped Maintenance migration. The available Supabase account inventory identifies one production project and no Supabase-managed branches, but cannot prove the absence of external/local/manual databases.
2. Reconcile the production schema baseline and migration history before selecting a clean-bootstrap replacement or forward-upgrade path. Do not rewrite timestamped migration history without that evidence.
3. Confirm the Data API Exposed schemas configuration, production CORS/origin settings, required Edge Function environment variables, and deployment procedure.
4. Only after the above are reviewed and separately authorized: prepare deployment and rollback steps, deploy to a non-production environment if available, and run hosted smoke tests before considering feature enablement.

This closeout does not include the separately scheduled January 2027 security review. No security scope was expanded by this documentation update.


## User environment-history clarification — 2026-11-22

The user recalls that they probably have not manually run the Maintenance SQL in a local or other test database, but expressed uncertainty ("好像沒有"). Record this as an unverified recollection, not as proof that all non-production environments are clean.

Current environment-history evidence:

- The known Supabase account inventory contains one production project and no Supabase-managed development branches.
- CI PostgreSQL / GoTrue / PostgREST databases are disposable test environments created by workflows; they are not persistent user-managed environments and do not establish the history of any local or manually managed database.
- No evidence has been provided for a separate local, preview, staging, shared, or manually administered database.
- The existing timestamped Maintenance migrations must remain unchanged until this uncertainty is resolved.

Decision:

- Do not squash, delete, rename, replace, or reorder either timestamped Maintenance migration yet.
- Do not create or apply a replacement migration.
- If the user later confirms that no other database/environment exists or has applied either migration, record that explicit confirmation and re-check repository/environment inventory before proposing a coordinated clean-bootstrap change.
- If any environment is found to have applied either migration, preserve its history and evaluate a forward-upgrade path for that environment.

No SQL was run and no database, branch, feature flag, deployment, or production data was changed as part of this clarification.


## Final first-stage CI confirmation — 2026-11-22

After the closeout review and environment-history clarification above, documentation-only commit(s) triggered GitHub Actions run [#271](https://github.com/johnjohn114/smart-class/actions/runs/44998262133). All four jobs completed successfully:

- Isolated PostgreSQL RPC/RLS tests.
- Deno type check, validation tests, feature-gate tests, Playwright compatibility tests, and SQL static guardrails.
- GoTrue-issued JWT + PostgREST integration using the legacy two-migration path.
- GoTrue-issued JWT + PostgREST integration using the single-pass draft path.

This is CI evidence from disposable test services, not a hosted production Supabase or deployed Edge Runtime validation. The legacy and single-pass tracks are separate test paths; the result does not authorize migration-history rewriting or production execution.

### First-stage disposition

- First-stage implementation and isolated test documentation are recorded.
- CI run #271 is green (4/4 jobs).
- Migration-history uncertainty remains open; the user's recollection is "probably not applied" and is not treated as confirmation.
- Both timestamped Maintenance migrations remain unchanged.
- PR #31 and PR #34 remain Draft and unmerged.
- Production feature flag remains off; no production SQL, migration, Edge deployment, or website release was performed.
- The January 2027 security review remains separate and is not advanced by this closeout.

**Disposition:** documentation and isolated CI closeout complete; production readiness is not established. Keep the feature disabled and do not merge or deploy until the remaining environment-history and hosted-release gates are resolved with separate approval.
