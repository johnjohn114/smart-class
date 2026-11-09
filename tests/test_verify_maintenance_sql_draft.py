import unittest

from scripts.verify_maintenance_sql_draft import inspect_sql


GOOD = """
CREATE TABLE private.maintenance_scopes (code text);
CREATE TABLE private.maintenance_events (id uuid);
CREATE TABLE private.maintenance_event_scopes (event_id uuid);
CREATE TABLE private.maintenance_audit_logs (id uuid);
CREATE TABLE private.maintenance_idempotency (actor_id uuid);
""" + "\n".join(
    f"ALTER TABLE private.{name} ENABLE ROW LEVEL SECURITY;"
    for name in (
        "maintenance_scopes", "maintenance_events", "maintenance_event_scopes",
        "maintenance_audit_logs", "maintenance_idempotency",
    )
) + "\n".join(
    f"CREATE FUNCTION public.{name}(p_request jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$ BEGIN RETURN '{{}}'::jsonb; END; $$;"
    for name in (
        "maintenance_status_public", "maintenance_admin_list",
        "maintenance_event_create", "maintenance_event_update",
        "maintenance_event_action",
    )
) + """
CREATE TRIGGER audit_no_mutation BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs
FOR EACH ROW EXECUTE FUNCTION private.block_audit();
CREATE TRIGGER audit_no_truncate BEFORE TRUNCATE ON private.maintenance_audit_logs
FOR EACH STATEMENT EXECUTE FUNCTION private.block_audit();
PRIMARY KEY(actor_id, idempotency_key);
SELECT pg_advisory_xact_lock(20261108,1);
-- Hardened admin-list validation markers used by static guardrail fixtures.
v_limit integer := 20;
IF p_request ? 'limit' THEN
  IF pg_catalog.jsonb_typeof(p_request->'limit') IS DISTINCT FROM 'number' THEN NULL; END IF;
END IF;
IF pg_catalog.jsonb_typeof(p_request->'status') IS DISTINCT FROM 'string' THEN NULL; END IF;
IF pg_catalog.strpos(v_cursor_text,'|') < 1 THEN NULL; END IF;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
"""


class MaintenanceSqlDraftStaticTests(unittest.TestCase):
    def test_complete_draft_passes_guardrails(self):
        result = inspect_sql(GOOD)
        self.assertTrue(all(result.values()), result)

    def test_missing_rls_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "ALTER TABLE private.maintenance_events ENABLE ROW LEVEL SECURITY;", ""
        ))
        self.assertFalse(result["rls:maintenance_events"])

    def test_security_definer_is_rejected(self):
        result = inspect_sql(GOOD + "\n-- SECURITY DEFINER")
        self.assertFalse(result["no_security_definer"])

    def test_service_role_grant_is_rejected(self):
        result = inspect_sql(GOOD + "\nGRANT SELECT ON private.maintenance_events TO service_role;")
        self.assertFalse(result["no_service_role_grants"])

    def test_events_delete_grant_is_rejected(self):
        result = inspect_sql(GOOD + "\nGRANT SELECT, DELETE ON private.maintenance_events TO authenticated;")
        self.assertFalse(result["no_events_delete_grant"])

    def test_unclosed_dollar_quote_is_detected(self):
        broken = GOOD.replace(" END; $$;", " END;\n$;", 1)
        result = inspect_sql(broken)
        self.assertFalse(result["dollar_quote_balance"])
        self.assertFalse(result["no_bare_dollar_closer"])

    def test_duplicate_public_rpc_is_detected(self):
        duplicate = GOOD + "\nCREATE FUNCTION public.maintenance_event_create(p_request jsonb) RETURNS jsonb;"
        result = inspect_sql(duplicate)
        self.assertFalse(result["public_rpc_definitions_unique"])


if __name__ == "__main__":
    unittest.main()
