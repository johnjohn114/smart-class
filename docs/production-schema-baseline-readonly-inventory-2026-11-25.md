# Production Supabase schema baseline — read-only inventory

> Captured: 2026-11-25 (Asia/Taipei)  
> Project ref: `fsoowongtavlsrwvzbze`  
> Database: `postgres`, PostgreSQL `17.11`, region `ap-northeast-1`  
> Scope: read-only catalog inventory via Supabase database tools. No DDL/DML, migration, setting, or data-row changes were performed.  
> Status: **inventory only — NOT a complete schema-only dump and NOT a reconstructed baseline.**

## 1. Executive finding

The production migration ledger remains unresolved:

- Supabase `list_migrations` returned an empty migration list.
- `to_regclass('supabase_migrations.schema_migrations')`, `to_regclass('supabase_migrations')`, and `to_regclass('public.schema_migrations')` all returned `NULL`.
- The database is active and reports PostgreSQL 17.11.
- The project contains application objects and managed Supabase objects across multiple schemas. A `public`-only export would be incomplete.

**Decision:** do not run `db pull`, `db push`, migration repair, hand-written ledger insertion, or any production DDL as a shortcut. A genuine schema-only dump and a disposable blank-database replay are still required before establishing the global migration baseline.

## 2. Schema and relation inventory

| Schema | Owner | Tables | Views | Sequences | Notes |
|---|---|---:|---:|---:|---|
| `auth` | `supabase_admin` | 27 | 0 | 1 | Managed Auth objects |
| `extensions` | `postgres` | 0 | 2 | 0 | Extension views |
| `graphql` | `supabase_admin` | 0 | 0 | 0 | Schema present |
| `graphql_public` | `supabase_admin` | 0 | 0 | 0 | Schema present |
| `public` | `pg_database_owner` | 44 | 1 | 2 | Application schema |
| `realtime` | `supabase_admin` | 3 | 0 | 1 | Managed Realtime objects |
| `storage` | `supabase_admin` | 10 | 0 | 0 | Managed Storage objects |
| `vault` | `supabase_admin` | 1 | 1 | 0 | Vault objects |
| **Total** | | **85** | **4** | **4** | No foreign tables found |

The 44 `public` tables contain 412 columns. Each currently has RLS enabled. The detailed column/PK/FK inventory was retrieved from the database tool; the full per-column schema is not reproduced here because this document is a summary, not a dump.

### Public table inventory

`announcements`, `site_settings`, `visitor_profiles`, `profiles`, `products`, `visitor_accounts`, `support_tickets`, `coupons`, `competitions`, `competition_results`, `quick_links`, `forms`, `form_questions`, `form_responses`, `form_answers`, `competition_categories`, `notifications`, `member_no_counter`, `competition_registrations`, `announcement_reads`, `growth_levels`, `growth_point_transactions`, `growth_tasks`, `growth_user_tasks`, `growth_achievements`, `growth_user_achievements`, `growth_activity_days`, `growth_rewards`, `growth_reward_redemptions`, `growth_achievement_unlock_history`, `growth_reset_history`, `videos`, `ai_announcement_generations`, `competition_attendance`, `competition_waitlist`, `activity_badges`, `user_activity_badges`, `competition_reward_rules`, `competition_reward_grants`, `download_files`, `orders`, `order_items`, `app_releases`, `device_push_tokens`.

## 3. Application schema structural counts

| Object | `public` count | Notes |
|---|---:|---|
| Tables | 44 | 412 columns |
| Views | 1 | `activity_member_stats` |
| Sequences | 2 | `device_push_tokens_id_seq`, `member_no_seq` |
| Indexes | 109 | 62 unique; 0 invalid |
| Primary-key constraints | 44 | |
| Foreign-key constraints | 51 | |
| Unique constraints | 16 | |
| Check constraints | 39 | |
| RLS policies | 98 | 3 policies explicitly include `anon`; 84 explicitly include `authenticated`; other policies may target `public` |
| User triggers | 7 | All enabled |
| Functions | 38 | 36 SECURITY DEFINER; no procedures |

The only application view found in `public` is `activity_member_stats`. No materialized views or foreign tables were found in the inventoried schemas.

## 4. RLS posture by schema

