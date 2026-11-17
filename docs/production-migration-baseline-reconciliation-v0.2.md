# Production Migration Baseline Reconciliation v0.2

> Snapshot: 2026-11-17 (Asia/Taipei)  
> Repository base: `main` at `812e95958d5edd31f7335511e470666da53c7b7b`  
> Supabase project: `fsoowongtavlsrwvzbze`  
> Scope: read-only production catalog/migration inventory reconciliation after maintenance-system integration PR #12.  
> Safety: this document records metadata/catalog reads only. No production DDL/DML, migration repair, Edge Function deployment, secret changes, or paid resources were performed.

## 1. Executive result

**Production migration baseline remains NOT READY for execution.**

The current Supabase project is `ACTIVE_HEALTHY` on PostgreSQL 17.11. Supabase's migration listing is empty, and the `supabase_migrations` schema is absent. This does not mean the database is empty: existing public objects match two repository migration outcomes.

The repository currently contains **five** files under `supabase/migrations/` (not six). The two App Releases SQL files are incompatible alternatives; they must not both be treated as sequential migrations.

The maintenance SQL remains a development draft at `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`; it is not in the migration folder and must not be run against production yet.

## 2. Current production evidence (read-only)

| Check | Current observation |
|---|---|
| Project status | `ACTIVE_HEALTHY` |
| PostgreSQL | 17.11 |
| Supabase migration listing | Empty |
| `supabase_migrations` schema | Absent |
| `private` schema | Absent |
| Maintenance tables / objects | None found in `public` or `private` |
| Maintenance RPCs | None found |
| Maintenance Edge Functions | None of the five are deployed |
| Existing App Releases table | Present; columns match variant A |
| Announcement calendar columns | All four expected columns present |

The live `public.app_releases` columns are: `id`, `version_code`, `version_name`, `release_notes`, `apk_url`, `published`, `created_at`, `published_at`, `created_by`. There is no `is_latest` column. This is consistent with variant A's table shape.

The four live announcement calendar columns are `event_date`, `event_end_date`, `event_date_source`, and `event_date_confirmed`. The earlier read-only catalog review also found the two expected CHECK constraints and the partial calendar index matching the calendar migration.

## 3. Exact repository migration inventory

The current `main` branch contains these five SQL files:

| File | Classification from current evidence | Handling |
|---|---|---|
| `202610310001_app_releases.sql` | Already reflected in live table shape (variant A) | Do not replay blindly; preserve as the historical candidate for baseline reconciliation |
| `20261031_app_releases.sql` | Conflicting alternative (variant B); adds `is_latest` and a different helper/policy model | Do not apply as a second App Releases migration |
| `26.11.3_calendar_fields.sql` | Already reflected in live columns, constraints and index | Do not replay blindly |
| `202611160001_growth_function_authorization_hardening.sql` | Candidate hardening migration; not applied | Requires full function-by-function authorization and regression review |
| `202611170001_default_privileges_and_trigger_hardening.sql` | Candidate default-ACL / trigger hardening; not applied | Requires explicit review of global PUBLIC function-default change and owner context |

Schema similarity is evidence of current post-state only. It is not evidence of the original execution time, operator, or migration ledger entry. Do not use `migration repair`, `db push`, or manual history insertion solely to make the empty ledger appear complete.

## 4. Maintenance system status after PR #12

PR #12 is merged into `main` at `812e95958d5edd31f7335511e470666da53c7b7b`. The website integration and GitHub Pages deployment succeeded.

The maintenance UI remains gated off by `MAINTENANCE_FEATURE_ENABLED = false`.

The current target design is the six-table private-schema model:
1. `private.maintenance_scopes`
2. `private.maintenance_events`
3. `private.maintenance_event_private_notes`
4. `private.maintenance_event_scopes`
5. `private.maintenance_audit_logs`
6. `private.maintenance_idempotency`

It uses five public `SECURITY INVOKER` RPCs, user JWT forwarding from Edge Functions, explicit minimum grants and RLS. The old four-table SQL is historical and incompatible; it must not be mixed into this design.

The draft is still located under `supabase/sql/`, not `supabase/migrations/`. Production currently has no maintenance schema, tables, RPCs, or deployed maintenance Edge Functions.

## 5. Existing security baseline — separate workstream

The latest Security Advisor snapshot reports:
- 34 SECURITY DEFINER function findings callable by `anon`;
- one SECURITY DEFINER view finding (`public.activity_member_stats`);
- two RLS-enabled tables without policies (`member_no_counter`, `visitor_profiles`);
- leaked-password protection disabled.

These findings predate the maintenance deployment and are not evidence that the new maintenance feature caused them. Do not batch-revoke existing function privileges or change existing view/table policies as part of this baseline task. Each existing function requires call-site, identity, dependency, and regression review.

## 6. Remaining blockers before any production migration

1. Produce a reproducible baseline manifest for all existing application objects, including tables, columns, constraints, indexes, functions, triggers, RLS policies, grants, and extensions.
2. Decide how to represent the already-existing App Releases and calendar schema in a clean migration history without replaying their DDL or inventing historical execution records.
3. Complete the function-by-function authorization matrix and isolated regression tests for the two candidate hardening migrations.
4. Verify in Supabase Dashboard that `private` is not in Data API Exposed schemas. The current database metadata tools do not prove this Dashboard setting.
5. Complete the maintenance SQL / Edge Function contract review, including rate limiting and audit/idempotency retention decisions.
6. Test the exact final migration sequence against a disposable PostgreSQL 17 / GoTrue / PostgREST environment, with a recovery plan.

## 7. Required execution boundary

Until all blockers are closed and a separate release plan is reviewed:

- Do not execute the maintenance SQL draft against production.
- Do not run `db push` or `migration repair`.
- Do not apply either App Releases variant again.
- Do not deploy the five maintenance Edge Functions.
- Keep `MAINTENANCE_FEATURE_ENABLED = false`.
- Do not create a paid Supabase project or branch.

## 8. Verification record

Read-only checks performed on 2026-11-17:
- project status and PostgreSQL version;
- Supabase migration listing;
- public/private schema table inventory;
- maintenance object and RPC catalog search;
- App Releases and announcement calendar column inventory;
- deployed Edge Function inventory;
- Security Advisor snapshot;
- GitHub `main` migration-folder inventory and SQL source review.

No production SQL writes, migration repair, Edge Function deployment, or new paid resources were performed.

**Final status: baseline reconciliation is improved, but production migration execution remains blocked.**
