import tempfile, unittest, subprocess, sys
from pathlib import Path
SCRIPT=Path(__file__).resolve().parents[1]/"scripts"/"verify_schema_snapshot.py"
class CheckerTests(unittest.TestCase):
 def fixture(self, root, bad=False):
  (root/"20261108-public-tables-policies.sql").write_text(
   "-- Not pg_dump output\n"+"".join(f"CREATE TABLE public.t{i}(id int);\n" for i in range(44))+
   "".join(f"CREATE POLICY p{i} ON public.t0 FOR SELECT USING(true);\n" for i in range(97 if bad else 98))+
   "".join(f"CREATE INDEX i{i} ON public.t0(id);\n" for i in range(49)))
  (root/"20261108-public-views.sql").write_text("CREATE OR REPLACE VIEW public.v AS SELECT 1;")
  (root/"20261108-public-functions.sql").write_text("".join(f"CREATE OR REPLACE FUNCTION public.f{i}() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;\n" for i in range(38)))
  (root/"20261108-public-triggers.sql").write_text("".join(f"CREATE TRIGGER t{i} BEFORE INSERT ON t EXECUTE FUNCTION f();\n" for i in range(7)))
  (root/"20261108-public-types-sequences.sql").write_text("-- public.demo_seq type=bigint")
 def runcheck(self, root): return subprocess.run([sys.executable,str(SCRIPT),str(root)],capture_output=True,text=True)
 def test_valid_fixture(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); self.fixture(p); r=self.runcheck(p); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
 def test_wrong_count_fails(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); self.fixture(p,True); self.assertEqual(self.runcheck(p).returncode,1)
 def test_missing_files_fail(self):
  with tempfile.TemporaryDirectory() as d: self.assertEqual(self.runcheck(Path(d)).returncode,1)
if __name__=="__main__": unittest.main(verbosity=2)
