-- Smart Class maintenance system
-- SQL DESIGN DRAFT v0.1 — NOT A DEPLOYABLE MIGRATION
-- Target branch: feature/maintenance-system
-- Source: maintenance-database-design-v0.3.md
-- IMPORTANT:
--   1. This file has NOT been executed against Supabase.
--   2. It intentionally does not create RPCs or Edge Functions.
--   3. No direct access is granted to anon/authenticated/service_role.
--   4. Confirm the server-side DB role/connection model before granting access.
--   5. Cross-table invariants and schedule locking must be implemented in
--      a single transaction function before scheduled writes are enabled.

BEGIN;

CREATE SCHEMA IF NOT EXISTS private;

-- Keep the schema outside the Data API and deny ordinary API roles.
REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon, authenticated, service_role;

CREATE TABLE private.maintenance_scopes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  sort_order integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_scopes_code_check CHECK (
    code IN (
      'site_core',
      'announcements_info',
      'events_competitions',
      'video_content',
      'membership_growth',
      'store_support',
      'downloads_app'
    )
  )
);

CREATE TABLE private.maintenance_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  internal_note text,
  is_global boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'draft',
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  version integer NOT NULL DEFAULT 1,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz,
  completed_at timestamptz,
  CONSTRAINT maintenance_events_status_check
    CHECK (status IN ('draft', 'scheduled', 'cancelled', 'completed')),
  CONSTRAINT maintenance_events_time_check CHECK (starts_at < ends_at),
  CONSTRAINT maintenance_events_version_check CHECK (version >= 1)
);

CREATE TABLE private.maintenance_event_scopes (
  event_id uuid NOT NULL
    REFERENCES private.maintenance_events(id) ON DELETE CASCADE,
  scope_id uuid NOT NULL
    REFERENCES private.maintenance_scopes(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, scope_id)
);

CREATE TABLE private.maintenance_audit_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id uuid REFERENCES private.maintenance_events(id) ON DELETE SET NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  before_data jsonb,
  after_data jsonb,
  reason text,
  request_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.maintenance_idempotency (
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  idempotency_key uuid NOT NULL,
  operation text NOT NULL,
  request_hash text NOT NULL,
  response_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (actor_id, idempotency_key),
  CONSTRAINT maintenance_idempotency_expiry_check CHECK (expires_at > created_at)
);

-- Seed only missing scope rows. Existing configured rows are not overwritten.
INSERT INTO private.maintenance_scopes (code, name, sort_order)
VALUES
  ('site_core', '網站核心', 1),
  ('announcements_info', '公告與資訊', 2),
  ('events_competitions', '活動與比賽', 3),
  ('video_content', '影音內容', 4),
  ('membership_growth', '會員與成長', 5),
  ('store_support', '商城與客服', 6),
  ('downloads_app', '下載與 App', 7)
ON CONFLICT (code) DO NOTHING;

CREATE INDEX maintenance_events_status_time_idx
  ON private.maintenance_events (status, starts_at, ends_at);

CREATE INDEX maintenance_event_scopes_scope_event_idx
  ON private.maintenance_event_scopes (scope_id, event_id);

CREATE INDEX maintenance_audit_logs_event_created_idx
  ON private.maintenance_audit_logs (event_id, created_at DESC);

CREATE INDEX maintenance_audit_logs_actor_created_idx
  ON private.maintenance_audit_logs (actor_id, created_at DESC);

CREATE INDEX maintenance_idempotency_expires_idx
  ON private.maintenance_idempotency (expires_at);

-- Defense in depth: all maintenance tables have RLS enabled and no client policies.
ALTER TABLE private.maintenance_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_event_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.maintenance_idempotency ENABLE ROW LEVEL SECURITY;

-- Explicitly remove direct table access. Server-side access is deliberately
-- withheld until the Edge Function database role is designed and verified.
REVOKE ALL ON TABLE
  private.maintenance_scopes,
  private.maintenance_events,
  private.maintenance_event_scopes,
  private.maintenance_audit_logs,
  private.maintenance_idempotency
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA private
FROM PUBLIC, anon, authenticated, service_role;

-- Generic updated_at trigger for editable configuration/event rows.
CREATE OR REPLACE FUNCTION private.maintenance_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.maintenance_set_updated_at()
FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER maintenance_scopes_set_updated_at
BEFORE UPDATE ON private.maintenance_scopes
FOR EACH ROW
EXECUTE FUNCTION private.maintenance_set_updated_at();

CREATE TRIGGER maintenance_events_set_updated_at
BEFORE UPDATE ON private.maintenance_events
FOR EACH ROW
EXECUTE FUNCTION private.maintenance_set_updated_at();

-- Audit log is append-only for ordinary SQL operations.
CREATE OR REPLACE FUNCTION private.maintenance_audit_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'maintenance audit logs are append-only'
    USING ERRCODE = '55000';
END;
$function$;

REVOKE ALL ON FUNCTION private.maintenance_audit_reject_mutation()
FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER maintenance_audit_no_update_delete
BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs
FOR EACH ROW
EXECUTE FUNCTION private.maintenance_audit_reject_mutation();

CREATE TRIGGER maintenance_audit_no_truncate
BEFORE TRUNCATE ON private.maintenance_audit_logs
FOR EACH STATEMENT
EXECUTE FUNCTION private.maintenance_audit_reject_mutation();

COMMIT;

-- NOT YET IMPLEMENTED IN THIS DRAFT:
-- * Enforce is_global <=> no event_scope links, and local event => >= 1 scope.
-- * Central transactional write functions with pg_advisory_xact_lock.
-- * Idempotency claim/replay with canonical request hashing.
-- * Admin authorization boundary and least-privilege server DB role.
-- * Public status read path and safe response projection.
-- * Audit event insertion in the same transaction as every state change.
