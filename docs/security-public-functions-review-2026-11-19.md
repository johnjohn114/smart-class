# Supabase public function security review — 2026-11-19

## Scope and safety

- Reviewed the live PostgreSQL function catalog and selected function definitions using read-only queries.
- No production SQL, grants, function definitions, Edge Functions, or Dashboard settings were changed.
- This document is an audit record and proposed remediation plan, not an approved migration.
- Project ref: `fsoowongtavlsrwvzbze`.

## Findings

### 1. EXECUTE privilege exposure on administrative functions

The live catalog reports `anon_can_execute = true` and `authenticated_can_execute = true` for the following **16** `public.admin_*` functions. All 16 are `SECURITY DEFINER`.

- `admin_activity_analytics()`
- `admin_adjust_growth_points(uuid, integer, text)`
- `admin_apply_competition_rewards(uuid)`
- `admin_cancel_order(uuid)`
- `admin_complete_order(uuid)`
- `admin_delete_growth_reward(uuid)`
- `admin_delete_video(uuid)`
- `admin_grant_competition_reward(uuid, text, text, text, integer, uuid)`
- `admin_mark_competition_attendance(uuid, text, text)`
- `admin_mark_competition_member_attendance(uuid, uuid, text, text)`
- `admin_mark_order_paid(uuid)`
- `admin_promote_competition_waitlist(uuid)`
- `admin_reset_growth_member(uuid, text)`
- `admin_settle_competition(uuid)`
- `admin_upsert_growth_reward(uuid, text, text, text, text, text, integer, text, uuid, integer, integer, text, text, text, integer, timestamptz, timestamptz, integer, boolean)`
- `admin_upsert_video(jsonb)`

EXECUTE privilege alone does not prove an operation succeeds. The definitions sampled in this pass generally perform admin checks:
- Most check for a matching `profiles.id = auth.uid()` row with `role = 'admin'`.
- `admin_adjust_growth_points` delegates to `public.is_admin()`, which checks the authenticated UID against `profiles`.
- `admin_delete_video` and `admin_upsert_video` delegate to `public.is_admin_user()`, which also checks the authenticated UID against `profiles`.
- `admin_reset_growth_member` explicitly rejects a NULL `auth.uid()` and checks `is_admin()`.

Therefore, the broad EXECUTE grants are an unnecessary exposure surface, but the read-only checks do **not** establish that all 16 functions can be successfully used by anonymous callers. The two NULL-sensitive checks below are the confirmed authorization logic defects found so far.

### 2. Two confirmed NULL-sensitive authorization checks

The live definitions of these functions use a check equivalent to:

```sql
if caller_role <> 'admin' then
  raise exception '...';
end if;
```

- `public.admin_delete_growth_reward(uuid)`
- `public.admin_upsert_growth_reward(...)`

In SQL, a comparison with NULL yields UNKNOWN, and PL/pgSQL IF does not enter the branch for UNKNOWN. If no profile row is found, `caller_role` can remain NULL and this check does not reject the caller.

Proposed correction:

```sql
if caller_role is distinct from 'admin' then
  raise exception '只有管理員可以執行此操作';
end if;
```

This is a confirmed logic defect in the current definitions and should be fixed in a reviewed migration.

### 3. Dependency / trigger check

- Catalog dependency query found no catalog-recorded function dependents for these 16 admin functions.
- None of the 16 is attached to a non-internal trigger.
- This does not detect every dynamic SQL call or application-side RPC call. A repository-wide source search is still needed before changing grants.
- Some admin functions call shared helpers (for example `award_growth_points`, `check_activity_badges`, `is_admin`, and `is_admin_user`). These helpers have separate permissions and should not be blanket-revoked without reviewing their intended use.

### 4. Authorization helpers

- `public.is_admin()` is `SECURITY DEFINER`, checks `auth.uid()` against `profiles.role = 'admin'`, and the catalog reports EXECUTE for `authenticated` but not `anon`.
- `public.is_admin_user()` is `SECURITY DEFINER`, checks `auth.uid()` against `profiles.role = 'admin'`, and the catalog reports EXECUTE for both `anon` and `authenticated`. An anonymous caller receives the boolean result of the admin check; it does not itself grant admin identity.
- `public.award_growth_points` is `SECURITY DEFINER`, executable by `anon` but not `authenticated` in the inspected catalog. It does not itself perform an admin check in the inspected definition. It is called internally by `admin_adjust_growth_points`, so its broad anon grant is a separate high-priority item for review; do not change it until its legitimate call paths and public exposure are understood.

## Proposed remediation sequence

1. Complete a full inventory of all public `SECURITY DEFINER` functions, their grants, callers, and trigger dependencies.
2. Review source-code RPC call sites and all callers of shared helpers such as `award_growth_points`.
3. Correct the two NULL-sensitive checks with `IS DISTINCT FROM`.
4. Prepare explicit per-signature grants: revoke EXECUTE from `PUBLIC` and `anon` for administrative RPCs; grant only to the intended authenticated/service roles after caller paths are verified.
5. Separately review `award_growth_points` and other helpers with broad grants.
6. Add regression tests for anonymous, ordinary authenticated, and admin callers.
7. Run CI and Supabase security advisors.
8. Only after review and explicit approval, prepare a production migration. Do not run it as part of this audit.

## Important caveats

- `anon_can_execute = true` indicates a database privilege, not proof of successful business operation.
- The definition review in this pass covers all 16 admin functions at a high level, but does not replace full testing with real JWT roles or exhaustive application call-site tracing.
- The proposed grant pattern is not yet approved for deployment. Some helpers may have legitimate internal or public callers; dependencies must be checked first.
- No production change has been made.
