#!/usr/bin/env python3
"""Static guardrails for the unexecuted maintenance SQL draft.

This is not a PostgreSQL parser and does not prove JWT/RLS behavior.
Run from the repository root:
    python scripts/verify_maintenance_sql_draft.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SQL_PATH = Path("supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql")
TABLES = (
    "maintenance_scopes", "maintenance_events", "maintenance_event_private_notes",
    "maintenance_event_scopes", "maintenance_audit_logs", "maintenance_idempotency",
)
RPCS = (
    "maintenance_status_public", "maintenance_admin_list", "maintenance_event_create",
    "maintenance_event_update", "maintenance_event_action",
)


def _rpc_body(sql: str, rpc: str) -> str:
    pattern = rf"CREATE\s+FUNCTION\s+public\.{rpc}\s*\(p_request\s+jsonb\)(.*?)(?:\n\s*)?\$\$;"
    match = re.search(pattern, sql, re.I | re.S)
    return match.group(1) if match else ""


def inspect_sql(sql: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    bodies = {rpc: _rpc_body(sql, rpc) for rpc in RPCS}
    for table in TABLES:
        checks[f"table:{table}"] = bool(
            re.search(rf"CREATE\s+TABLE\s+private\.{table}\b", sql, re.I)
        )
        checks[f"rls:{table}"] = bool(
            re.search(rf"ALTER\s+TABLE\s+private\.{table}\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY", sql, re.I)
        )
    for rpc, body in bodies.items():
        checks[f"rpc:{rpc}"] = bool(body)
        checks[f"invoker:{rpc}"] = bool(
            body and re.search(r"SECURITY\s+INVOKER", body, re.I)
            and re.search(r"SET\s+search_path\s*=\s*''", body, re.I)
        )

    create_body = bodies["maintenance_event_create"]
    update_body = bodies["maintenance_event_update"]
    action_body = bodies["maintenance_event_action"]
    checks["create_rpc_text_type_validation"] = all(
        marker in create_body for marker in (
            "jsonb_typeof(p_request->'title') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'message') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'internal_note') NOT IN ('string','null')",
        )
    )
    checks["update_rpc_text_type_validation"] = all(
        marker in update_body for marker in (
            "jsonb_typeof(p_request->'title') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'message') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string'",
            "jsonb_typeof(p_request->'internal_note') NOT IN ('string','null')",
        )
    )
    checks["action_rpc_reason_type_validation"] = (
        "jsonb_typeof(p_request->'reason') IS DISTINCT FROM 'string'" in action_body
    )
    timezone_marker = "([Zz]|[+-][0-9]{2}:[0-9]{2})$"
    checks["create_rpc_timezone_validation"] = (
        "jsonb_typeof(p_request->'starts_at') IS DISTINCT FROM 'string'" in create_body
        and "jsonb_typeof(p_request->'ends_at') IS DISTINCT FROM 'string'" in create_body
        and create_body.count(timezone_marker) >= 2
    )
    checks["update_rpc_timezone_validation"] = (
        "jsonb_typeof(p_request->'starts_at') IS DISTINCT FROM 'string'" in update_body
        and "jsonb_typeof(p_request->'ends_at') IS DISTINCT FROM 'string'" in update_body
        and update_body.count(timezone_marker) >= 2
    )
    checks["private_object_privileges_reset"] = all(
        marker in sql for marker in (
            "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;",
            "REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;",
            "REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;",
        )
    )

    checks["no_service_role_grants"] = not bool(
        re.search(r"GRANT\b[^;]*\bTO\s+[^;]*service_role", sql, re.I | re.S)
    )
    checks["no_security_definer"] = not bool(re.search(r"SECURITY\s+DEFINER", sql, re.I))
    checks["audit_update_delete_guard"] = "BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs" in sql
    checks["audit_truncate_guard"] = "BEFORE TRUNCATE ON private.maintenance_audit_logs" in sql
    checks["idempotency_unique_actor_key"] = "PRIMARY KEY(actor_id, idempotency_key)" in sql
    checks["transaction_lock_present"] = "pg_advisory_xact_lock(20261108,1)" in sql
    checks["notes_admin_only_rls"] = (
        "CREATE POLICY maintenance_event_private_notes_admin_select" in sql
        and "CREATE POLICY maintenance_event_private_notes_admin_insert" in sql
        and "CREATE POLICY maintenance_event_private_notes_admin_update" in sql
        and "ALTER TABLE private.maintenance_event_private_notes ENABLE ROW LEVEL SECURITY" in sql
    )
    checks["notes_not_in_events_table"] = not bool(
        re.search(r"CREATE\s+TABLE\s+private\.maintenance_events\s*\([^;]*\binternal_note\b", sql, re.I | re.S)
    )
    checks["no_events_delete_grant"] = not bool(
        re.search(r"GRANT\s+[^;]*DELETE[^;]*ON\s+private\.maintenance_events", sql, re.I)
    )
    checks["safe_limit_default"] = "v_limit integer := 20;" in bodies["maintenance_admin_list"]
    checks["admin_list_type_validation"] = (
        "jsonb_typeof(p_request->'status') IS DISTINCT FROM 'string'" in bodies["maintenance_admin_list"]
        and "jsonb_typeof(p_request->'limit') IS DISTINCT FROM 'number'" in bodies["maintenance_admin_list"]
    )
    checks["cursor_shape_validation"] = "pg_catalog.strpos(v_cursor_text,'|')" in bodies["maintenance_admin_list"]
    checks["rpc_cast_errors_normalized"] = (
        len(re.findall(r"WHEN invalid_text_representation OR invalid_datetime_format", sql, re.I)) >= 4
    )
    checks["public_rpc_definitions_unique"] = all(
        len(re.findall(rf"CREATE\s+FUNCTION\s+public\.{rpc}\s*\(", sql, re.I)) == 1
        for rpc in RPCS
    )
    checks["dollar_quote_balance"] = (
        len(re.findall(r"\bAS\s+\$\$", sql, re.I))
        == len(re.findall(r"\$\$;", sql))
    )
    checks["no_bare_dollar_closer"] = not bool(re.search(r"^\s*\$;\s*$", sql, re.M))
    return checks


def main() -> int:
    if not SQL_PATH.is_file():
        print(f"FAIL: SQL draft not found: {SQL_PATH}", file=sys.stderr)
        return 2
    checks = inspect_sql(SQL_PATH.read_text(encoding="utf-8"))
    failed = [name for name, ok in checks.items() if not ok]
    print(json.dumps({
        "sql_file": str(SQL_PATH),
        "check_count": len(checks),
        "passed": len(checks) - len(failed),
        "failed": failed,
        "scope": "static text guardrails only; not SQL parsing or database integration",
    }, ensure_ascii=False, indent=2))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
