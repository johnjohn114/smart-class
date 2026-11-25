# Rate-limit identity and retention design proposal v0.1

Status: design proposal only. Not production-approved and not integrated into Maintenance v1.

## 1. Trusted identity boundary

The current lab function accepts `p_bucket_key`, `p_limit`, and `p_window_seconds` from its caller. Those parameters are test conveniences only and must never be exposed as a public RPC contract.

For a future Supabase implementation:

1. The Edge Function validates the incoming bearer token against Supabase Auth (the existing shared handler already validates required-auth tokens through `/auth/v1/user`).
2. The Edge Function must not accept a user ID, role, bucket key, limit, or window from request JSON, query parameters, or caller-controlled headers.
3. A database RPC invoked with the user's verified JWT can derive the actor from `auth.uid()`; the function must reject a NULL UID. The database must not trust a caller-supplied actor UUID.
4. Endpoint policy is a constant selected by server-side endpoint code. The caller cannot choose or loosen the limit/window.
5. Namespace the bucket with a fixed endpoint identifier plus the derived UID. Keep public status/IP buckets separate; do not infer IP identity from unverified forwarding headers.
6. Before enabling this path, test through disposable GoTrue + PostgREST using actual GoTrue-issued JWTs for two distinct users. Prove that a caller cannot spend another user's quota by changing payloads, query strings, or headers.
7. If the RPC uses SECURITY DEFINER, set an empty/fixed search_path, fully qualify every object, tightly scope EXECUTE, keep the table inaccessible to API roles, and review owner/grants. SECURITY DEFINER does not itself authenticate the caller.

### Integration blocker

The current Maintenance v0.7 API contract does not promise rate limiting or HTTP 429. Do not add a limiter call to `createMaintenanceHandler` or alter responses until a separately versioned API decision is approved.

## 2. Retention without a paid scheduler

The current prototype has one row per distinct bucket key and no cleanup. A bounded request counter does not bound the number of distinct keys.

Proposed low-complexity strategy for a later prototype:

- Store a `last_seen_at` timestamp on each bucket.
- Use a fixed, server-defined retention horizon (initial proposal: 24 hours after last activity).
- Delete only rows older than the retention horizon; never delete a bucket whose active window has not expired.
- Run cleanup opportunistically in a bounded batch from a trusted server-side maintenance path, not from an unauthenticated public endpoint.
- Use `FOR UPDATE SKIP LOCKED` or an equivalent safe batching pattern so cleanup does not wait on active request transactions.
- Bound work per invocation (for example, at most 500 stale rows); repeat on later trusted invocations.
- Do not introduce pg_cron, an external scheduler, Redis, or a paid service for this prototype.

The 24-hour horizon and batch size are proposals, not finalized policy. They need workload and retention review before implementation.

## 3. Required tests

### Identity
- Missing JWT subject is rejected.
- User A and User B receive independent buckets.
- Tampering with any caller-supplied user/bucket/policy fields has no effect because those fields are not accepted.
- Invalid/expired JWT is rejected by GoTrue before the limiter RPC.
- A non-admin user cannot call admin-only maintenance operations even if authenticated.

### Retention
- A recently active bucket is never deleted.
- A bucket with an unexpired active window is never deleted.
- A stale bucket is deleted after the configured retention horizon.
- Cleanup deletes no more than the configured batch size.
- Concurrent consumption and cleanup do not lose a valid request or reset an active bucket.
- Re-running cleanup is idempotent.

## 4. Failure behavior decision needed before integration

For administrative mutations, default proposal is fail closed: if the limiter cannot be reached, do not perform the mutation. For read-only public status, a separate decision is needed because blocking status during limiter outage may reduce availability. No behavior is implemented by this document.

## 5. Safety boundary

This document does not authorize production SQL, migrations, Edge Function deployment, feature-flag changes, PR merge, or paid services. Keep the prototype isolated and PR #34 in Draft.
