# Seven-file migration reconciliation audit — 2026-11-24

Scope: read-only comparison of the seven files under `supabase/migrations/` on `feature/maintenance-single-pass-migration-20261122`, using the current repository source and the production catalog observations recorded in the Maintenance Phase 2 closeout document.

This is a development review artifact only. It does not authorize or perform production SQL, migration-history repair, deployment, feature-flag changes, PR merge, dashboard changes, or paid services.

## Executive summary

| File | Production evidence | Disposition |
|---|---|---|
| `202610310001_app_releases.sql` | Live `public.app_releases` shape, defaults, unique version index, and five policy names/operations align with this file. Execution provenance is unknown. | Closest live structural match; do not replay. |
| `20261031_app_releases.sql` | Live table lacks `is_latest`; helper `is_app_release_admin()` is absent; other columns/defaults/constraints differ. | Incompatible with observed live schema; preserve for history, do not apply. |
| `202611160001_growth_function_authorization_hardening.sql` | Most target functions exist, but internal helper is absent and broad live anon EXECUTE remains. | Candidate hardening is not live; high-impact ACL/function change requires final dependency review and approved rollout. |
| `202611170001_default_privileges_and_trigger_hardening.sql` | Production postgres defaults still grant broad table/sequence/function privileges in `public`; storage has separate schema defaults. | Candidate effects are not present in observed public defaults; review scope carefully before any use. |
| `20261117121103_maintenance_system_initial.sql` | Production has no `private` schema or Maintenance objects. | Legacy v1 design only; do not use as the current deployment source. |
| `20261121140000_maintenance_rpc_least_privilege_upgrade.sql` | Depends on the old Maintenance objects and `maintenance_rpc_executor`; production has no `private` schema. | Legacy upgrade only; do not apply or combine with the current single-pass design. |
| `26.11.3_calendar_fields.sql` | All four columns, both check constraints, and the partial index exist with matching definitions. | Live structural match; execution provenance unknown; do not replay. |

## Per-file findings

### 1. `202610310001_app_releases.sql`

- Defines `public.app_releases` with a unique positive `version_code`, `published DEFAULT false`, nullable `published_at`, and nullable `created_by REFERENCES auth.users(id)`.
- Uses direct `profiles.role = 'admin'` policy predicates and does not create `is_app_release_admin()`.
- The recorded production catalog matches the nine-column table shape, defaults/nullability, unique `version_code` index, and five policy names/operations.
- This is a structural match, not proof that this exact file was executed.
- Separate live ACL finding: `anon` currently has unnecessary INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, and TRIGGER table privileges in addition to SELECT. Existing RLS currently blocks ordinary anon writes because there are no anon write policies, but the grants should be addressed through a separately reviewed candidate and regression test. No ACL was changed here.

### 2. `20261031_app_releases.sql`

- Defines a different table design: `is_latest`, published default true, non-null published timestamp, no `created_by`, no unique constraint on `version_code`, an HTTPS check, and a SECURITY DEFINER helper `is_app_release_admin()`.
- The recorded live table has no `is_latest` column and the helper is absent. Its index references `is_latest`, so running this file against the observed live table would fail when creating that index.
- The current frontend uses neither `is_latest` nor `is_app_release_admin()`.
- Preserve this file as historical source; do not run it or combine it with file 1.

### 3. `202611160001_growth_function_authorization_hardening.sql`

- Changes postgres-owned function defaults and replaces multiple Growth/admin function definitions; adds `_refresh_growth_level_internal(uuid)`; narrows function EXECUTE grants with an explicit allowlist.
- Production evidence recorded in the closeout notes shows the internal helper is absent and broad anon EXECUTE remains on privileged routines. Therefore the candidate's intended authorization state is not live.
- The candidate addresses material authorization defects: arbitrary-member point awards, arbitrary-target achievement checks, arbitrary-target level refresh, NULL-caller handling for activity badges, and NULL-safe admin checks.
- It also changes default EXECUTE behavior and relies on internal SECURITY DEFINER call paths. The complete allowlist, trigger-function handling, service_role expectations, and all frontend RPC dependencies must remain covered by regression tests.
- Do not treat the file as an ordinary additive migration or deploy it before the production baseline and final ACL matrix are reconciled.

### 4. `202611170001_default_privileges_and_trigger_hardening.sql`

