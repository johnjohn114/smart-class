# Maintenance SQL Isolated Validation Report v0.1

> Date: 2026-11-17 (Asia/Taipei)  
> Repository base: `824fc8570b4faf9a38daf0c60245bfbc185cf20c`  
> Supabase production project: `fsoowongtavlsrwvzbze`  
> SQL under test: `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`  
> Scope: isolated CI validation and production read-only re-check.  
> **This report does not authorize production migration execution.**

## 1. Result

The maintenance SQL draft passed the repository's disposable CI integration pipeline after PR #14 added further coverage.

- Workflow run: [44078089552](https://github.com/johnjohn114/smart-class/actions/runs/44078089552)
- Tested commit: `6f5c4852bce7e192a05641f34468218f080e477e`
- Overall conclusion: `success`
- Deno type check / Edge Function validation / static SQL guardrails: success
- Isolated PostgreSQL 17 RPC and RLS integration: success
- GoTrue-issued JWT and PostgREST integration: success

PR #14 merged the test additions into `main` at `824fc8570b4faf9a38daf0c60245bfbc185cf20c`.

## 2. Additional test cases in PR #14

The GoTrue/PostgREST integration test now additionally verifies:

1. An anonymous request for `membership_growth` sees an active event only for that scope.
2. A request for unrelated `video_content` does not see the `membership_growth` event.
3. Public status never includes the private internal note marker.
4. An overlapping `site_core` event conflicts with a different local scope (`video_content`).

The existing CI suite also covers real GoTrue-issued user JWTs, role separation, private schema exclusion from PostgREST exposed schemas in the disposable test, event create/update/action, idempotency replay and key reuse, version conflicts, schedule overlaps, and half-open adjacent intervals.

These tests establish behavior only for the tested disposable PostgreSQL / GoTrue / PostgREST configuration. They do not prove the production Data API Exposed schemas setting, production secrets/CORS, production deployment behavior, or a production migration baseline.

## 3. Production re-check (read-only)

After PR #14 merged, the connected Supabase project was checked again:

| Item | Observation |
|---|---|
| Project health | `ACTIVE_HEALTHY` (previously confirmed) |
| PostgreSQL | 17.11 (previously confirmed) |
| Migration history listing | Empty |
| `private` schema | Not present in the current table inventory |
| Maintenance tables / RPCs | Not deployed |
| Maintenance Edge Functions | None of the five maintenance functions deployed |
| Existing production tables | Existing application tables remain present and RLS-enabled |

No production DDL/DML, migration repair, Edge Function deployment, secret update, or Data API setting change was performed.

## 4. Security Advisor snapshot (existing project-wide findings)

The current Security Advisor snapshot reports:
- 34 SECURITY DEFINER functions executable by `anon`.
- 34 SECURITY DEFINER functions executable by `authenticated`.
- One SECURITY DEFINER view: `public.activity_member_stats`.
- Two RLS-enabled tables without policies: `public.member_no_counter` and `public.visitor_profiles`.
- Leaked-password protection disabled.

These are existing project-wide findings and are not attributed to the maintenance SQL. They require a separate function-by-function / view / RLS review. This maintenance phase did not modify their grants or policies.

## 5. Remaining blockers before a migration can be created and executed

1. The production migration history is empty while application schema objects already exist. A complete baseline manifest and a non-replaying baseline strategy are still required.
2. The two App Releases migration variants remain incompatible; only the live variant-A table shape is reflected in production. Neither file may be blindly replayed.
3. The maintenance SQL is still stored as a development draft under `supabase/sql/`, not as a production migration.
4. The SQL/API contract still has unresolved product decisions: 429 rate limiting behavior, audit retention, idempotency retention, final scope seed confirmation, and final text-length limits.
5. Supabase Dashboard Data API Exposed schemas must be checked to ensure `private` remains excluded. CI proves only the disposable PostgREST configuration.
6. Production Edge Function environment, CORS allowlist, JWT behavior, and smoke tests remain unverified.
7. The current execution environment does not have the Supabase CLI installed, and external network name resolution prevented obtaining it. Per the repository workflow, a migration file must be created with `supabase migration new`; do not invent a timestamped migration filename or treat this draft as a migration.

## 6. Execution boundary

Until the blockers above are closed:

- Keep `MAINTENANCE_FEATURE_ENABLED = false`.
- Do not run `db push`, `migration repair`, or `apply_migration` against production.
- Do not apply the SQL draft to production.
- Do not deploy the five maintenance Edge Functions.
- Do not create a paid Supabase project or development branch.

**Final status: isolated test coverage improved and passed; production migration remains NOT READY.**
