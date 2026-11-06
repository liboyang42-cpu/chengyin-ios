"""Source wiring checks only; not Swift compilation, navigation, or device verification."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class RoamAccountEntryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.browser = (ROOT / "App/RoamBrowserView.swift").read_text()
        cls.root = (ROOT / "App/QuestifyApp.swift").read_text()

    def test_missing_callback_has_no_fallback_and_only_user_button_uses_it(self):
        self.assertIn("var onOpenAccount: (() -> Void)? = nil", self.browser)
        section = self.browser.split("if let onOpenAccount {", 1)[1].split("if let cityDestination", 1)[0]
        self.assertIn('Button("account.title", systemImage: "person.crop.circle", action: onOpenAccount)', section)
        self.assertIn('accessibilityIdentifier("roam.account.open")', section)
        self.assertEqual(self.browser.count("action: onOpenAccount"), 1)
        self.assertNotIn("onOpenAccount()", self.browser)
        self.assertNotIn("AccountView(", section)

    def test_normal_root_selects_existing_current_account_tab(self):
        self.assertIn("onOpenAccount:{ selectedTab = .mine }", self.root)
        self.assertEqual(self.root.count("onOpenAccount:"), 1)
        self.assertIn('}.tabItem { rootTabLabel(.mine) }.tag(RootTab.mine)', self.root)
        self.assertIn("if let account=session.account { AccountView(account:account", self.root)
        self.assertIn("else { WelcomeView() }", self.root)

    def test_local_button_is_in_normal_chrome_outside_map_read_gates(self):
        toolbar = self.browser.index(".toolbar {")
        action = self.browser.index("if let onOpenAccount {")
        self.assertLess(toolbar, action)
        self.assertGreater(toolbar, self.browser.index(".sheet(item: $selected)"))
        for token in ["reader.isConfigured", "reader.identity", "reader.searchArea", "currentFix", "approval", "transport"]:
            self.assertNotIn(token, self.browser.split("if let onOpenAccount {", 1)[1].split("if let cityDestination", 1)[0])

    def test_callback_does_not_change_subject_or_start_a_walk(self):
        action = self.root.split("onOpenAccount:{", 1)[1].split("}", 1)[0].strip()
        self.assertEqual(action, "selectedTab = .mine")
        for token in ["memberID", "profileReader", "makeRoamLive", "start", "request", "token", "grant"]:
            self.assertNotIn(token, action)


if __name__ == "__main__":
    unittest.main()
