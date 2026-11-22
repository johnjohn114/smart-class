import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NotificationMarkupParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.select_options = {}
        self._select_id = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        element_id = attrs.get("id")
        if element_id:
            self.ids.add(element_id)
        if tag == "select":
            self._select_id = element_id
            self.select_options[self._select_id] = set()
        elif tag == "option" and self._select_id:
            self.select_options[self._select_id].add(attrs.get("value"))

    def handle_endtag(self, tag):
        if tag == "select":
            self._select_id = None


class NotificationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (ROOT / "my.html").read_text(encoding="utf-8")
        cls.js = (ROOT / "app.js").read_text(encoding="utf-8")
        parser = NotificationMarkupParser()
        parser.feed(cls.html)
        cls.ids = parser.ids
        cls.options = parser.select_options

    def test_notification_panel_has_required_elements_and_filters(self):
        required = {
            "myNotificationsPanel", "myNotifications", "notificationSummary",
            "notificationFilter", "notificationMsg", "markAllNotifications",
            "deleteReadNotifications",
        }
        self.assertTrue(required.issubset(self.ids), required - self.ids)
        self.assertEqual(
            self.options.get("notificationFilter"),
            {"all", "unread", "read"},
        )

    def test_load_is_member_scoped_and_handles_invalid_responses(self):
        start = self.js.index("async function loadMyNotifications")
        end = self.js.index("async function markNotificationRead", start)
        fn = self.js[start:end]
        self.assertIn("getCurrentUser()", fn)
        self.assertIn("user_id=eq.'+encodeURIComponent(user.id)", fn)
        self.assertIn("if(!r.ok)", fn)
        self.assertIn("Array.isArray(rows)", fn)
        self.assertIn("retryMyNotifications", fn)
        self.assertIn("loadMyNotifications", fn)

    def test_filter_renders_all_unread_and_read_rows(self):
        start = self.js.index("function renderMyNotifications")
        end = self.js.index("async function loadMyNotifications", start)
        fn = self.js[start:end]
        self.assertIn("filter==='unread'", fn)
        self.assertIn("filter==='read'", fn)
        self.assertIn(":myNotificationRows;", fn)
        self.assertIn("read_at", fn)

    def test_read_mutations_are_scoped_to_verified_member(self):
        start = self.js.index("async function markNotificationRead")
        end = self.js.index("async function markAllNotificationsRead", start)
        fn = self.js[start:end]
        self.assertIn("const user=await getCurrentUser()", fn)
        self.assertIn("if(!user?.id)", fn)
        self.assertIn("id=eq.'+encodeURIComponent(id)", fn)
        self.assertIn("user_id=eq.'+encodeURIComponent(user.id)", fn)
        self.assertIn("method:'PATCH'", fn)

    def test_bulk_read_and_delete_only_affect_current_members_matching_rows(self):
        start = self.js.index("async function markAllNotificationsRead")
        end = self.js.index("function searchTextScore", start)
        fn = self.js[start:end]
        self.assertIn("async function markAllNotificationsRead", fn)
        self.assertIn("read_at=is.null", fn)
        self.assertIn("async function deleteReadNotifications", fn)
        self.assertIn("read_at=not.is.null", fn)
        self.assertGreaterEqual(fn.count("user_id=eq.'+encodeURIComponent(user.id)"), 2)
        self.assertIn("if(!user?.id)", fn)
        self.assertIn("confirm(", fn)

    def test_notification_controls_are_wired(self):
        self.assertIn("addEventListener('click',markAllNotificationsRead)", self.js)
        self.assertIn("addEventListener('click',deleteReadNotifications)", self.js)
        self.assertIn("addEventListener('change',renderMyNotifications)", self.js)


if __name__ == "__main__":
    unittest.main()
