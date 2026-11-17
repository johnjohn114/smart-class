# Maintenance Contract and SQL Review v0.1

> Date: 2026-11-17 (Asia/Taipei)  
> Scope: source consistency review, isolated test results, and pre-migration blockers.  
> Safety: no production database changes, migration repair, Edge Function deployment, or paid resources.

## 1. Current CI result

The exact source commit `58db0f1a86d9c7e92693848dafa596d195345416` passed GitHub Actions run [44079551407](https://github.com/johnjohn114/smart-class/actions/runs/44079551407).

All three jobs succeeded:
- Deno type check, Edge Function tests, feature-gate tests, and SQL static guardrails.
- GoTrue-issued JWT and PostgREST integration.
- Isolated PostgreSQL 17 RPC/RLS, growth authorization, default privileges, and trigger regression tests.

The GoTrue/PostgREST test additionally checked the exact maximum text lengths and one-character-over-limit rejection for title, message, internal note, and reason. The isolated test run is not a production deployment or production environment smoke test.

## 2. UI / Edge Function / SQL consistency review

The following values match across `admin.html`, `supabase/functions/_shared/maintenance.ts`, and `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`:

| Field | Maximum | UI | Edge Function | SQL |
|---|---:|---|---|---|
| `title` | 200 | maxlength 200 | parser 200 | DB check 200 |
| `message` | 4,000 | maxlength 4000 | parser 4000 | DB check 4000 |
| `internal_note` | 4,000 | maxlength 4000 | parser 4000 | DB validation 4000 |
| `reason` | 500 | maxlength 500 | parser 500 | DB validation 500 |

The seven scope identifiers match across UI checkboxes, Edge Function validation, SQL CHECK/seed:
`site_core`, `announcements_info`, `events_competitions`, `video_content`, `membership_growth`, `store_support`, `downloads_app`.

This proves source consistency only. It does not prove production seed deployment.

## 3. Additional database-boundary tests

The new integration tests assert:
- Exact maximum lengths are accepted.
- One character above each maximum is rejected by the database RPC.
- Existing tests continue to cover anonymous/member/admin roles, signed JWT validation, public response redaction, scoped public status, global/local/site_core conflicts, half-open adjacent windows, idempotency, version conflicts, and concurrent scheduling.

## 4. API contract decisions now explicit

- v1 status returns currently active maintenance only; no future preview.
- Started events cannot have schedule or scope changed through ordinary update.
- Text field limits are fixed as listed above.
- HTTP 429 `RATE_LIMITED` remains a documented error code but is **not implemented** in the current Edge Functions. Do not claim rate limiting is active. This must be resolved before enabling public endpoints: either implement a durable, tested limiter or remove the 429 promise and document the platform-only limits and abuse response.
- Audit retention is not finalized. No automatic audit deletion/cleanup is implemented.
- Idempotency retention is not finalized. No automatic idempotency cleanup is implemented. Do not add an unreviewed TTL or cron job.

The updated API specification is `docs/maintenance-api-spec-v0.6.md`.

## 5. SQL review observations

The current SQL remains a development draft, not a migration. Its six-table private schema, five SECURITY INVOKER RPCs, JWT-derived actor, server-side request hash, column-scoped note grants, RLS, and transactional writes are covered by the isolated suite.

Before production approval, conduct one final independent SQL review of:
- all invoker grants and RLS policies under the exact production role setup;
- malformed JSON edge cases and RPC error mapping;
- advisory lock scope and transaction behavior;
- audit immutability and retention;
- idempotency replay and any eventual cleanup semantics;
- actual Supabase Dashboard Data API Exposed schemas (confirm `private` is excluded).

## 6. Migration and production blockers

1. PR #16 contains only a CLI-generated **empty 0-byte migration shell**. It must not be merged or applied empty.
2. Production migration history remains empty while existing application schema objects exist. The full baseline manifest and safe non-replaying baseline strategy are unresolved.
3. Two App Releases migration alternatives conflict; production matches variant A. Neither should be replayed blindly.
4. Supabase Dashboard Data API Exposed schemas have not been inspected; CI only proves the disposable PostgREST schema list.
5. Production Edge Function CORS/env values and runtime smoke tests are not verified.
6. Rate-limit and retention decisions above remain unresolved.
7. Existing project-wide Security Advisor findings remain a separate workstream.

## 7. Execution boundary

Until all blockers are resolved and a separate release review approves the exact migration:
- keep `MAINTENANCE_FEATURE_ENABLED = false`;
- do not run `db push`, `migration repair`, or production SQL writes;
- do not deploy the five maintenance Edge Functions;
- do not enable the feature;
- do not create a paid Supabase project or branch.

**Conclusion: source consistency and isolated CI coverage improved; production Migration is still NOT READY.**
