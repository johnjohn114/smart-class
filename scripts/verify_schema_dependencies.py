#!/usr/bin/env python3
"""Conservative dependency checks for reconstructed Smart Class SQL snapshots."""
from pathlib import Path
import argparse
import re

try:
    from pglast import parse_sql
except ImportError:
    print("ERROR: pglast is required.")
    raise SystemExit(2)

SQL_FILES = (
    "20261108-public-functions.sql",
    "20261108-public-tables-policies.sql",
    "20261108-public-views.sql",
    "20261108-public-triggers.sql",
    "20261108-public-triggers-sequences.sql",
    "20261108-public-types-sequences.sql",
)


def uncomment(sql):
    sql = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    return re.sub(r"(?m)--[^\r\n]*", " ", sql)


def names(pattern, text):
    return {m.group(1).strip('"') for m in re.finditer(pattern, text, re.I)}


def relation_refs(text):
    pattern = re.compile(
        r"\b(?:FROM|JOIN|UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+"
        r"(?:(?P<schema>[A-Za-z_][\w]*)\.)?"
        r'(?P<name>"?[A-Za-z_][\w]*"?)', re.I
    )
    for match in pattern.finditer(text):
        name = match.group("name").strip('"')
        schema = match.group("schema")
        if text[match.end():].lstrip().startswith("("):
            continue
        yield schema.lower() if schema else None, name


def check(snapshot_dir):
    root = Path(snapshot_dir)
    errors = []
    missing = [name for name in SQL_FILES if not (root / name).is_file()]
    if missing:
        return [f"missing required snapshot file: {name}" for name in missing], {}

    raw = {name: (root / name).read_text(encoding="utf-8") for name in SQL_FILES}
    clean = {name: uncomment(value) for name, value in raw.items()}
    parsed = {}
    for name, sql in raw.items():
        try:
            parsed[name] = len(parse_sql(sql))
        except Exception as exc:
            errors.append(f"SQL parse failed in {name}: {exc}")

    table_sql = clean["20261108-public-tables-policies.sql"]
    view_sql = clean["20261108-public-views.sql"]
    function_sql = clean["20261108-public-functions.sql"]
    trigger_sql = clean["20261108-public-triggers.sql"]

    tables = names(r"(?im)^\s*CREATE\s+TABLE\s+public\.([A-Za-z_][\w]*)", table_sql)
    views = names(r"(?im)^\s*CREATE\s+OR\s+REPLACE\s+VIEW\s+public\.([A-Za-z_][\w]*)", view_sql)
    functions = names(r"(?im)^\s*CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.([A-Za-z_][\w]*)\s*\(", function_sql)
    relations = tables | views

    fk_checked = 0
    fk_re = re.compile(r"\bREFERENCES\s+(?:(?P<schema>[A-Za-z_][\w]*)\.)?(?P<name>[A-Za-z_][\w]*)", re.I)
    for match in fk_re.finditer(table_sql):
        schema, name = match.group("schema"), match.group("name")
        if name.upper() == "ON" or (schema and schema.lower() != "public"):
            continue
        fk_checked += 1
        if name not in relations:
            errors.append(f"foreign-key target not found in public snapshot: {name}")

    view_refs = 0
    for schema, name in relation_refs(view_sql):
        if schema and schema != "public":
            continue
        view_refs += 1
        if name not in relations:
            errors.append(f"view dependency not found in public snapshot: {name}")

    function_blocks = re.finditer(
        r"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.([A-Za-z_][\w]*)"
        r"[\s\S]*?AS\s+\$function\$([\s\S]*?)\$function\$\s*;",
        function_sql, re.I
    )
    function_count = public_function_refs = unqualified_matches = 0
    for block in function_blocks:
        function_count += 1
        owner, body = block.group(1), block.group(2)
        for schema, name in relation_refs(body):
            if schema and schema != "public":
                continue
            if schema == "public":
                public_function_refs += 1
                if name not in relations:
                    errors.append(f"function {owner}: public relation dependency not found: {name}")
            elif name in relations:
                unqualified_matches += 1

    trigger_re = re.compile(
        r"CREATE\s+TRIGGER\s+(?P<trigger>[A-Za-z_][\w]*)"
        r"[\s\S]*?\bON\s+(?:(?P<table_schema>[A-Za-z_][\w]*)\.)?"
        r"(?P<table>[A-Za-z_][\w]*)[\s\S]*?\bEXECUTE\s+FUNCTION\s+"
        r"(?:(?P<fn_schema>[A-Za-z_][\w]*)\.)?(?P<function>[A-Za-z_][\w]*)\s*\(", re.I
    )
    triggers = list(trigger_re.finditer(trigger_sql))
    trigger_tables = trigger_functions = 0
    for match in triggers:
        trigger = match.group("trigger")
        table_schema, table = match.group("table_schema"), match.group("table")
        fn_schema, function = match.group("fn_schema"), match.group("function")
        if not table_schema or table_schema.lower() == "public":
            trigger_tables += 1
            if table not in tables:
                errors.append(f"trigger {trigger}: target table not found: {table}")
        if not fn_schema or fn_schema.lower() == "public":
            trigger_functions += 1
            if function not in functions:
                errors.append(f"trigger {trigger}: trigger function not found: {function}")

    stats = {
        "tables": len(tables), "views": len(views), "functions": len(functions),
        "triggers": len(triggers), "parsed": len(parsed), "fk": fk_checked,
        "view_refs": view_refs, "function_blocks": function_count,
        "public_function_refs": public_function_refs,
        "unqualified_matches": unqualified_matches,
        "trigger_tables": trigger_tables, "trigger_functions": trigger_functions,
    }
    return errors, stats


def main():
    parser = argparse.ArgumentParser(description="Static dependency check for SQL snapshots.")
    parser.add_argument("snapshot_dir", nargs="?", default="docs/schema-snapshots")
    args = parser.parse_args()
    errors, s = check(args.snapshot_dir)
    if s:
        print(f"INVENTORY: {s['tables']} tables, {s['views']} views, {s['functions']} functions, {s['triggers']} triggers")
        print(f"SQL files parsed: {s['parsed']}/{len(SQL_FILES)}")
        print(f"Foreign-key targets checked: {s['fk']}")
        print(f"View relation references checked: {s['view_refs']}")
        print(f"Function definitions scanned: {s['function_blocks']}")
        print(f"Explicit public relation refs in function bodies checked: {s['public_function_refs']}")
        print(f"Unqualified function-body refs matching inventory: {s['unqualified_matches']}")
        print(f"Trigger target-table checks: {s['trigger_tables']}")
        print(f"Trigger-function checks: {s['trigger_functions']}")
    if errors:
        print("\nDEPENDENCY CHECK: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("\nDEPENDENCY CHECK: PASS")
    print("NOTE: Conservative static check only; not a full dependency graph or restore test.")
    print("NOTE: Unknown unqualified names in PL/pgSQL bodies are not declared missing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
