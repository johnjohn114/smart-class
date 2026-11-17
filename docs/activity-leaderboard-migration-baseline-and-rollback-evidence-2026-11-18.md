# Activity leaderboard migration baseline and rollback evidence

**Date:** 2026-11-18  
**Scope:** `public.activity_member_stats` and the proposed `public.activity_public_leaderboard` rollout  
**Environment:** Supabase project `fsoowongtavlsrwvzbze`, PostgreSQL 17.11  
**Status:** Read-only evidence and candidate rollback guidance only. No production write was performed.

## 1. Migration-history reconciliation

The earlier check established that the project does not expose the expected `supabase_migrations.schema_migrations` ledger used by the repository's assumed workflow, and the Supabase migration-list API returned an empty list.

A wider catalog search on 2026-11-18 found:

- `auth.schema_migrations` — a one-column `version varchar NOT NULL` table with many versions through `20261030120000`. This is in the Supabase Auth/GoTrue schema and is not evidence that this application's `supabase/migrations/*.sql` files were applied.
- `realtime.schema_migrations` — Realtime service migration metadata, unrelated to the application's migration history.
- `storage.migrations` — Storage service migration metadata, unrelated to the application's migration history.
- No `supabase_migrations.schema_migrations` relation was found by the catalog search.

**Decision:** Application migration history remains unreconciled. Do not mark repository SQL files as applied based on the Auth, Realtime, or Storage ledgers. Do not run a candidate migration until its application-level deployment history is established or a deliberate baseline/adoption procedure is reviewed.

## 2. Captured production view baseline

Read-only catalog query returned:

- Relation: `public.activity_member_stats` (ordinary view)
- Owner: `postgres`
- View options: `NULL` (no explicit `security_invoker=true`; current behavior is the default security-definer view behavior)
- Existing view definition:

```sql
SELECT
  a.user_id,
  max(COALESCE(p.nickname, a.user_id::text)) AS nickname,
  count(*) FILTER (
    WHERE a.status = ANY (ARRAY['checked_in'::text, 'late'::text])
  )::integer AS attended_count,
  count(*) FILTER (WHERE a.status = 'late'::text)::integer AS late_count,
  count(*) FILTER (WHERE a.status = 'no_show'::text)::integer AS no_show_count,
  COALESCE(sum(a.points_awarded), 0::bigint)::integer AS checkin_points,
  COALESCE(sum(a.completion_points_awarded), 0::bigint)::integer AS completion_points,
  (
    COALESCE(sum(a.points_awarded), 0::bigint)
    + COALESCE(sum(a.completion_points_awarded), 0::bigint)
  )::integer AS activity_points
FROM competition_attendance a
LEFT JOIN profiles p ON p.id = a.user_id
GROUP BY a.user_id;
```

The view currently exposes eight columns: `user_id`, `nickname`, `attended_count`, `late_count`, `no_show_count`, `checkin_points`, `completion_points`, and `activity_points`.

### Current explicit role grants

The read-only `information_schema.role_table_grants` snapshot showed the following explicit privileges:

| Role | Current privileges |
|---|---|
| `anon` | SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER |
| `authenticated` | SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER |
| `service_role` | SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER |
| `postgres` | Same privileges, with grant option |

The candidate hardening migration should remove these broad API-role privileges and grant only the intended SELECT permissions.

### Source-table policies and dependencies

The view reads from `public.competition_attendance` and `public.profiles`. Catalog dependency inspection found those two source relations; it did not identify another dependent view in that dependency query.

Current policies relevant to those source tables:

- `competition_attendance.attendance_admin_all`: authenticated admin access, using and check based on a matching `profiles.role = 'admin'`.
- `competition_attendance.attendance_member_select`: authenticated members can select rows where `user_id = auth.uid()`.
- `profiles.profile_admin_all`: authenticated admin access via `is_admin()`.
- `profiles.profile_self_read`: authenticated users can read their own profile or an admin-readable profile.
- `profiles.profile_self_update`: authenticated users can update their own profile only while the row role is `visitor`.

Do not alter these source-table policies as part of the view rollout. The security-invoker change makes their behavior directly relevant to the view caller and therefore must be tested with real role contexts in a disposable database.

## 3. Safe staged rollout

1. **Stage A — Projection:** Create `activity_public_leaderboard` first. Verify anonymous SELECT returns only the five UI fields: `nickname`, `attended_count`, `late_count`, `no_show_count`, `activity_points`. Confirm no account UUID or internal point subtotals are exposed.
2. **Stage B — Frontend:** Release the reader for the new projection. The current frontend fallback retries the legacy view only on HTTP 404 and selects only the five presentation fields. A fallback to the old view does not itself fix the old view's exposure.
3. **Stage C — Legacy view hardening:** Only after Stage B has been verified, set `security_invoker=true`, revoke broad privileges from API roles, and retain SELECT only for `authenticated` and `service_role`. Verify member, admin, and service-role behavior plus anonymous denial.

The synthetic PostgreSQL 17 integration test in CI passed, but it is not a production clone or production smoke test. Keep production execution blocked until the application migration baseline and a sanitized production-like rehearsal are complete.

## 4. Emergency compatibility rollback SQL (candidate only)

The original view definition was not changed by the proposed hardening; the proposed Stage C change only changes its view option and grants. If Stage C has been applied and an emergency compatibility rollback is explicitly approved, the minimum rollback needed to restore the old anonymous reader is:

```sql
BEGIN;

-- Restore the original default view option (captured baseline had reloptions NULL).
ALTER VIEW public.activity_member_stats
  RESET (security_invoker);

-- Keep least privilege: do not restore the old DML/TRUNCATE/REFERENCES/TRIGGER grants.
REVOKE ALL PRIVILEGES ON TABLE public.activity_member_stats
  FROM PUBLIC, anon, authenticated, service_role;

-- Temporary compatibility exception for the legacy public leaderboard.
-- authenticated and service_role retain SELECT for their existing readers.
GRANT SELECT ON TABLE public.activity_member_stats
  TO anon, authenticated, service_role;

COMMIT;
```

**Critical privacy warning:** this compatibility rollback makes the original eight-column view anonymously readable again. It can expose account UUIDs (`user_id`) and internal point subtotals (`checkin_points`, `completion_points`). This is an emergency-only exception, not an acceptable steady state. Prefer rolling forward the new projection/frontend path and keeping anonymous access to the legacy view revoked.

This rollback SQL is documentation for review only. It has not been executed. Before any production use, verify that the live view definition/options/grants still match the captured baseline and that the migration being rolled back is exactly the expected Stage C change.

## 5. Explicit no-write record

During this review:

- No production SQL DDL or DML was executed.
- No grants, RLS policies, view definitions, or source data were changed.
- No Supabase migration was applied.
- No Supabase paid branch or paid compute was created.
- GitHub Pages deployment remains separate from the Supabase database rollout.

## 6. Remaining release gates

- [ ] Establish an authoritative application migration history or approve a controlled baseline/adoption procedure.
- [ ] Review the migration file inventory against live schema state, not filenames alone.
- [ ] Rehearse Stage A/B/C and the emergency rollback on a sanitized production-like clone.
- [ ] Verify the new public projection's privacy decision and aggregate outputs.
- [ ] Run production smoke checks with member, admin, anonymous, and service-role contexts without logging member data.
- [ ] Record the release operator, approved window, exact migration hash, and rollback decision.

Until these gates are met, production database execution remains **not approved**.
