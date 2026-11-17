# Production Migration Baseline Reconciliation v0.1

> Date: 2026-11-17  
> Branch: `feature/maintenance-system`  
> Scope: read-only comparison of current production catalog against repository migration files.  
> Safety: no production DDL/DML, migration-history repair, deploy, merge, secrets, or paid resources.

## 1. Executive result

**Migration baseline: NOT READY for execution.**

The production database has no `supabase_migrations` schema, so there is no migration-history table available to establish which repository migrations were applied. This is not proof that no SQL was ever run: the live schema contains objects matching at least two repository migration files. Do not replay the migration folder wholesale and do not mark migrations as applied without a separately reviewed baseline-reconciliation procedure.

## 2. Repository migration inventory

The feature branch currently contains six SQL migration files:

- `202610310001_app_releases.sql`
- `20261031_app_releases.sql`
- `202611160001_growth_function_authorization_hardening.sql`
- `202611170001_default_privileges_and_trigger_hardening.sql`
- `26.11.3_calendar_fields.sql`

(The listing returned five entries; this report records the five files actually returned by GitHub.)

Two app-release migrations are incompatible alternatives and must not both be treated as sequential migrations.

### 2.1 App release variant A — `202610310001_app_releases.sql`

This file defines `app_releases` with:
- `id`, `version_code`, `version_name`, `release_notes`, `apk_url`
- `published` default false
- nullable `published_at`
- nullable `created_by` referencing `auth.users(id)`
- positive and unique `version_code`
- four admin/public RLS policy patterns, plus explicit table grants.

### 2.2 App release variant B — `20261031_app_releases.sql`

This is a materially different design:
- adds `is_latest`
- `published` defaults true
- `published_at` is NOT NULL with `now()`
- omits `created_by`
- adds HTTPS URL check and a published/latest index
- defines a separate `is_app_release_admin()` SECURITY DEFINER helper and a consolidated admin policy.

These two files are not interchangeable. Their different column contracts and RLS helpers make automatic ordering unsafe.

## 3. Live production comparison

### 3.1 `public.app_releases`

The production catalog matches variant A's table shape:
- all nine columns from variant A exist, including `created_by`
- `published` defaults false
- `published_at` is nullable
- `created_by` references `auth.users(id)`
- `version_code` has a positive CHECK and UNIQUE constraint
- the four live policies match variant A's public-read/admin-read/admin-insert/admin-update/admin-delete policy design.

Production does **not** have the variant B `is_latest` column, its HTTPS URL constraint, its published/latest index, or the `is_app_release_admin()` helper (the helper lookup returned no matching function).

Conclusion: variant A is the only app-release file aligned with the observed live schema. This is schema evidence, not migration-history evidence. Do not replay it against production merely because the history schema is absent.

### 3.2 `26.11.3_calendar_fields.sql`

All four expected columns are present on `public.announcements`:
- `event_date`
- `event_end_date`
- `event_date_source`
- `event_date_confirmed`

Both CHECK constraints and the partial calendar index also exist with definitions matching the migration.

Conclusion: live schema matches this migration's intended result. It should be treated as already reflected in the schema for baseline analysis, not blindly re-executed.

### 3.3 Migration history

- `information_schema.schemata` contains no `supabase_migrations` schema.
- `information_schema.tables` contains no migration-history table under that schema.

This means the normal Supabase migration ledger is unavailable in this project snapshot. It does not tell us who executed the SQL or when.

## 4. Current object and privilege observations

- The production `public` schema contains the existing application tables and views; the `private` schema and maintenance objects remain absent.
- All listed ordinary public tables in the catalog query had RLS enabled.
- `app_releases` currently has broad table ACL entries for API roles, including DML-level grants. The RLS policies still constrain which rows/actions succeed, but the grants are broader than a least-privilege design and should be handled in a separately reviewed privilege-hardening change. Do not conflate table grants with RLS policy authorization.
- The `announcements` calendar columns, constraints and partial index are already present, so a second application of the same migration is unnecessary and may cause avoidable locking/DDL churn even where `IF NOT EXISTS` is used.

## 5. Required safe next steps

1. Obtain a complete read-only schema dump/catalog snapshot for all application schemas, including columns, constraints, indexes, triggers, policies, grants, functions, sequences, views, and extensions.
2. Compare every repository migration's intended post-state to the live catalog; classify each as `already reflected`, `partially reflected`, `not present`, or `conflicting/ambiguous`.
3. Resolve the app-release migration fork explicitly. Variant A is the schema-aligned historical candidate; variant B must not be replayed.
4. Create a reviewed baseline plan that does not mutate production. Any migration-ledger adoption or baseline repair requires explicit approval and a tested recovery path.
5. Separately review broad table ACLs and default privileges; do not mix this with migration-history reconstruction.
6. Only after a full catalog comparison and disposable restore test should a production migration execution plan be proposed.

## 6. Status

- Read-only schema comparison: **partial, high-confidence for app_releases and announcements calendar objects**.
- Migration ledger: **absent/unavailable**.
- App-release migration fork: **identified; variant A matches live schema**.
- Full migration baseline: **NOT APPROVED**.
- Production changes, migration execution, deployment, merge, and paid resources: **none**.
