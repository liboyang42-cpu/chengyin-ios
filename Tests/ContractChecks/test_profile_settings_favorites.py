"""Source contracts only; these do not compile or execute Swift."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ProfileSettingsFavoritesContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.route = (ROOT / 'App/ProfileSettingsFavoritesRoute.swift').read_text()
        cls.settings = (ROOT / 'App/SettingsView.swift').read_text()
    def test_normal_settings_entry_and_stack_lifetime(self):
        for value in ['ProfileSettingsFavoritesEntry', 'ProfileSettingsFavoritesNavigation', 'ProfileSettingsFavoritesLifecycle']:
            self.assertIn(value, self.settings)
        self.assertIn('.onDisappear { owner.retire() }', self.route)
    def test_captured_context_and_exact_route(self):
        for value in ['ObjectIdentifier(reader)', 'scope: reader.scope', 'configured: reader.isConfigured', 'viewerRevision', 'identity.accountID == accountID', 'route?.id == offered.id', 'current?.key == offered.access.key']:
            self.assertIn(value, self.route)
    def test_existing_readers_and_accepted_rows_only(self):
        for value in ['reader.selectPost(post, renderedScope:', 'reader.selectTopic(topicID, renderedScope:', 'session.makeProfileFavoriteDetailReader(selected)', 'session.makeProfileFavoriteTopicReader(selected)']:
            self.assertIn(value, self.route)
        self.assertNotIn('URLSession', self.route)
    def test_repeated_tap_and_stale_close_guards(self):
        self.assertIn('foreground, route == nil', self.route)
        self.assertIn('guard route?.id == id else { return false }', self.route)
        self.assertIn('posts.selection == nil, topics.selection == nil', self.route)
    def test_background_and_permanent_retirement(self):
        self.assertIn('foreground = value && mounted && !retired', self.route)
        self.assertIn('posts.setForeground(foreground); topics.setForeground(foreground)', self.route)
        self.assertIn('retired = true; mounted = false; foreground = false', self.route)
    def test_bilingual_dedicated_table(self):
        data=json.loads((ROOT/'Resources/ProfileSettingsFavorites.xcstrings').read_text())
        self.assertEqual(len(data['strings']),7)
        for value in data['strings'].values():
            for lang in ['en','zh-Hans']:
                self.assertTrue(value['localizations'][lang]['stringUnit']['value'])
        self.assertEqual(self.route.count('tableName: "ProfileSettingsFavorites"'),2)
    def test_native_tests_are_authored(self):
        tests=(ROOT/'Tests/AppUnitTests/ProfileSettingsFavoritesTests.swift').read_text()
        self.assertEqual(tests.count('    func test'),13)
        for text in ['testHeldPostReplyAfterCollectionPop','testClosingSettingsIsPermanent','testApprovalRevocationRetires']:
            self.assertIn(text,tests)
if __name__ == '__main__': unittest.main()
