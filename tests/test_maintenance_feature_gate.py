from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MaintenanceFeatureGateTests(unittest.TestCase):
    def test_public_client_is_disabled_until_explicit_enable(self):
        config = (ROOT / "config.js").read_text(encoding="utf-8")
        client = (ROOT / "maintenance-client.js").read_text(encoding="utf-8")
        self.assertIn("const MAINTENANCE_FEATURE_ENABLED = false;", config)
        guard = "if (typeof MAINTENANCE_FEATURE_ENABLED === 'undefined' || MAINTENANCE_FEATURE_ENABLED !== true) return;"
        self.assertIn(guard, client)
        self.assertLess(client.index(guard), client.index("async function fetchStatus"))

    def test_admin_maintenance_tab_is_hidden_by_default(self):
        html = (ROOT / "admin.html").read_text(encoding="utf-8")
        script = (ROOT / "admin.js").read_text(encoding="utf-8")
        self.assertIn('data-tab="maintenanceTab" hidden', html)
        self.assertIn("if (maintenanceEnabled) maintenanceTabButton?.removeAttribute('hidden');", script)
        self.assertIn("if (!maintenanceEnabled) return;", script)

    def test_existing_page_script_order_is_preserved(self):
        index = (ROOT / "index.html").read_text(encoding="utf-8")
        admin = (ROOT / "admin.html").read_text(encoding="utf-8")
        self.assertLess(index.index('<script src="config.js"></script>'), index.index('<script src="app.js'))
        self.assertLess(admin.index('<script src="config.js"></script>'), admin.index('<script src="admin.js'))
        self.assertIn("const MAINTENANCE_FEATURE_ENABLED = false;", (ROOT / "config.js").read_text(encoding="utf-8"))

    def test_public_app_bundle_is_not_replaced_by_maintenance_client(self):
        index = (ROOT / "index.html").read_text(encoding="utf-8")
        self.assertIn('<script src="app.js', index)
        self.assertNotIn('<script src="maintenance-client.js', index)


if __name__ == "__main__":
    unittest.main()
