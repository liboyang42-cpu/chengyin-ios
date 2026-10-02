"""Source guards supplement (not replace) Swift compilation, XCTest and simulator review."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CooperationStructureTests(unittest.TestCase):
    def text(self, name):
        return (ROOT / name).read_text()

    def test_only_audited_read_routes(self):
        service = self.text('Core/CooperationService.swift')
        routes = set(re.findall(r'"(api/coop/[^"\\]+)"', service))
        self.assertEqual(routes, {'api/coop/list', 'api/coop/pool/mine', 'api/coop/pool/received',
                                 'api/coop/candidates/received', 'api/coop/pool/list', 'api/coop/candidates'})
        self.assertNotRegex(service, r'api/coop/(invite|handle|contact|deposit|offer|review|finance|mybiz)')
        self.assertIn('"application/json"', service)
        self.assertIn('["topicId": topicID]', service)

    def test_detail_is_fresh_directional_and_not_first_duplicate(self):
        source = self.text('Core/CooperationService.swift')
        self.assertIn('let list = try await invitations(token: token)', source)
        self.assertIn('list.rows(key.direction)', source)
        self.assertIn('guard matches.count == 1', source)
        self.assertIn('list.occupancy(for: row)', source)

    def test_independent_sources_and_authentication_closes_all(self):
        source = self.text('Core/CooperationService.swift')
        self.assertIn('async let invites', source)
        self.assertIn('async let applies', source)
        self.assertIn('async let regs', source)
        self.assertIn('try requireAuthorized(results.0); try requireAuthorized(results.1); try requireAuthorized(results.2)', source)
        self.assertIn('CooperationIssue(error)', source)
        self.assertIn('hasMore', self.text('Core/CooperationContracts.swift'))
        self.assertIn('cooperation.registrations.more', self.text('App/CooperationBrowserView.swift'))

    def test_tokens_stay_private_and_scope_checks_wrap_success_and_failure(self):
        source = self.text('Core/CooperationReading.swift')
        self.assertIn('fileprivate let token: String', source)
        self.assertNotIn('public let token', source)
        self.assertGreaterEqual(source.count('currentSession() == session, scope == captured'), 2)
        self.assertIn('loadedScope == scope ? value : nil', source)
        self.assertIn('generation == captured, currentScope() == scope', source)
        self.assertNotRegex(source, r'UserDefaults|FileManager|URLCache|print\(')
        for file in ROOT.glob('App/Cooperation*.swift'):
            self.assertNotIn('session.token', file.read_text())

    def test_native_accessibility_controls_and_no_custom_motion_or_fake_actions(self):
        app = '\n'.join(file.read_text() for file in ROOT.glob('App/Cooperation*.swift'))
        for name in ['NavigationStack', 'NavigationLink', 'ProgressView', 'Section', 'Picker', 'List', '.textSelection(.enabled)']:
            self.assertIn(name, app)
        self.assertNotRegex(app, r'\.minimumScaleFactor|Timer\.|\.animation\(|\.scaleEffect|\.onTapGesture|\bLink\(')
        self.assertIn('CooperationReadOnlyNotice()', app)
        self.assertIn('if !pool.hasClub', app)
        self.assertNotRegex(app, r'Button\("(?:Accept|Reject|Pay|Refund|Contact|Confirm candidate)"')

    def test_ui_tests_use_buttons_and_not_sheet_assumptions(self):
        tests = self.text('Tests/AppUITests/CooperationFlowTests.swift')
        self.assertNotIn('app.sheets', tests)
        self.assertNotRegex(tests, r'staticTexts\[[^\n]+\]\.tap\(')
        self.assertIn('cooperation.invite.received.71.0', tests)
        self.assertIn('cooperation.invite.sent.71.0', tests)
        self.assertIn('cooperation.fixture.signOut', tests)

    def test_bilingual_entries_are_unique_and_dynamic_states_are_covered(self):
        entries = json.loads(self.text('docs/cooperation-localizations.json'))
        keys = [entry['key'] for entry in entries]
        self.assertEqual(len(keys), len(set(keys)))
        for entry in entries:
            self.assertTrue(entry['en'].strip())
            self.assertTrue(entry['zh-Hans'].strip())
        for suffix in [*(f'invite.status.{i}' for i in range(6)), *(f'application.status.{i}' for i in range(4)),
                       *(f'registration.status.{i}' for i in range(3)),
                       *(f'pool.state.{state}' for state in ['open', 'applied', 'invited', 'taken', 'cooped', 'converted', 'declined', 'withdrawn'])]:
            self.assertIn('cooperation.' + suffix, keys)
        for file in ROOT.glob('App/Cooperation*.swift'):
            self.assertNotRegex(file.read_text(), r'LocalizedStringKey\("[^"\n]*\\\(')

    def test_fixture_json_valid_and_transport_free(self):
        source = self.text('Core/CooperationSyntheticFixtures.swift')
        fixtures = re.findall(r'#"""\n(.*?)\n    """#', source, re.S)
        self.assertEqual(len(fixtures), 6)
        for fixture in fixtures:
            self.assertEqual(json.loads(fixture)['code'], 200)
        source = self.text('App/CooperationFixtureSupport.swift')
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertNotRegex(source, r'URLSession|HTTPTransport|CooperationService|https?://')


if __name__ == '__main__':
    unittest.main()
