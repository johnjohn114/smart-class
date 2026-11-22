#!/usr/bin/env python3
"""Prove the maintenance SQL draft rolls back all objects after a late injected failure."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql"
INJECTION_POINT = "GRANT CREATE ON SCHEMA public TO maintenance_rpc_executor;"
FAILURE = "INJECTED_MAINTENANCE_ROLLBACK_TEST"


def psql(database_url: str, sql: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", database_url],
        input=sql,
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> int:
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        print("FAIL: DATABASE_URL is required", file=sys.stderr)
        return 2
    draft = SQL_PATH.read_text(encoding="utf-8")
    if draft.count(INJECTION_POINT) != 1:
        print("FAIL: rollback injection point must occur exactly once", file=sys.stderr)
        return 2

    injected = draft.replace(
        INJECTION_POINT,
        f"DO $rollback_probe$ BEGIN RAISE EXCEPTION '{FAILURE}'; END $rollback_probe$;\n"
        + INJECTION_POINT,
        1,
    )
    result = psql(database_url, injected)
    output = result.stdout + result.stderr
    if result.returncode == 0 or FAILURE not in output:
        print("FAIL: injected migration failure did not abort as expected", file=sys.stderr)
        print(output, file=sys.stderr)
        return 1

    verification = """
SELECT (
  NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='maintenance_rpc_executor')
  AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='private')
  AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE pronamespace='public'::pg_catalog.regnamespace
      AND proname IN ('maintenance_status_public','maintenance_admin_list',
                      'maintenance_event_create','maintenance_event_update',
                      'maintenance_event_action')
  )
)::text;
"""
    check = subprocess.run(
        ["psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", database_url, "-c", verification],
        text=True,
        capture_output=True,
        check=False,
    )
    if check.returncode != 0 or check.stdout.strip() not in ("t", "true"):
        print("FAIL: partial migration objects remain after rollback", file=sys.stderr)
        print(check.stdout + check.stderr, file=sys.stderr)
        return 1

    print("PASS: injected late failure rolled back executor role, private schema and public RPCs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
