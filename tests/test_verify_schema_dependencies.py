import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from verify_schema_dependencies import check


class DependencyCheckerTests(unittest.TestCase):
    def fixture(self, root, *, missing_trigger_function=False, missing_view_table=False,
                missing_function_table=False, missing_fk_table=False):
        (root / "20261108-public-tables-policies.sql").write_text(
            "CREATE TABLE public.alpha (id integer PRIMARY KEY);\n"
            + ("CREATE TABLE public.beta (alpha_id integer REFERENCES public.ghost(id));\n"
               if missing_fk_table else
               "CREATE TABLE public.beta (alpha_id integer REFERENCES public.alpha(id));\n"),
            encoding="utf-8",
        )
        view_source = "public.ghost" if missing_view_table else "public.alpha"
        (root / "20261108-public-views.sql").write_text(
            f"CREATE OR REPLACE VIEW public.v AS SELECT id FROM {view_source};\n",
            encoding="utf-8",
        )
        function_source = "public.ghost" if missing_function_table else "public.alpha"
        (root / "20261108-public-functions.sql").write_text(
            "CREATE OR REPLACE FUNCTION public.fn() RETURNS trigger "
            "LANGUAGE plpgsql AS $function$ BEGIN "
            f"PERFORM id FROM {function_source}; "
            "RETURN NEW; END $function$;\n",
            encoding="utf-8",
        )
        trigger_function = "public.missing_fn" if missing_trigger_function else "public.fn"
        (root / "20261108-public-triggers.sql").write_text(
            "CREATE TRIGGER trg BEFORE INSERT ON public.alpha "
            f"FOR EACH ROW EXECUTE FUNCTION {trigger_function}();\n",
            encoding="utf-8",
        )
        (root / "20261108-public-triggers-sequences.sql").write_text("-- inventory only\n", encoding="utf-8")
        (root / "20261108-public-types-sequences.sql").write_text("-- inventory only\n", encoding="utf-8")

    def run_fixture(self, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, **kwargs)
            return check(root)[0]

    def test_valid_dependencies_pass(self):
        self.assertEqual(self.run_fixture(), [])

    def test_missing_trigger_function_fails(self):
        self.assertTrue(any("trigger function not found" in x for x in self.run_fixture(missing_trigger_function=True)))

    def test_missing_view_relation_fails(self):
        self.assertTrue(any("view dependency not found" in x for x in self.run_fixture(missing_view_table=True)))

    def test_missing_public_function_relation_fails(self):
        self.assertTrue(any("public relation dependency not found" in x for x in self.run_fixture(missing_function_table=True)))

    def test_missing_foreign_key_target_fails(self):
        self.assertTrue(any("foreign-key target not found" in x for x in self.run_fixture(missing_fk_table=True)))


if __name__ == "__main__":
    unittest.main()
