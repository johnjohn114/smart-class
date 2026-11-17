#!/usr/bin/env python3
"""Static inventory check only; this does not parse or execute SQL."""
from pathlib import Path
import argparse, re, sys

EXPECTED = {
 "20261108-public-tables-policies.sql": [
  ("tables", r"(?im)^CREATE TABLE public\.", 44),
  ("policies", r"(?im)^CREATE POLICY ", 98),
  ("indexes", r"(?im)^CREATE (?:UNIQUE )?INDEX ", 49),
 ],
 "20261108-public-views.sql": [("views", r"(?im)^CREATE OR REPLACE VIEW public\.", 1)],
 "20261108-public-functions.sql": [("functions", r"(?im)^CREATE OR REPLACE FUNCTION public\.", 38)],
 "20261108-public-triggers.sql": [("triggers", r"(?im)^CREATE TRIGGER ", 7)],
 "20261108-public-types-sequences.sql": [("sequence inventory", r"(?im)^-- public\.[^\s]+_seq\b", 2)],
}

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument("snapshot_dir", nargs="?", default="docs/schema-snapshots")
 root=Path(p.parse_args().snapshot_dir)
 errors=[]
 for filename, checks in EXPECTED.items():
  path=root/filename
  if not path.is_file():
   errors.append(f"MISSING {filename}"); continue
  data=path.read_text(encoding="utf-8")
  print(f"[{filename}]")
  for label,pattern,want in checks:
   got=len(re.findall(pattern,data))
   print(f"  {'PASS' if got==want else 'FAIL'} {label}: {got}/{want}")
   if got!=want: errors.append(f"{filename}: {label} {got} != {want}")
 table=root/"20261108-public-tables-policies.sql"
 if table.is_file() and "not pg_dump output" not in table.read_text(encoding="utf-8").lower():
  errors.append("missing provenance warning")
 print("STATIC INVENTORY CHECK: "+("PASS" if not errors else "FAIL"))
 print("Counts only; this is not SQL syntax, permission, dependency or restore validation.")
 for e in errors: print("ERROR:",e,file=sys.stderr)
 return 1 if errors else 0
if __name__=="__main__": raise SystemExit(main())
