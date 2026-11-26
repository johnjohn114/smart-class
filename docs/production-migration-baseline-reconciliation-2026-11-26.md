# Production migration baseline reconciliation — 2026-11-26

## Scope and safety

This is a read-only comparison of the connected Supabase production catalog with the repository's `main` migration directory and the candidate PR branch. No production SQL was executed that changes data, schema, grants, policies, or functions. No deployment or merge was performed.

Project ref: `fsoowongtavlsrwvzbze`  
Repository: `johnjohn114/smart-class`  
PR: #41  
Candidate head after 2026-11-26 ACL follow-up: `9b04f34fe4ef349bf3a0a3a17c087c24926b3643`

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


## 2026-11-26 follow-up: service-role RPC scope and CI

The combined candidate removes direct `service_role` EXECUTE from the application-facing SECURITY DEFINER RPC classes in migration `202611250004_security_definer_execution_scope_guard.sql`:

- Admin and member RPCs: EXECUTE remains granted to `authenticated`; direct `service_role` EXECUTE is revoked.
- Trigger-only routines: EXECUTE is revoked from PUBLIC, anon, authenticated, and service_role; trigger dispatch is covered by the isolated SQL regression test.
- Internal growth routines: direct EXECUTE is granted to `postgres` for existing postgres-owned SECURITY DEFINER callers, and revoked from service_role.
- Admin helper functions: authenticated access remains; direct service_role EXECUTE is revoked.
- Public download counter: anon/authenticated access remains; direct service_role EXECUTE is revoked.

A source scan of the browser clients and reviewed Edge Functions found that browser RPC requests use the signed-in user's JWT; the reviewed Edge Functions perform privileged Auth/table operations and do not directly call this RPC set. This is evidence for the reviewed call sites, not a substitute for rechecking every deployed function and external integration before production release.

The isolated ACL regression test now asserts the service_role denial for these classes. On candidate head `9b04f34fe4ef349bf3a0a3a17c087c24926b3643`, all five GitHub checks completed successfully: PostgreSQL RPC/RLS, GoTrue/PostgREST JWT integration, Deno, notification contract, and isolated browser preview.

This does not resolve the production migration-baseline blocker. PR #41 remains Draft and unmerged; no production migration or deployment was performed.


## 2026-11-26 product decision: public individual leaderboard

The project owner confirmed retaining the current individual public leaderboard design rather than replacing it with aggregate-only statistics. The intended public projection remains limited to:

- member nickname;
- attended count;
- late count;
- no-show count;
- activity points.

It continues to omit account IDs and internal check-in/completion point subtotals.

This is a product-design decision for the candidate only. It is not evidence that every member whose statistics may appear has been informed or has authorized publication. Before production release, the operator must provide a clear notice describing the public fields and obtain any required member/guardian/school authorization or opt-in, as applicable. If that cannot be established, do not enable the public view. No production schema or data has been changed.


## 2026-11-27 read-only reconciliation: public object inventory and exact-head CI

- Re-ran the public-schema inventory using both PostgreSQL catalogs and the Supabase table-list interface.
- PostgreSQL reports **44 ordinary tables and 1 view** in `public`.
- The Supabase table-list interface returned the same 44 table names; a name-by-name comparison found no missing or extra table. The earlier apparent 42-versus-44 discrepancy is therefore resolved as a stale/partial prior count, not a current inventory mismatch.
- All 44 returned public tables report RLS enabled. This confirms the RLS-enabled flag only; it does not prove that policies are correct or that every table has safe grants.
- The one public view is `activity_member_stats`. The candidate-only `activity_public_leaderboard` is not part of production inventory.
- Candidate head `4b5d85978de4122e8e564d7e3b96f633f7270a49`: both workflows completed successfully. Maintenance Edge Function Checks Run `45854369279` passed all 3 jobs (isolated PostgreSQL RPC/RLS and migration tests, Deno checks, GoTrue/PostgREST integration). Notification Page Checks Run `45854368962` passed both jobs (notification contracts and isolated browser preview). Total: **5/5 jobs passed on this exact commit**.
- The candidate remains Draft and unmerged. These isolated CI results and read-only catalog checks do not authorize production migration or deployment. Application migration provenance/baseline remains unresolved.


## 2026-11-27 read-only policy and helper-table follow-up

- The live public schema currently has 98 RLS policies across 42 of the 44 public tables. The two RLS-enabled tables with no policy rows are `member_no_counter` and `visitor_profiles`. RLS being enabled with no policies means ordinary Data API roles do not gain row access through a policy; it does not by itself establish that the tables are unused or safe to change.
- Current grants show `member_no_counter` is granted to `service_role` with broad table privileges, while `visitor_profiles` has broad grants to `anon`, `authenticated`, and `service_role`. Because `visitor_profiles` has RLS enabled and no policies, those grants alone do not make rows visible through RLS-protected access.
- The `member_no_counter` table has columns `id boolean`, `next_no integer`, `compacted boolean`, and `repair_version integer`. Its live database dependency is the SECURITY DEFINER trigger function `assign_member_no_and_nickname()`, attached as a BEFORE INSERT trigger on `public.profiles`; that function increments the counter when creating a visitor profile. The trigger function uses an empty search_path and schema-qualified table references.
- A read-only scan of public function definitions found no function reference to `visitor_profiles`; no trigger is attached to either helper table. This is not a complete proof that no frontend, Edge Function, or external integration accesses `visitor_profiles`.
- No grants, policies, tables, functions, or triggers were changed. Before narrowing `member_no_counter` grants or removing/retiring `visitor_profiles`, inspect all browser/Edge Function/external call sites and confirm the visitor-account creation flow end-to-end.

## Explicit non-actions

- No production migration was applied.
- No production data, RLS policy, grant, function, or schema was modified.
- PR #41 remains Draft and unmerged.
- GitHub Pages was not deployed.
- No paid service was enabled or purchased.

## 2026-11-27 visitor_profiles dependency follow-up

Read-only catalog checks of `public.visitor_profiles` confirmed:

- RLS is enabled, `FORCE ROW LEVEL SECURITY` is not enabled, and the table has **zero policies**.
- The table owner is `postgres`; current table ACL grants broad table privileges to `anon`, `authenticated`, and `service_role`. With no applicable RLS policy, the ordinary API roles do not receive row access through RLS; `service_role` is a privileged bypass role and must be considered separately.
- Columns are `id uuid`, `username text`, `active boolean`, and `created_at timestamptz`.
- The only catalog dependency found is its foreign key `id REFERENCES auth.users(id) ON DELETE CASCADE`. No view/materialized-view dependency, inbound foreign key, database function body reference, or trigger on this table was found in the inspected catalogs.
- Candidate-branch browser files `app.js` and `admin.js`, and the reviewed visitor-related Edge Functions, did not contain a direct `visitor_profiles` reference. GitHub code search on the repository's default branch also returned no matching source file. These searches are limited evidence; they do not rule out older branches, external integrations, manually issued SQL, or clients not represented in the inspected repository.

**Disposition:** do not delete the table or change grants/policies yet. First verify the deployed visitor-account lifecycle and check any external consumers. The table may be legacy, but the evidence is not sufficient to classify it as safely removable. No production object or data was changed.
