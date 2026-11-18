# Maintenance Code Consistency Audit v1.0

> Date: 2026-11-18 (Asia/Taipei)
> Branch reviewed: `feature/v26.11.7-maintenance-next`
> Scope: static comparison of the current branch's migration, SQL draft, Edge Function entrypoints/shared handler, API contract, and isolated test sources.
> Change scope: this report only. No application code, SQL, tests, production database, deployment, merge, or paid resources were changed or run during this audit.

## 1. Executive result

**The core five-Edge-Function / five-RPC naming and seven-scope identifiers align. The architecture is directionally consistent with the v1.0 decision, but the repository is not yet release-ready.**

The most important finding is operational: a full maintenance SQL file exists under `supabase/migrations/`. Supabase CLI treats SQL files in that directory as migration candidates. It is not merely a harmless draft file. Do not run `supabase db push` or any migration command against production until the migration-baseline and release gates are separately resolved and approved.

## 2. Items confirmed aligned

| Area | Result | Evidence |
|---|---|---|
| Edge Function entrypoints | Aligned | Five entrypoints map status/list/create/update/action to the expected RPC names |
| RPC names | Aligned | `maintenance_status_public`, `maintenance_admin_list`, `maintenance_event_create`, `maintenance_event_update`, `maintenance_event_action` |
| Scope identifiers | Aligned | Seven codes match across SQL, Edge shared validator, and API contract |
| Authentication mode | Aligned | status is optional-token; four management endpoints require a token |
| SQL authorization | Aligned | All five RPCs are SECURITY INVOKER; management RPCs check `auth.uid()` and `public.is_admin()` |
| Search path | Aligned | RPCs use an empty fixed search_path and schema-qualified references |
| RPC transport | Aligned | Edge handler sends `{ p_request: payload }` to the corresponding PostgREST RPC |
| Private notes | Aligned | `internal_note` is stored in the separate private notes table; public status response does not include it |
| Private schema test boundary | Partially verified in CI | PostgREST test config uses only the `public` schema and asserts direct `/maintenance_events` access returns 404; this is not evidence of the production Dashboard setting |

## 3. Findings requiring action

### P0 — Migration file is present in the active migrations directory

Current branch contains:

`supabase/migrations/20261117121103_maintenance_system_initial.sql`

It contains the full six-table schema and five RPC definitions. The SQL integration harness includes this exact file using `\\ir ../../migrations/20261117121103_maintenance_system_initial.sql`.

The separate file `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql` is labelled “DEVELOPMENT DRAFT ONLY. DO NOT RUN AGAINST PRODUCTION” and says it is intentionally outside the migrations directory. The two SQL files are almost identical; the observed differences are their headers, the preflight error wording, and the maintenance_events table comment.

**Risk:** documentation that says the SQL exists only as a draft under `supabase/sql/` is stale for this branch. More importantly, the migration-directory file is eligible to be applied by a future CLI migration operation. A warning in a review document does not prevent that.

**Required decision:** before any production migration workflow, explicitly decide whether this file remains a migration candidate or is moved back to a non-migration draft location pending baseline approval. Do not execute it as part of this audit.

### P1 — API specification metadata and implementation state are stale

`docs/maintenance-api-spec-v0.6.md` still says:
- branch is `main` and the migration remains in PR #16;
- Edge Function source is on `feature/maintenance-system`;
- the six tables/RPCs exist only as an unverified draft and have not been created.

Those statements do not describe the current repository branch, which contains the five Edge Function sources and a full SQL file in `supabase/migrations/`. They may still describe production deployment state, but the document does not distinguish repository state from production state.

**Required action:** update the document header and implementation-state paragraph to distinguish (a) current branch source, (b) migration file present in the repository, and (c) production state, which the reviewed evidence says remains un-deployed. Keep the production non-approval statement.

### P1 — HTTP 429 is specified but no rate limiter is implemented

The API contract lists HTTP 429 `RATE_LIMITED`. The reviewed shared Edge Function handler contains CORS, token validation, input parsing, RPC forwarding, and RPC error mapping, but no application-level rate limiter. The contract review document itself records this as unresolved.

**Required decision:** either implement and test a durable rate limiter, or remove/qualify the 429 promise and document what platform-level controls actually exist. Do not claim rate limiting is active.

### P1 — SECURITY INVOKER design is not strict RPC-only at the PostgreSQL grant layer

The migration grants authenticated column-scoped INSERT/UPDATE/DELETE privileges on several private tables, including events, private notes, event scopes, audit logs, and idempotency. RLS policies restrict these operations to admins, and the design requires `private` to remain outside Data API Exposed schemas.

This matches the architecture decision's documented limitation, but it means the phrase “all writes should use RPCs” in the events table COMMENT is an application convention, not a database-enforced guarantee. Audit INSERT is also available to an authenticated admin under the current grants/RLS design.

**Required action:** retain the explicit limitation in release documentation and verify actual role behavior. If strict RPC-only writes are a product requirement, design that separately; do not silently switch functions to SECURITY DEFINER.

### P1 — Production Data API exposure remains unverified

The test suite proves only that the isolated PostgREST test instance uses `PGRST_DB_SCHEMAS=public` and returns 404 for a private table endpoint. It does not prove the real Supabase project's Dashboard Data API Exposed schemas setting.

**Required action:** before release, manually confirm that `private` is not in the production Exposed schemas list and record the evidence.

### P2 — Historical review documents refer to earlier branches/commits

The prelaunch and contract review documents contain historical branch names, source commits, and CI run identifiers. Those are useful as historical evidence but must not be represented as tests of the current branch HEAD unless the SHA matches exactly.

**Required action:** every release review should record the exact current branch commit SHA and the CI run whose tested SHA matches it.

## 4. Test evidence and limitations

Static source inspection confirms that:
- the PostgreSQL-only harness applies the migration file in an ephemeral test database;
- the PostgREST JWT/RLS test asserts anonymous status access, non-admin denial for admin list, admin list success, expired-token denial, private-table endpoint 404, and concurrent overlapping schedule serialization;
- the API and review documents identify unresolved rate limiting, retention, production exposed-schema confirmation, and production Edge Function runtime/CORS checks.

This audit did not execute CI, run local tests, call production Supabase, or verify production Dashboard settings. Historical CI success cited in existing documents is not proof that the current branch HEAD was tested.

## 5. Release blockers retained

1. Migration history/baseline reconciliation and a safe non-replaying migration plan.
2. Decision on the active migration-directory file.
3. Production Data API Exposed schemas confirmation (`private` excluded).
4. Production Edge Function secrets, CORS environment, Gateway settings, deployment, and smoke tests.
5. Rate-limit decision/implementation.
6. Audit and idempotency retention/cleanup decisions.
7. Actual anon, ordinary authenticated, and admin JWT/PostgREST permission verification.
8. Existing project-wide Security Advisor findings remain a separate workstream.

## 6. Safety boundary

No production database changes, migration repair/replay, Edge Function deployment, feature enablement, merge to `main`, or paid resource creation is authorized by this audit.

**Conclusion: source naming and core architecture align; documentation drift and migration placement must be resolved before release review.**
