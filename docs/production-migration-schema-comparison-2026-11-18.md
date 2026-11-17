# Production schema vs repository migration comparison

**Date:** 2026-11-18  
**Branch:** `docs/activity-view-migration-baseline-rollback-20261118`  
**Method:** Read-only PostgreSQL catalog inspection compared with the exact SQL files on GitHub `main`.  
**Production writes:** None.

## Executive result

The repository's migration files do not have a trustworthy application-level execution ledger in this project. Therefore this document reports **live schema match / mismatch**, not a definitive historical statement that a migration command was run.

| Repository migration | Live production evidence | Assessment |
|---|---|---|
| `202610310001_app_releases.sql` | The `app_releases` columns, `version_code` unique/check constraints, `created_by -> auth.users(id)` FK, and five named RLS policies match this file's design. | **Schema matches.** Execution history unproven. |
| `20261031_app_releases.sql` | Production does not have `is_latest`, the HTTPS URL check, or `is_app_release_admin()`; it has the first file's `created_by` field and policy set. | **Conflicting alternative. Do not apply.** |
| `26.11.3_calendar_fields.sql` | All four calendar columns, both named check constraints, and `announcements_calendar_event_date_idx` exist with matching definitions. | **Schema matches.** Execution history unproven. |
| `202611160001_growth_function_authorization_hardening.sql` | Several live function definitions remain the older versions, and the candidate's expected effective ACL changes are not reflected. | **Not fully reflected; treat as unapplied pending isolated review.** |
| `202611170001_default_privileges_and_trigger_hardening.sql` | Live `postgres` defaults in `public` still grant broad table, sequence, and function privileges to API roles; old SECURITY DEFINER function bodies/ACL behavior remain. | **Not reflected; do not assume applied.** |
| `20261117121103_maintenance_system_initial.sql` | No `private` schema, none of the six maintenance tables, no `maintenance_*` public RPCs, and no maintenance triggers were found. | **Not deployed in production.** |

## Detailed evidence

### A. App releases

Live `public.app_releases` has these columns:

`id, version_code, version_name, release_notes, apk_url, published, created_at, published_at, created_by`.

The live constraints include:

- `app_releases_version_code_key`: UNIQUE (`version_code`)
- `app_releases_version_code_check`: `version_code > 0`
- `app_releases_created_by_fkey`: `created_by` references `auth.users(id)`

Live policies are:

- `Public can read published app releases`
- `Admins can read all app releases`
- `Admins can insert app releases`
- `Admins can update app releases`
- `Admins can delete app releases`

This matches `202610310001_app_releases.sql` at the inspected schema/policy level. The alternate `20261031_app_releases.sql` is not a safe follow-up: it describes a different schema and policy/function design. Do not run it to "complete" the first migration.

### B. Calendar fields

Live `public.announcements` contains:

- `event_date date`
- `event_end_date date`
- `event_date_source text`
- `event_date_confirmed boolean NOT NULL DEFAULT false`

The two named constraints exist with the expected rules:

- `announcements_event_date_source_check`: source is NULL, `manual`, or `auto`.
- `announcements_event_date_range_check`: end date is NULL, start date is NULL, or end date is not before start date.

The partial calendar index `announcements_calendar_event_date_idx` also exists. This is a schema match, not a migration-ledger proof.

### C. Growth function authorization

The candidate `202611160001_growth_function_authorization_hardening.sql` contains updated function bodies and targeted ACL changes. Live catalog evidence still shows old function bodies:

- `admin_delete_growth_reward` still checks only `caller_role <> 'admin'`; it does not include the candidate's explicit `auth.uid() IS NULL` and `caller_role IS DISTINCT FROM 'admin'` fail-closed guard.
- `check_activity_badges` still uses `p_user_id <> auth.uid()` without the candidate's explicit NULL-authentication guard and `IS DISTINCT FROM` comparison.
- `refresh_growth_level` still has no caller identity/admin authorization guard in its body.
- `complete_growth_task` is still the older function body, including the unqualified row type from the old implementation rather than the candidate's explicitly qualified type and relations.

The live effective privilege check reports `anon` can execute all of these inspected routines, including `award_growth_points`, `check_growth_achievements`, `refresh_growth_level`, and `admin_delete_growth_reward`. This is not the intended hardened state.

**Important follow-up:** The candidate growth migration by itself does not visibly revoke anonymous execution from every old SECURITY DEFINER RPC. The later default/trigger hardening migration contains a broader SECURITY DEFINER allowlist pass. Both files need a combined isolated regression review, including dependency checks, before production approval. Do not apply either file directly to production.

### D. Default privileges and trigger hardening

The live default ACL snapshot for owner `postgres`, schema `public`, still shows:

- Tables: `anon`, `authenticated`, and `service_role` have broad `arwdDxtm` defaults.
- Sequences: those API roles have `rwU` defaults.
- Functions: those API roles have `X` defaults.

These do not match `202611170001_default_privileges_and_trigger_hardening.sql`, which revokes the API roles' public-schema table/sequence/function defaults and removes global PUBLIC function execute defaults for future postgres-owned functions.

All five trigger functions inspected still have one trigger binding each:

- `assign_member_no_and_nickname`
- `check_competition_registration_rules`
- `ensure_visitor_profile`
- `growth_registration_reward`
- `growth_result_reward`

Keep those trigger bindings intact in any future ACL hardening. A trigger function does not need to be directly callable as a PostgREST RPC; the migration's revocation must be tested to ensure the trigger itself continues to fire.

### E. Maintenance system

The production catalog has no `private` schema. No maintenance tables, maintenance public RPCs, or maintenance triggers were found.

The repository migration defines six tables under `private`:

- `maintenance_scopes`
- `maintenance_events`
- `maintenance_event_private_notes`
- `maintenance_event_scopes`
- `maintenance_audit_logs`
- `maintenance_idempotency`

It also defines five public RPCs:

- `maintenance_status_public(jsonb)`
- `maintenance_admin_list(jsonb)`
- `maintenance_event_create(jsonb)`
- `maintenance_event_update(jsonb)`
- `maintenance_event_action(jsonb)`

This migration is not deployed to the inspected production database. Do not treat its existence in Git as proof that the maintenance backend is active.

## Recommended next steps

1. Preserve the two matching schema baselines (`app_releases` and calendar fields) as "live schema matches; ledger unproven".
2. Keep the alternate app-release migration blocked.
3. Combine growth authorization and default-privilege migrations in isolated PostgreSQL 17 tests; verify every exposed SECURITY DEFINER signature, the intended API-role allowlist, all trigger behavior, and RPC dependencies.
4. Review the maintenance migration separately against its outstanding product/backend requirements before considering a rollout.
5. Keep all production DDL/DML blocked until the above reviews, a sanitized production-like rehearsal, and an explicit release approval are complete.

## No-write attestation

All production observations in this report came from catalog/read-only SELECT queries. No production schema, grants, RLS policies, function definitions, table rows, or deployment settings were changed.
