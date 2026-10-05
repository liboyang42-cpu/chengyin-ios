"""Source wiring checks only; Apple navigation/runtime tests remain unrun."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ClubHomeTopicNavigationChecks(unittest.TestCase):
    def read(self, name): return (ROOT/'App'/name).read_text()
    def test_event_uses_topic_id_and_native_navigation_link(self):
        s=self.read('ClubHomeView.swift')
        self.assertIn('if let topicDestination, event.id > 0',s)
        self.assertIn('NavigationLink { topicDestination(event.id) } label: { eventRow(event) }',s)
        self.assertIn('else if let onTopicDestination',s)
        self.assertIn('else { eventRow(event) }',s)
    def test_both_normal_hosts_inject_existing_guarded_destination(self):
        for file in ['QuestifyApp.swift','AccountView.swift']:
            s=self.read(file)
            self.assertIn('topicDestination: { AnyView(SessionTopicDetailView(id: $0, session: session)) }',s)
            self.assertIn('.id(session.sessionRevision)',s)
    def test_destination_keeps_auth_and_content_revision_guards(self):
        s=self.read('PlatformConsumerSessionOwner.swift')
        self.assertIn('if session.account == nil',s)
        self.assertIn('TopicIssueView(issue: .unauthorized)',s)
        self.assertIn('reader: session.topicReader',s)
        self.assertIn('.id(session.contentDetailRevision)',s)
    def test_fixture_is_offline_and_scope_reset_survives(self):
        s=self.read('ClubFixtureSupport.swift')
        self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('topicDestination: { id in',s)
        self.assertIn('.id(reader.clubIdentity)',s)
        self.assertNotIn('AppSession(',s)
    def test_authored_ui_tests_cover_back_reopen_signout_account_change(self):
        s=(ROOT/'Tests/AppUITests/ClubCommunityUITests.swift').read_text()
        for v in ['testClubHomeTopicNavigationBackAndReopen','testClubHomeTopicNavigationClearsOnSignOut','testClubHomeTopicNavigationClearsOnAccountSwitch','club.fixture.topic.91','club.fixture.signOut','club.fixture.switchAccount']:
            self.assertIn(v,s)
        self.assertNotIn('XCTSkip',s)
