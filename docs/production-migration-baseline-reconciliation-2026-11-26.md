# Production migration baseline reconciliation — 2026-11-26

## Scope and safety

This is a read-only comparison of the connected Supabase production catalog with the repository's `main` migration directory and the candidate PR branch. No production SQL was executed that changes data, schema, grants, policies, or functions. No deployment or merge was performed.

Project ref: `fsoowongtavlsrwvzbze`  
Repository: `johnjohn114/smart-class`  
PR: #41  
Candidate head at time of inspection: `2202165bc8bd8a30916c1dca97e1c0733f56abca`

## Executive result

**The production application migration baseline is not reconstructable from the current repository migration directory alone.** The `main` branch contains six migration files, while the production `public` schema contains 44 tables and one view. Several production objects match individual migration scripts, but the core schema's creation history is not represented in the available migration set. No application-owned migration history table/schema was found, and the Supabase migration-list interface returned an empty application migration list.

This is not proof that migrations were never applied. It means their application history and order cannot currently be independently verified.

## Repository migration inventory

The `main` branch `supabase/migrations` directory currently contains:

1. `202610310001_app_releases.sql`
2. `20261031_app_releases.sql`
3. `202611160001_growth_function_authorization_hardening.sql`
4. `202611170001_default_privileges_and_trigger_hardening.sql`
5. `20261117121103_maintenance_system_initial.sql`
6. `26.11.3_calendar_fields.sql`

The candidate PR adds migrations `202611250001` through `202611250005`; these are candidate-only and have not been applied to production.

## Confirmed object comparisons

| Area | Repository definition | Production catalog observation | Result |
|---|---|---|---|
| `app_releases` | `202610310001_app_releases.sql` | Columns include `version_code`, `version_name`, `published`, `published_at`, and `created_by`; FK `created_by -> auth.users`; positive version check; policies match the first script | Matches first script |
| `app_releases` duplicate | `20261031_app_releases.sql` | This script defines `is_latest`, omits `created_by`, and adds a different APK URL constraint/index | Conflicting variant; do not run as an additional migration |
| Announcement calendar | `26.11.3_calendar_fields.sql` | All four calendar columns, both date checks, and the partial calendar index are present | Matches inspected objects |
| Maintenance system | `20261117121103_maintenance_system_initial.sql` | No `private` schema or its maintenance tables were found | Not present in production |
| Growth executor | Candidate migration `202611250001` | `growth_points_executor` role is absent; current growth RPC ownership remains `postgres` | Candidate prerequisite not present |
| Growth default ACL hardening | `202611160001` | Current `award_growth_points` and `refresh_growth_level` ACLs still include API-role EXECUTE; `_refresh_growth_level_internal` was not found; public default EXECUTE grants remain | Expected effects not present |
| Default privileges and trigger hardening | `202611170001` | `postgres` public-schema defaults still grant broad table, sequence, and function privileges to API roles | Expected effects not present |

## Current production growth RPC ACL observations

The read-only catalog showed:

- `award_growth_points(uuid, integer, text, text, text, text, uuid)`: EXECUTE granted to `postgres`, `anon`, and `service_role`.
- `refresh_growth_level(uuid)`: EXECUTE granted to `postgres`, `anon`, `authenticated`, and `service_role`.
- `check_growth_achievements(uuid)`: EXECUTE granted to `postgres`, `anon`, `authenticated`, and `service_role`.
- `check_activity_badges(uuid)`: EXECUTE granted to PUBLIC/default, `postgres`, `anon`, `authenticated`, and `service_role`.

These observations support the need for the candidate ACL work, but do not by themselves prove exploitability of every function. Caller checks, triggers, RLS, and function bodies must still be evaluated together.

## Migration-history limitations

- The Supabase `list_migrations` integration returned no application migration entries.
- No application-owned `supabase_migrations` schema or migration-history relation was found in the inspected non-system schemas.
- `auth.schema_migrations`, `realtime.schema_migrations`, and `storage.migrations` exist, but their rows track Supabase-managed subsystems, not this application's public-schema migration history.
- The repository's six migration scripts do not contain a complete creation baseline for all 44 production public tables and the existing view.

## Release blockers

1. Establish an authoritative production schema baseline and provenance. Obtain a trusted schema-only dump or equivalent catalog snapshot and identify which SQL changes were applied manually, through the Dashboard, or through migrations.
2. Resolve the duplicate `app_releases` migration pair. Preserve the production-matching definition and clearly mark the other as superseded or remove it only after confirming repository history and consumers.
3. Reconcile the effects of migrations `202611160001` and `202611170001` against live default ACLs, function ACLs, triggers, and service-role dependencies before any production execution.
4. Validate candidate migrations `202611250001`–`202611250005` against the verified baseline, including ownership transfer, function caller grants, RLS behavior, and the public leaderboard data-exposure decision.
5. Produce a reviewed forward plan and rollback/restore plan. Do not treat reverse SQL alone as a safe rollback for data-changing operations.

## Explicit non-actions

- No production migration was applied.
- No production data, RLS policy, grant, function, or schema was modified.
- PR #41 remains Draft and unmerged.
- GitHub Pages was not deployed.
- No paid service was enabled or purchased.
