# Maintenance Compatibility / Permission Dependency Audit v0.1

> Date: 2026-11-17  
> Branch: `feature/maintenance-system`  
> Scope: read-only Supabase catalog review + feature-branch SQL / Edge / test inspection.  
> Safety: no production DDL/DML, migration, repair, deploy, merge, secret access, or paid resource.

## 1. Baseline and evidence

- Branch HEAD at audit start: `2ac1e94bd7ce651bd0f86e1d18f53b0d03cdd5c7`.
- Latest successful code CI: run `43912032237`, tested commit `7c1750d19c91af548dd0b8d8cd2e6ae5e688eae5`. HEAD is a documentation-only descendant; no application SQL/Edge code changed after that tested commit.
- CI jobs: Deno checks/tests passed; GoTrue-issued JWT/PostgREST integration passed; disposable PostgreSQL 17 RPC/RLS, growth authorization and trigger/default-privilege tests passed.
- Production remains on the pre-maintenance schema: the earlier read-only audit found no `private` schema, no five maintenance RPCs, no six maintenance tables, and no deployed maintenance Edge Functions.
- The uploaded `啟動第一步檢查.txt` is a prior review summary for an older four-table/public-schema design, not the raw SQL migration. The current architecture baseline explicitly selects the six-table private-schema model; the old four-table SQL is not to be mixed into it.

## 2. Production default-privilege inventory (read-only)

### 2.1 Defaults owned by postgres

Current `pg_default_acl` entries show:

| Schema | Object type | Existing default grantees |
|---|---|---|
| public | tables | anon, authenticated, service_role receive ALL |
| public | sequences | anon, authenticated, service_role receive ALL |
| public | functions | anon, authenticated, service_role receive EXECUTE |
| storage | tables | anon, authenticated, service_role receive ALL |
| storage | sequences | anon, authenticated, service_role receive ALL |
| storage | functions | anon, authenticated, service_role receive EXECUTE |

### 2.2 Defaults owned by supabase_admin

Supabase-managed default ACL entries also exist for schemas including `extensions`, `graphql`, `graphql_public`, `public`, and `realtime`. These are deliberately outside the candidate migration's scope and must not be modified casually.

### 2.3 Candidate migration impact

`202611170001_default_privileges_and_trigger_hardening.sql`:
- Revokes postgres-owned future table/sequence defaults for API roles in `public` only.
- Revokes postgres-owned future function EXECUTE from PUBLIC globally, then revokes postgres-owned schema-specific API-role function defaults in `public`.
- Does not change `supabase_admin` defaults.
- Does not remove the existing schema-specific API-role defaults in `storage`. The global PUBLIC revoke does not cancel those explicit storage grants; new postgres-owned functions in storage can still inherit the storage-specific API-role grants.

**Required wording correction before production use:** the migration comment currently implies all callers in every schema will need explicit per-function grants. That is only true where no schema-specific default ACL independently grants them. The global PUBLIC revoke has cross-schema impact; the existing storage-specific grants remain. A production rollout must inventory any postgres-owned functions created outside public and test the intended caller behavior.

## 3. Production SECURITY DEFINER inventory and permission dependencies

Read-only catalog results:
- 36 public SECURITY DEFINER functions total: 31 ordinary functions and 5 trigger functions.
- All are owned by postgres.
- Before candidate hardening, effective EXECUTE was available to anon on 34/36 and authenticated on 34/36 (including inherited PUBLIC access).
- Existing public RLS policies call `public.is_admin()`; several public-facing policies are scoped to PUBLIC. The current live ACL does not give anon EXECUTE on `is_admin()`. The candidate migration intentionally restores anon EXECUTE for this helper; its body returns whether `auth.uid()` is an admin and is safe for anonymous evaluation.
- The `videos_admin_read` policy calls `public.is_admin_user()` for authenticated users. The candidate's authenticated grant preserves this dependency.

### 3.1 Candidate grant behavior

The growth hardening migration iterates all public SECURITY DEFINER functions:
- Trigger functions: revoke PUBLIC, anon, authenticated and service_role direct EXECUTE; existing trigger bindings continue to run.
- Non-trigger functions: revoke PUBLIC and anon; grant authenticated, except `award_growth_points` and `_refresh_growth_level_internal`, from which authenticated EXECUTE is revoked.
- `is_admin()` receives anon EXECUTE for existing PUBLIC RLS policy evaluation.
- service_role grants on most non-trigger routines are not removed.

The live function-body scan found the expected ownership checks for admin routines and user-scoped checks for member routines. Candidate replacements harden the null-identity check in reward administration, add cross-account checks to achievement/level functions, and keep the points writer/internal level helper unavailable for direct authenticated calls.

### 3.2 Compatibility and test coverage gaps

