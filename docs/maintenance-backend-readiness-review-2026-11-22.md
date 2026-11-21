# Maintenance backend readiness review — 2026-11-22

## Scope and safety

This is a review note only. It does not change application behavior, add a migration, deploy an Edge Function, or execute SQL against Supabase production.

Reviewed against `integration/maintenance-pagination-hardening-main-20261121`:
- Draft PR #31 and its current head commit `5cd64d061768147cf0e57b4bf93f7902b3166b1b`
- `supabase/functions/_shared/maintenance.ts`
- The five Maintenance Edge Function entry points
- The ordered Maintenance migrations and the separate private-schema/RPC development draft

## Current implementation found

### Request and identity path

- `maintenance-status` is GET with optional authentication.
- `maintenance-admin-list` is GET and requires authentication.
- `maintenance-event-create`, `maintenance-event-update`, and `maintenance-event-action` are POST and require authentication.
- The shared handler validates a required bearer token through Supabase Auth's `/auth/v1/user` endpoint. Invalid credentials fail with 401; an unavailable Auth service fails closed with 503.
- The admin RPCs independently require `auth.uid()` and `public.is_admin()`. The Edge Function's successful token validation is not treated as proof of administrator status.
- The shared request parser restricts methods, JSON size, UTF-8 decoding, accepted fields, UUIDs, timestamps, scope codes, and action names.

### Database protection and lifecycle

- The public status RPC is `SECURITY INVOKER`; the administrative RPCs are `SECURITY DEFINER` with an empty search path.
- The least-privilege upgrade creates `maintenance_rpc_executor` as NOLOGIN and NOBYPASSRLS, forces RLS on the six private tables, restricts mutation policies to that role, transfers the administrative RPC ownership to it, and removes PUBLIC/anon execution grants.
- The upgrade grants authenticated users SELECT but removes their direct table write privileges.
- Audit rows have UPDATE/DELETE rejection triggers and a TRUNCATE rejection trigger.
- Write RPCs use idempotency keys and event versions. The update/action RPCs lock the target event row and reject stale versions.
- Create, update, and schedule operations use a transaction-scoped advisory lock and check overlapping scheduled windows. A global event conflicts with all overlapping scopes; the `site_core` scope also conflicts broadly.
- Public maintenance state is derived from a scheduled event whose start/end window contains the database server time. The public status RPC does not depend on a separate mutable global on/off flag.

## Corrections to the earlier preliminary checklist

The earlier note described state consistency, schedule conflict handling, and administrator validation as still needing implementation. The current integration branch already contains mechanisms for all three:
1. State is derived from the event status and time window.
2. Overlapping schedules are checked under a shared advisory transaction lock.
3. Both the Edge Function path and the database RPC enforce identity/administrator checks.

These mechanisms still require end-to-end verification; source inspection alone does not prove production behavior.

## Remaining release gates

1. **Keep PR #31 as Draft until review is complete.** Its branch is ahead of main and is not production code yet.
2. **Run/confirm the complete isolated CI suite** on the exact head commit, including SQL migration tests, RPC privilege tests, Edge Function tests, and browser compatibility tests.
3. **Review the exact migration pair in order**:
   - `20261117121103_maintenance_system_initial.sql`
   - `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`
   Confirm that the first migration cannot be accidentally treated as the final secure state without the upgrade.
4. **Use a disposable database for integration tests** with anon, authenticated non-admin, authenticated admin, and missing/invalid JWT cases. Verify direct table writes are denied, admin RPC writes succeed only for admins, public status reveals no internal notes, and Auth outages fail closed.
5. **Verify the production preflight read-only** before any migration: `public.is_admin()`, existing schema/table/function/role names, exposed schemas, current grants, and migration history must match the migration assumptions.
6. **Deploy only after separate approval**, in a controlled order: migrations, Edge Functions, smoke tests with the feature flag still disabled, then a separately approved feature-flag enablement.
7. **Prepare rollback steps** for both database objects and Edge Functions before any production change.

## Explicitly not done

- No Supabase production SQL was run.
- No migration was applied.
- No Edge Function was deployed.
- No production feature flag was enabled.
- No PR was merged and no deployment was triggered.
