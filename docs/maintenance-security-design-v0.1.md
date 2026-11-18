# Maintenance Security Design v0.1

> Status: design review only; not an approved migration or deployment artifact.
> Branch: `feature/v26.11.7-maintenance-next`
> Scope: maintenance subsystem draft only.
> Production Supabase, migrations, Edge Function deployment, and `main` are out of scope.

## 1. Purpose

Record the permission-boundary findings and the decisions that must be settled before changing the maintenance SQL or Edge Functions. This document deliberately does not convert the existing RPCs to `SECURITY DEFINER` by assumption.

## 2. Source facts checked on 2026-11-18

The current `main` source files were compared with the clean working branch. The relevant files currently match:

- `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`
- `supabase/functions/_shared/maintenance.ts`
- `supabase/config.toml`

The SQL draft currently:

- Creates six tables under `private`; all six have RLS enabled.
- Defines the five public maintenance RPCs as `SECURITY INVOKER` with an empty `search_path` and schema-qualified object references.
- Checks `auth.uid()` and `public.is_admin()` inside the four management RPCs.
- Grants management RPC EXECUTE to `authenticated` and revokes it from `PUBLIC` and `anon`.
- Grants `USAGE` on schema `private` to `anon` and `authenticated`.
- Grants public read access to limited columns for status-related tables.
- Grants `authenticated` direct write privileges on selected columns/operations for events, private notes, event-scope links, audit logs, and idempotency rows. RLS policies further restrict these table operations to admins.

The Edge Function helper validates user JWTs. The database management RPCs independently perform admin authorization. The current helper does not perform a separate Edge-level admin-role precheck.

## 3. Documentation inconsistency to resolve

The opening summary in `docs/maintenance-prelaunch-review-v0.1.md` says there are no `anon`/`authenticated` private-table write grants. Its later detailed permission review says authenticated admins have selected write grants. The actual SQL draft confirms those selected grants exist.

For implementation decisions, the SQL source is the direct evidence of the current grants. The audit document should be reconciled in a later documentation-only update; neither statement should be repeated without this qualification.

## 4. Security boundary assessment

The current design is not a database-enforced RPC-only write model:

- An authenticated admin with the relevant table grants and matching RLS policy may issue direct table writes if the `private` schema is reachable through the Data API.
- Such direct writes may bypass RPC-level validation, idempotency handling, schedule-overlap rules, version checks, lifecycle transitions, and the intended complete audit workflow.
- Keeping `private` out of Data API Exposed schemas is an important additional boundary, but it does not remove the underlying SQL grants or make the database permission model RPC-only.
- RLS is still required; schema exposure settings are not a substitute for table ACLs and RLS.
- The audit table's row mutation/TRUNCATE triggers protect against ordinary row mutation paths, but the current direct INSERT grant means the database does not prove that every audit row was created by the intended RPC workflow.

This is a design weakness to address before release, not evidence that the production project is currently exposed. The maintenance schema and RPCs are not deployed in production according to the existing prelaunch review.

## 5. Architecture decision required

Two viable models must be compared with disposable PostgreSQL 17 tests before choosing:

### Option A — Keep SECURITY INVOKER

- Retain caller privileges and RLS enforcement.
- Retain only the minimum direct table grants required by the RPCs.
- Explicitly document that an authenticated admin may have direct table-write capability when the schema is exposed/reachable.
- Do not claim RPC-only writes, complete audit provenance, or that all invariants can only be reached through RPCs.
- Confirm whether this weaker guarantee is acceptable for the product.

### Option B — Enforce RPC-only writes with carefully constrained SECURITY DEFINER

Only select this model after verifying all of the following:

- Management RPCs have explicit `auth.uid() IS NOT NULL` and `public.is_admin()` checks inside each function; Edge checks are never the sole authorization boundary.
- Function owner is explicit and its table/RLS bypass characteristics are understood. No broad `service_role` impersonation or generic table-access helper is introduced.
- Functions use `SET search_path = ''` and fully qualified object references.
- `PUBLIC` and `anon` EXECUTE are revoked; only the intended API role receives EXECUTE.
- Direct `anon`/`authenticated` write grants on the private tables are revoked.
- Any RLS policy behavior under the actual function owner is tested; SECURITY DEFINER must not be assumed safe merely because it is used.
- Public status remains a narrowly scoped read RPC returning only an explicit public-field allowlist.
- Audit and idempotency writes remain atomic with the corresponding business operation.

A SECURITY DEFINER conversion is a material security architecture change and must not be performed as a blanket text replacement.

## 6. Edge authorization

The current database RPCs already recheck admin authorization. A separate Edge-level admin precheck may improve early error handling and defense in depth, but it is not a replacement for database checks and must not trust a frontend-supplied user/admin identifier.

Before implementing an Edge precheck, define its exact server-side verification call and test invalid, expired, non-admin, and admin JWTs. Avoid adding a new public RPC solely for convenience unless its EXECUTE ACL and return shape are narrowly constrained.

## 7. Required acceptance tests

Run in disposable PostgreSQL 17 / GoTrue / PostgREST environments only:

1. `anon` cannot execute management RPCs or write private tables.
2. Authenticated non-admin cannot execute management RPCs or write private tables.
3. Authenticated admin can perform intended operations through the approved API.
4. If Option B is selected, authenticated admin direct table INSERT/UPDATE/DELETE is denied while RPC operations still succeed.
5. Forged actor/user/role fields cannot alter the actor; audit actor derives from `auth.uid()`.
6. Public status exposes only the documented public fields; private notes and audit data never appear.
7. Schedule overlap, global/local scope conflicts, version conflicts, lifecycle constraints, and idempotency remain atomic and correct.
8. Audit mutation and TRUNCATE protections remain effective.
9. Data API tests confirm `private` is not exposed in the isolated PostgREST configuration.
10. Edge tests cover missing, invalid, expired, non-admin, and admin tokens.

## 8. Release boundary

Until the architecture decision and acceptance tests are complete:

- Do not place this draft under `supabase/migrations/`.
- Do not execute SQL against production.
- Do not deploy Edge Functions.
- Do not change Supabase Dashboard settings or secrets.
- Do not merge into `main`.
- Do not add paid services or resources.

This document records findings and test requirements only; it is not authorization to change production systems.
