# Supabase public function security review — 2026-11-19

## Scope and safety

- Reviewed the live PostgreSQL function catalog using read-only queries.
- No production SQL, grants, function definitions, Edge Functions, or Dashboard settings were changed.
- This document is an audit record and proposed remediation plan, not an approved migration.
- Project ref: `fsoowongtavlsrwvzbze`.

## Findings

### 1. Public EXECUTE inheritance on administrative functions

The live catalog reports `anon_can_execute = true` and `authenticated_can_execute = true` for the following 15 `public.admin_*` functions. These functions are also `SECURITY DEFINER`.

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

The fact that a role has EXECUTE privilege does not alone prove an operation succeeds. The function body must enforce authorization. However, granting anonymous callers the ability to reach privileged SECURITY DEFINER code is unnecessary exposure and should be removed after verifying each function's intended caller.

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

### 3. Other functions require a separate authorization pass

A first pass showed several other SECURITY DEFINER functions with broad EXECUTE privileges. They are not all administrative endpoints. Before changing grants, review each function's intended use, caller identity, and whether it is called by triggers or other functions. Do not bulk-revoke every SECURITY DEFINER function.

## Proposed remediation sequence

1. Complete a full inventory of all public SECURITY DEFINER functions, including callers and trigger dependencies.
2. Confirm every `admin_*` function checks the authenticated caller against the trusted `profiles.role = 'admin'` record (and rejects NULL / missing identity).
3. Correct the two NULL-sensitive checks with `IS DISTINCT FROM`.
4. Prepare explicit per-signature grants: revoke EXECUTE from `PUBLIC` and `anon` for administrative RPCs; grant only to the intended authenticated/service roles after caller paths are verified.
5. Add regression tests for anonymous, ordinary authenticated, and admin callers.
6. Run CI and Supabase security advisors.
7. Only after review and explicit approval, prepare a production migration. Do not run it as part of this audit.

## Important caveats

- `anon_can_execute = true` indicates a database privilege, not proof of successful business operation.
- The initial body scan found admin checks in the sampled admin functions, but the complete body-by-body authorization review is not yet complete.
- The proposed grant pattern is not yet approved for deployment. Some functions may have legitimate internal or service callers; dependencies must be checked first.
- No production change has been made.
