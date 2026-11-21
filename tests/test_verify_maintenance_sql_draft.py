import unittest

from scripts.verify_maintenance_sql_draft import inspect_sql


TABLES = (
    "maintenance_scopes", "maintenance_events", "maintenance_event_private_notes",
    "maintenance_event_scopes", "maintenance_audit_logs", "maintenance_idempotency",
)


def rpc(name, body):
    security = "INVOKER" if name == "maintenance_status_public" else "DEFINER"
    return (
        f"CREATE FUNCTION public.{name}(p_request jsonb) RETURNS jsonb "
        f"LANGUAGE plpgsql SECURITY {security} SET search_path = '' "
        f"AS $ BEGIN {body} RETURN '{{}}'::jsonb; END; $;"
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
'site_core'=ANY(v_codes); es.scope_code='site_core' OR es.scope_code=ANY(v_codes);
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
'site_core'=ANY(v_codes); es.scope_code='site_core' OR es.scope_code=ANY(v_codes);
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
          "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string'; 'site_core'=ANY(v_codes); es.scope_code='site_core' OR es.scope_code=ANY(v_codes);")
    + """
GRANT SELECT ON private.maintenance_event_private_notes TO authenticated;
GRANT INSERT (event_id,internal_note)
  ON private.maintenance_event_private_notes TO authenticated;
GRANT UPDATE (internal_note,updated_at)
  ON private.maintenance_event_private_notes TO authenticated;
CREATE POLICY maintenance_event_private_notes_admin_select ON private.maintenance_event_private_notes FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY maintenance_event_private_notes_admin_insert ON private.maintenance_event_private_notes FOR INSERT TO authenticated WITH CHECK (public.is_admin());
CREATE POLICY maintenance_event_private_notes_admin_update ON private.maintenance_event_private_notes FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE TRIGGER audit_no_mutation BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs
FOR EACH ROW EXECUTE FUNCTION private.block_audit();
CREATE TRIGGER audit_no_truncate BEFORE TRUNCATE ON private.maintenance_audit_logs
FOR EACH STATEMENT EXECUTE FUNCTION private.block_audit();
PRIMARY KEY(actor_id, idempotency_key);
request_hash bytea NOT NULL CHECK (pg_catalog.octet_length(request_hash) = 32);
pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
v_old_request_hash IS DISTINCT FROM v_request_hash; IDEMPOTENCY_KEY_REUSED
v_old_request_hash IS DISTINCT FROM v_request_hash; IDEMPOTENCY_KEY_REUSED
v_old_request_hash IS DISTINCT FROM v_request_hash; IDEMPOTENCY_KEY_REUSED
SELECT pg_advisory_xact_lock(20261108,1);
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN NULL;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT SELECT (id,title,message,is_global,status,starts_at,ends_at) ON private.maintenance_events TO anon;
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

    def test_creator_id_must_not_be_exposed_on_events(self):
        result = inspect_sql(GOOD)
        self.assertTrue(result["creator_id_not_exposed_on_events"])

        broken = GOOD.replace(
            "CREATE TABLE private.maintenance_events (id uuid);",
            "CREATE TABLE private.maintenance_events (id uuid, created_by uuid);"
        )
        result = inspect_sql(broken)
        self.assertFalse(result["creator_id_not_exposed_on_events"])

    def test_private_notes_grants_are_column_scoped(self):
        result = inspect_sql(GOOD)
        self.assertTrue(result["notes_column_scoped_insert"])
        self.assertTrue(result["notes_column_scoped_update"])

        broad = GOOD + "\\nGRANT SELECT, INSERT, UPDATE ON private.maintenance_event_private_notes TO authenticated;"
        result = inspect_sql(broad)
        self.assertFalse(result["notes_column_scoped_update"])

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
        broken = GOOD.replace(" END; $$;", " END;\n$;\n", 1)
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
            "", 2
        ))
        self.assertFalse(result["update_rpc_text_type_validation"])

    def test_missing_action_reason_type_check_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string';",
            "", 3
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

    def test_site_core_must_conflict_with_every_local_scope(self):
        result = inspect_sql(GOOD)
        self.assertTrue(result["site_core_conflicts_with_all_scopes"])

        broken = GOOD.replace("'site_core'=ANY(v_codes)", "false")
        result = inspect_sql(broken)
        self.assertFalse(result["site_core_conflicts_with_all_scopes"])

    def test_missing_private_privilege_reset_is_detected(self):
        result = inspect_sql(GOOD.replace(
            "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;",
            ""
        ))
        self.assertFalse(result["private_object_privileges_reset"])

    def test_server_side_idempotency_hash_is_required(self):
        result = inspect_sql(GOOD)
        self.assertTrue(result["idempotency_server_sha256"])
        self.assertTrue(result["idempotency_replay_hash_comparison"])

        broken = GOOD.replace(
            "pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));", "", 1
        )
        result = inspect_sql(broken)
        self.assertFalse(result["idempotency_server_sha256"])

        broken = GOOD.replace(
            "v_old_request_hash IS DISTINCT FROM v_request_hash;", "true", 1
        )
        result = inspect_sql(broken)
        self.assertFalse(result["idempotency_replay_hash_comparison"])

    def test_duplicate_public_rpc_is_detected(self):
        duplicate = GOOD + "\nCREATE FUNCTION public.maintenance_event_create(p_request jsonb) RETURNS jsonb;"
        result = inspect_sql(duplicate)
        self.assertFalse(result["public_rpc_definitions_unique"])


if __name__ == "__main__":
    unittest.main()