| Schema | Tables | RLS enabled | FORCE RLS |
|---|---:|---:|---:|
| `public` | 44 | 44 | 0 |
| `storage` | 10 | 10 | 0 |
| `auth` | 27 | 16 | 0 |
| `realtime` | 3 | 1 | 0 |
| `vault` | 1 | 0 | 0 |

This is an inventory, not a recommendation to enable/disable RLS on managed Supabase schemas. The Maintenance design's FORCE RLS requirement applies to its own future private tables; it must not be generalized into blanket changes to managed schemas.

## 5. Application trigger inventory

All seven `public` user triggers are enabled:

| Table | Trigger | Function | SECURITY DEFINER |
|---|---|---|---|
| `competition_registrations` | `trg_check_competition_registration_rules` | `check_competition_registration_rules()` | Yes |
| `competition_registrations` | `trg_growth_registration_reward` | `growth_registration_reward()` | Yes |
| `competition_results` | `trg_growth_result_reward` | `growth_result_reward()` | Yes |
| `competitions` | `trg_competition_publish_time` | `set_competition_publish_time()` | No |
| `profiles` | `trg_profiles_member_no` | `assign_member_no_and_nickname()` | Yes |
| `profiles` | `trg_protect_profile_fields` | `protect_profile_fields()` | No |
| `visitor_accounts` | `trg_visitor_accounts_profile` | `ensure_visitor_profile()` | Yes |

Managed `realtime` and `storage` schemas have another 12 user triggers combined (1 Realtime, 11 Storage). These must be preserved in any complete schema capture/replay.

## 6. Installed extensions

Only the following five extensions were reported as installed (not merely available):

- `pg_stat_statements` 1.11 — schema `extensions`
- `pgcrypto` 1.3 — schema `extensions`
- `plpgsql` 1.0 — schema `pg_catalog`
- `supabase_vault` 0.3.1 — schema `vault`
- `uuid-ossp` 1.1 — schema `extensions`

The extension catalogue also listed many available-but-not-installed extensions. Do not enable any extension as part of baseline reconstruction unless the actual dump or a verified dependency requires it.

## 7. Default privileges — important baseline detail

The live `pg_default_acl` catalogue includes broad API-role defaults:

- `postgres` in `public`: future tables, sequences and functions default to grants for `anon`, `authenticated`, and `service_role`.
- `postgres` in `storage`: similarly broad defaults.
- `supabase_admin` in `public`, `graphql`, and `graphql_public`: broad API-role defaults are also present.
- Other managed owners have their own schema-specific defaults.

The existing candidate hardening migration changes defaults for `postgres` in `public`; it does not normalize every managed owner/schema default. A reconstructed baseline must preserve the actual current state first. Any security-hardening change must be treated as a separate, explicitly reviewed migration, not silently folded into a purported baseline dump.

## 8. What this inventory does not establish

This catalog snapshot does **not** establish:

- Full CREATE statements for all 85 tables, columns, constraints, indexes, views, functions and policies.
- All object grants/ACLs, ownership and dependency ordering in a restorable SQL dump.
- Complete Auth, Storage, Realtime, Vault internal schema replayability.
- Data contents, sequence current values, storage objects, Auth users or other production records.
- Which historical migration files were actually applied.
- Whether a blank database can be reconstructed from the repository migrations.

The earlier migration-file fingerprint review remains only a structural comparison; matching structure is not proof of execution.

## 9. Required next steps

1. Obtain a genuine schema-only export using a supported read-only method. Current working environment has no Supabase CLI, `psql`, `pg_dump` or Docker, so the Supabase MCP catalog queries cannot replace `pg_dump`.
2. Keep the export local/private; it may contain sensitive object definitions. Do not commit secrets or production data. Review the export for embedded credentials or sensitive comments before sharing any excerpts.
3. Reconcile the export against the seven repository migration files already audited and all later migrations.
4. Create a clean, disposable PostgreSQL 17 environment using only free CI resources and replay the verified baseline plus migration sequence.
5. Compare resulting schemas, owners, ACLs, RLS, policies, triggers, functions, extensions, sequences and indexes against the captured production metadata.
6. Only after the replay is proven, decide the Maintenance final migration path. Until then the Maintenance SQL remains a development draft.

## 10. Safety boundary

This document was created from read-only catalog queries only. No production DDL/DML, migration operation, Edge Function deployment, Data API exposure change, feature-flag change, paid service or PR merge was performed. The Maintenance PR remains Draft.
