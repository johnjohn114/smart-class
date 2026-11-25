# Maintenance rate-limit security review v0.1

Date: 2026-11-25
Status: review findings only; prototype is not approved for production or app integration.

## Scope inspected

- `supabase/tests/sql/rate-limit-prototype-setup.sql`
- `supabase/tests/sql/rate-limit-prototype-concurrency.sql`
- `.github/workflows/maintenance-edge-functions.yml` rate-limit CI step
- `docs/maintenance-rate-limit-prototype.md`
- `docs/maintenance-api-spec-v0.7.md`
- `supabase/functions/_shared/maintenance.ts`

## Findings

### Pass: atomic counter behavior in the current CI scenario

The prototype uses one `INSERT ... ON CONFLICT DO UPDATE` for each bucket. The CI test sends 40 concurrent calls to one bucket with a 5-per-60-second policy and asserts exactly 5 allowed, 35 denied, one bucket row, and a stored count capped at 6. This is useful evidence for serialization of updates to one bucket under this test setup.

### Blocker: CI does not validate the intended caller's database privileges

The workflow connects to the disposable rate-limit database as `postgres` for both setup and pgbench. This is a superuser test path, so it does not prove that `anon`, `authenticated`, or a narrowly scoped function owner can or cannot execute the function or read/write the bucket table.

Before any production consideration, add role-based tests using non-superuser roles and explicit grants/revokes. Keep the lab schema unexposed and do not grant direct table access to client roles.

### Blocker: bucket identity and policy are caller-controlled parameters

The function accepts `p_bucket_key`, `p_limit`, and `p_window_seconds`. The current CI call hardcodes a test key and policy, but the SQL function itself does not authenticate a user or derive an identity. If exposed as a callable RPC, a caller could choose another bucket key or request a more permissive policy.

Production design must derive the bucket identity from a verified JWT subject inside a trusted server/database boundary, and choose endpoint policy on the server. Never accept actor IDs, user IDs, roles, limits, or window durations from the browser as authoritative values. This prototype is not an authenticated-user limiter yet.

### Blocker: no retention / cleanup behavior is tested

The bucket table retains one row per bucket key indefinitely. Capping the request counter prevents unbounded counter growth within a bucket, but does not prevent unbounded growth in the number of distinct bucket keys. Production design needs a bounded key space and an explicit retention/cleanup strategy, including tests proving cleanup cannot reset an active bucket early. Do not add a paid scheduler solely for this prototype.

### Missing test: window rollover and retry-after behavior

The current test validates a single active window only. It does not verify that a bucket resets after expiry, that `retry_after_seconds` is positive and bounded when denied, or that allowed responses report the expected remaining quota. Add deterministic boundary tests before considering integration.

### Missing test: policy consistency and endpoint isolation

The SQL function accepts a different limit/window on each call for the same bucket. The current test always uses 5/60, so it does not test inconsistent policy calls. Production policy should be fixed per endpoint on the server, and buckets should be namespaced by endpoint/policy so one route cannot consume or weaken another route's quota.

### Not in scope: HTTP 429 integration

Maintenance API v0.7 explicitly does not promise HTTP 429 / `RATE_LIMITED`. The shared Edge handler currently has no rate-limit call or 429 mapping. Do not silently add a 429 response or change v1 behavior. Any future API contract change needs a separate versioned decision and tests for `Retry-After`.

### Not in scope: IP-based public endpoint limiting

The current prototype only exercises a single admin-style bucket key. Do not use client-supplied `X-Forwarded-For` or similar headers as an IP identity until the trusted Supabase gateway/proxy header contract is verified. No IP limiter is approved by this review.

## Required gates before integration

1. Keep the prototype isolated from Maintenance v1 and from production migrations.
2. Add non-superuser role/ACL tests for schema usage, function execute, and table access.
3. Derive authenticated user identity from verified JWT claims; do not accept a caller-provided identity.
4. Fix endpoint policy server-side and namespace buckets by endpoint.
5. Add window rollover, remaining quota, retry-after, invalid argument, and concurrent same-bucket tests.
6. Define bounded bucket retention and test safe cleanup.
7. Decide failure behavior if the limiter database call fails (fail closed vs fail open) for each endpoint.
8. Only after the above, separately propose a versioned HTTP 429 / `Retry-After` contract. Keep public status/IP limiting separate until trusted client IP forwarding is verified.

## Safety boundary

This review does not authorize production SQL, migrations, Edge Function deployment, feature-flag changes, PR merge, or paid services. PR #34 remains Draft.
