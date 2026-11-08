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
    "maintenance_scopes",
    "maintenance_events",
    "maintenance_event_scopes",
    "maintenance_audit_logs",
    "maintenance_idempotency",
)
RPCS = (
    "maintenance_status_public",
    "maintenance_admin_list",
    "maintenance_event_create",
    "maintenance_event_update",
    "maintenance_event_action",
)


def inspect_sql(sql: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    for table in TABLES:
        checks[f"table:{table}"] = bool(
            re.search(rf"CREATE\s+TABLE\s+private\.{table}\b", sql, re.I)
        )
        checks[f"rls:{table}"] = bool(
            re.search(rf"ALTER\s+TABLE\s+private\.{table}\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY", sql, re.I)
        )
    for rpc in RPCS:
        pattern = rf"CREATE\s+FUNCTION\s+public\.{rpc}\s*\(p_request\s+jsonb\)(.*?)(?:\n\$\$;)"
        match = re.search(pattern, sql, re.I | re.S)
        checks[f"rpc:{rpc}"] = bool(match)
        checks[f"invoker:{rpc}"] = bool(
            match and re.search(r"SECURITY\s+INVOKER", match.group(1), re.I)
            and re.search(r"SET\s+search_path\s*=\s*''", match.group(1), re.I)
        )
    checks["no_service_role_grants"] = not bool(
        re.search(r"GRANT\b[^;]*\bTO\s+[^;]*service_role", sql, re.I | re.S)
    )
    checks["no_security_definer"] = not bool(re.search(r"SECURITY\s+DEFINER", sql, re.I))
    checks["audit_update_delete_guard"] = "BEFORE UPDATE OR DELETE ON private.maintenance_audit_logs" in sql
    checks["audit_truncate_guard"] = "BEFORE TRUNCATE ON private.maintenance_audit_logs" in sql
    checks["idempotency_unique_actor_key"] = "PRIMARY KEY(actor_id, idempotency_key)" in sql
    checks["transaction_lock_present"] = "pg_advisory_xact_lock(20261108,1)" in sql
    checks["no_events_delete_grant"] = not bool(
        re.search(r"GRANT\s+[^;]*DELETE[^;]*ON\s+private\.maintenance_events", sql, re.I)
    )
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
