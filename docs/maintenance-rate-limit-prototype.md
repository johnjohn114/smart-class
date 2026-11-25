# Maintenance rate-limit prototype (CI only)

Status: isolated experiment; not part of Maintenance v1 and not deployed.

## Design under test

- One PostgreSQL row per stable bucket key.
- One atomic INSERT ... ON CONFLICT DO UPDATE per request serializes updates to that bucket.
- Fixed window: 5 requests per 60 seconds in the CI concurrency test.
- The stored count is capped at limit + 1 so rejected traffic cannot grow the counter without bound.
- The function returns allow/deny, remaining quota, and retry-after seconds.

## Boundaries

- CI creates this schema in a disposable PostgreSQL 17 service only.
- No production migration, Supabase SQL execution, Edge Function deployment, feature-flag change, or app integration.
- No Redis or paid external service.
- Do not use an IP bucket until the trusted proxy/header chain is verified. The current prototype tests only an authenticated-user-style bucket key.
- A production design must separately define bucket identity, per-endpoint policies, cleanup/retention, failure behavior, and how 429 plus Retry-After are surfaced.

The prototype is not yet approved for production use.
