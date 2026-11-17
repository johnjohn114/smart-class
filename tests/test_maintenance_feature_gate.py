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


if __name__ == "__main__":
    unittest.main()
