import unittest

from scripts.verify_maintenance_sql_draft import inspect_sql


TABLES = (
    "maintenance_scopes", "maintenance_events", "maintenance_event_private_notes",
    "maintenance_event_scopes", "maintenance_audit_logs", "maintenance_idempotency",
)


def rpc(name, body):
    return (
        f"CREATE FUNCTION public.{name}(p_request jsonb) RETURNS jsonb "
        "LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' "
        f"AS $$ BEGIN {body} RETURN '{{}}'::jsonb; END; $$;"
    )


CREATE_BODY = """
jsonb_typeof(p_request->'title') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'message') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'internal_note') NOT IN ('string','null');
jsonb_typeof(p_request->'starts_at') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'ends_at') IS DISTINCT FROM 'string';
starts_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';
ends_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';
"""

UPDATE_BODY = """
jsonb_typeof(p_request->'title') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'message') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'internal_note') NOT IN ('string','null');
jsonb_typeof(p_request->'starts_at') IS DISTINCT FROM 'string';
jsonb_typeof(p_request->'ends_at') IS DISTINCT FROM 'string';
starts_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';
ends_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';
"""

GOOD = (
    "\n".join(f"CREATE TABLE private.{name} (id uuid);" for name in TABLES)
    + "\n".join(
        f"ALTER TABLE private.{name} ENABLE ROW LEVEL SECURITY;"
        for name in TABLES
    )
    + rpc("maintenance_status_public", "NULL;")
    + rpc("maintenance_admin_list", """
        jsonb_typeof(p_request->'status') IS DISTINCT FROM 'string';
        jsonb_typeof(p_request->'limit') IS DISTINCT FROM 'number';
        pg_catalog.strpos(v_cursor_text,'|');
        v_limit integer := 20;
    """)
    + rpc("maintenance_event_create", CREATE_BODY)
    + rpc("maintenance_event_update", UPDATE_BODY)
    + rpc("maintenance_event_action",
          "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string';")
    + """
CREATE POLICY maintenance_event_private_notes_admin_select ON private.maintenance_event_private_notes FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY maintenance_event_private_notes_admin_insert ON private.maintenance_event_private_notes FOR INSERT TO authenticated WITH CHECK (public.is_admin());
CREATE POLICY maintenance_event_private_notes_admin_update ON private.maintenance_event_private_notes FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE TRIGGER audit_no_mutation BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs
FOR EACH ROW EXECUTE FUNCTION private.block_audit();
CREATE TRIGGER audit_no_truncate BEFORE TRUNCATE ON private.maintenance_audit_logs
FOR EACH STATEMENT EXECUTE FUNCTION private.block_audit();
PRIMARY KEY(actor_id, idempotency_key);
SELECT pg_advisory_xact_lock(20261108,1);
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
"""
)


class MaintenanceSqlDraftStaticTests(unittest.TestCase):
    def test_complete_draft_passes_guardrails(self):
        result = inspect_sql(GOOD)
        self.assertTrue(all(result.values()), result)

    def test_internal_note_is_not_stored_on_public_event_row(self):
        result = inspect_sql(GOOD.replace(
            "CREATE TABLE private.maintenance_events (id uuid);",
            "CREATE TABLE private.maintenance_events (id uuid, internal_note text);"
        ))
        self.assertFalse(result["notes_not_in_events_table"])

    def test_missing_notes_admin_policy_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "CREATE POLICY maintenance_event_private_notes_admin_select ON private.maintenance_event_private_notes FOR SELECT TO authenticated USING (public.is_admin());",
            ""
        ))
        self.assertFalse(result["notes_admin_only_rls"])

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

    def test_missing_create_text_type_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "jsonb_typeof(p_request->'title') IS DISTINCT FROM 'string';", "", 1
        ))
        self.assertFalse(result["create_rpc_text_type_validation"])

    def test_missing_update_note_type_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "jsonb_typeof(p_request->'internal_note') NOT IN ('string','null');",
            "", 1
        ))
        self.assertFalse(result["update_rpc_text_type_validation"])

    def test_missing_action_reason_type_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string';",
            "", 1
        ))
        self.assertFalse(result["action_rpc_reason_type_validation"])

    def test_missing_create_timezone_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "starts_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';", "", 1
        ))
        self.assertFalse(result["create_rpc_timezone_validation"])

    def test_missing_update_timezone_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "ends_at !~ '^[0-9]{4}-([Zz]|[+-][0-9]{2}:[0-9]{2})$';", "", 2
        ))
        self.assertFalse(result["update_rpc_timezone_validation"])

    def test_missing_private_privilege_reset_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;",
            ""
        ))
        self.assertFalse(result["private_object_privileges_reset"])

    def test_duplicate_public_rpc_is_detected(self):
        duplicate = GOOD + "\nCREATE FUNCTION public.maintenance_event_create(p_request jsonb) RETURNS jsonb;"
        result = inspect_sql(duplicate)
        self.assertFalse(result["public_rpc_definitions_unique"])


if __name__ == "__main__":
    unittest.main()