- Revokes postgres-owned default table, sequence, and function grants in `public`, removes global default PUBLIC function EXECUTE for postgres-owned functions, and replaces `ensure_visitor_profile()`.
- Revokes direct API-role EXECUTE on selected trigger functions. Trigger invocation itself does not require API roles to have direct EXECUTE.
- Production catalog observations show broad postgres defaults still present for tables, sequences, and functions in `public`. The intended public default changes are therefore not reflected in the observed live state.
- The global PUBLIC function revoke affects future postgres-owned functions across schemas; schema-specific defaults (including separately observed `storage` defaults) remain distinct. Do not assume this makes every schema opt-in.
- This is a broad future-object behavior change. Validate object ownership, all relevant schema-specific defaults, trigger behavior, and application-created objects before any rollout.

### 5. `20261117121103_maintenance_system_initial.sql`

- Creates six tables in `private`, seven scope seed rows, indexes, RLS policies, triggers, and five public RPCs using the earlier SECURITY INVOKER/RLS design.
- It grants direct authenticated write capabilities to several private tables and depends on the earlier RPC execution model.
- Its own preflight rejects an existing `private` schema or pre-existing Maintenance RPC names.
- Production currently has no `private` schema and no Maintenance RPCs/tables. That establishes absence of the feature objects in the inspected production catalog, not a complete historical execution record for all environments.
- This file is a legacy path. It must not be combined with the current PR #34 single-pass SQL.

### 6. `20261121140000_maintenance_rpc_least_privilege_upgrade.sql`

- This is a forward upgrade for the legacy Maintenance schema. It creates/uses `maintenance_rpc_executor`, changes ownership of four admin RPCs, and adjusts EXECUTE grants.
- It assumes the objects from the initial Maintenance migration already exist.
- The current PR #34 single-pass design instead uses built-in `pg_database_owner` and does not use the custom executor role.
- The upgrade cannot stand alone and is superseded by the current architecture. Do not apply it, and do not append the new single-pass draft after it as if that neutralized the intermediate role/privilege design.

### 7. `26.11.3_calendar_fields.sql`

- Adds `event_date`, `event_end_date`, `event_date_source`, and `event_date_confirmed` to `public.announcements`; adds two checks and a partial index.
- The recorded production catalog contains all four columns, both checks with matching definitions, and the matching partial index on confirmed published events.
- Treat the effects as already present when planning a baseline; do not replay blindly.
- The empty migration ledger means the exact execution provenance remains unknown.

## Cross-file blockers and decisions

1. **No trustworthy global migration ledger:** production migration listing is empty and `supabase_migrations` is absent. Structural matches cannot establish which file ran or when.
2. **App Releases duplication is a real design conflict:** file 1 is the closer live match; file 2 is incompatible with the observed table. Keep both unchanged until a separate history decision is documented.
3. **Growth and default ACL changes are not production state:** candidate files have important authorization and future-grant effects. Keep them isolated and do not infer successful deployment from CI.
4. **Maintenance migration track must be unified:** the two timestamped files represent the legacy executor-role design; the current single-pass draft is a distinct replacement architecture. No final timestamped single-pass migration has been approved or created.
5. **Calendar effects are present but provenance is unknown:** do not replay the calendar SQL.
6. **Full schema-only export/rebuild is still missing:** current catalog and generated TypeScript metadata are partial evidence, not a replayable schema dump.

## Recommended next safe sequence

1. Keep all seven historical migration files unchanged.
2. Obtain a complete schema-only export through an approved local CLI/pg_dump path; keep credentials local and do not export production rows or secrets.
3. Build a disposable baseline fixture from that export and compare every application-owned object, grant, policy, trigger, default ACL, function, type, index, and constraint.
4. Decide the App Releases history and the Growth/default-privilege rollout separately from Maintenance.
5. Finalize one Maintenance migration track only after the baseline and release prerequisites are satisfied.
6. Obtain separate explicit approval before any production SQL, migration-history operation, deployment, PR merge, or feature-flag change.

## Verification boundaries

- Repository sources were read from the current Maintenance development branch.
- Production facts above are limited to the read-only catalog observations already recorded in the closeout document.
- No production DDL/DML, data export, migration-history repair, deployment, merge, feature-flag change, dashboard setting change, or paid service was used for this audit.
- CI validation is disposable-environment evidence; it is not a hosted production test or proof of migration provenance.