- `increment_download_count(uuid)` has no in-function user identity check; it only increments the counter for a published file. The frontend currently invokes it only after visitor login, and the candidate migration changes it to authenticated-only. This matches the observed frontend path, but it remains an intentionally broad authenticated operation and has no rate limit.
- The SQL regression test uses fixture functions and a reduced schema. It proves selected ACL and behavior contracts, not all 31 ordinary SECURITY DEFINER routines against the complete live schema.
- The candidate migration's blanket authenticated grant therefore still requires a complete function-by-function guard/behavior matrix and targeted integration tests before production approval.
- The test suite verifies anon's `is_admin()` call and selected member/admin paths, but does not execute every existing public RLS policy under anon/authenticated JWT contexts.

## 4. SECURITY DEFINER search_path and temporary-schema dependency

Read-only checks show:
- anon, authenticated and service_role currently have database TEMP privilege.
- These API roles do not have CREATE on `public` or `extensions`.
- The public SECURITY DEFINER routines generally use `search_path=public`; relation-reference scanning found no unqualified FROM/JOIN/UPDATE/INSERT/DELETE relation references in their bodies.
- A separate rowtype scan found two unqualified `%ROWTYPE` declarations:
  - Live `public.complete_growth_task(text)`: `t growth_tasks%ROWTYPE`.
  - Live `public.refresh_growth_level(uuid)`: `lvl growth_levels%ROWTYPE`; the candidate migration replaces this function, but its new internal helper `_refresh_growth_level_internal(uuid)` still declares `lvl growth_levels%ROWTYPE`.

Because API roles have TEMP privilege, temporary relation/type names are a compatibility consideration when a SECURITY DEFINER routine resolves an unqualified rowtype under `search_path=public`. The relation reads themselves are schema-qualified, so this audit does not claim a demonstrated data-exfiltration or privilege-escalation exploit. Nevertheless, both rowtype declarations should be schema-qualified (for example, `public.growth_tasks%ROWTYPE` and `public.growth_levels%ROWTYPE`) or the affected routines should use a reviewed safe search_path. The candidate growth migration currently leaves this hardening incomplete.

## 5. Maintenance six-table SQL / Edge compatibility

Target model per `maintenance-architecture-baseline-decision-v0.1.md`:
1. `private.maintenance_scopes`
2. `private.maintenance_events`
3. `private.maintenance_event_private_notes`
4. `private.maintenance_event_scopes`
5. `private.maintenance_audit_logs`
6. `private.maintenance_idempotency`

Static review confirms:
- Five Edge entrypoints map one-to-one to five public JSONB RPCs using `p_request`.
- Edge field validation limits (title 200, message/internal note 4000, reason 500) match the SQL checks.
- `ends_at` is the new six-table model's canonical field; the older four-table `expected_end_at` field is not part of this target model.
- Create/update/action writes use the narrow column grants present in the SQL draft; actor IDs default from `auth.uid()`, not request payloads.
- Public status uses SECURITY INVOKER and whitelisted public columns. Internal notes are isolated in their own admin-only table.
- RLS and object grants appear aligned for the six-table draft, and disposable GoTrue/PostgREST + PostgreSQL tests passed.

Still unverified in production:
- The private schema and maintenance objects do not exist yet.
- Supabase Data API Exposed schemas were not confirmed; `private` must remain excluded.
- No production RLS/grants/runtime smoke test is possible until a separately approved deployment window.
- Idempotency/audit retention policy remains unresolved.
- The older four-table SQL and its service_role-only model are incompatible with the current user-JWT/SECURITY INVOKER architecture and must remain unused.

## 6. Migration baseline and compatibility gate

- Production migration history was previously found empty/unreconciled.
- The repository contains two conflicting `app_releases` migration variants plus legacy schema-upgrade SQL. Do not mark migrations applied, replay them, or run `db push` until a read-only schema diff and migration baseline decision are complete.
- The dependency checker `scripts/verify_schema_dependencies.py` is a conservative snapshot checker. It does not build a full PostgreSQL dependency graph, inspect dynamic SQL, verify column-level ACLs, compare all live grants, or cover the six-table private RPC draft and candidate migrations.
- The successful CI run is an isolated test result, not a production schema restore or migration-history reconciliation. Full restore testing remains skipped per project decision.

## 7. Required follow-up before production approval

1. Schema-qualify the two rowtype declarations noted in §4, and add a disposable test using same-named temporary tables to verify the protected routines resolve the intended public row types.
2. Extend growth authorization regression coverage to the full live function inventory and to the RLS policies that depend on `is_admin()` / `is_admin_user()`.
3. Add explicit default-ACL compatibility assertions for postgres-owned functions in public and storage; clarify the global PUBLIC revoke comment and verify no Supabase-managed schema dependency is unintentionally changed.
4. Confirm whether authenticated-only `increment_download_count` is the intended product behavior and whether rate limiting is needed.
5. Complete read-only production schema/migration baseline reconciliation; verify Data API Exposed schemas exclude private.
6. Only after these gates pass, prepare a separately reviewed migration plan. No production execution is authorized by this audit.

## 8. Final status

**Feature-branch CI:** passed for the latest code commit tested.  
**Static compatibility review:** substantially completed; follow-up items remain.  
**Production migration readiness:** NOT APPROVED.  
**Production database changes / deployments / merges / paid resources:** none performed.
