"""P045 public-profile routing SOURCE checks, not Swift/Apple runtime evidence."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def route_contract(source):
    helper = source.split('struct ClubLeaderboardMemberRoute:', 1)[1].split('struct ClubGovernanceReadView:', 1)[0]
    for token in [
        'context.operation == .leaderboard', 'context.accepts(snapshot)', 'viewer.isSignedIn',
        'clubID > 0', 'snapshot.permissions?.allows(ClubGovernanceRead.leaderboard.permission, scope: context.scope) == true',
        'profile.reader.isConfigured', 'profile.reader.identity.accountID == viewer.accountID',
        'profile.reader.identity.epoch == viewer.epoch', '(1...9_007_199_254_740_991).contains(memberID)',
        'row["clubId"] == .null || row["clubId"].int == clubID', 'rows.contains(row)',
        'rows.filter({ $0["memberId"].int == memberID }).count == 1',
        'self.context == context', 'self.snapshotGeneration == snapshotGeneration', 'snapshot == source',
        'profile.reader.identity == profileIdentity', 'profile.reader.presentationRevision == profileRevision',
        'ObjectIdentifier(profile.reader) == profileReaderIdentity',
        'ObjectIdentifier(profile.squareReader) == squareReaderIdentity', 'profile.squareReader.scope == squareScope',
    ]:
        if token not in helper:
            raise ValueError('Missing public-route fence: ' + token)
    if helper.count('profile.reader.isConfigured') != 2:
        raise ValueError('Both creation and current-selection paths must check configuration')
    return helper


class ClubLeaderboardMemberNavigationTests(unittest.TestCase):
    def source(self): return (ROOT / 'App/ClubGovernanceViews.swift').read_text()
    def test_positive_scoped_route_contract(self):
        route_contract(self.source())
    def test_every_new_route_fence_rejects_a_source_mutation(self):
        original = self.source()
        for token in ['context.operation == .leaderboard', 'context.accepts(snapshot)', 'viewer.isSignedIn',
                      'profile.reader.isConfigured', 'profile.reader.identity.accountID == viewer.accountID',
                      'profile.reader.identity.epoch == viewer.epoch', '(1...9_007_199_254_740_991).contains(memberID)',
                      'rows.contains(row)', 'rows.filter({ $0["memberId"].int == memberID }).count == 1',
                      'self.context == context', 'self.snapshotGeneration == snapshotGeneration',
                      'snapshot == source', 'profile.reader.identity == profileIdentity',
                      'profile.reader.presentationRevision == profileRevision',
                      'ObjectIdentifier(profile.reader) == profileReaderIdentity',
                      'ObjectIdentifier(profile.squareReader) == squareReaderIdentity', 'profile.squareReader.scope == squareScope']:
            with self.subTest(fence=token), self.assertRaises(ValueError):
                route_contract(original.replace(token, 'true', 1))
    def test_explicit_public_profile_button_preserves_existing_facts(self):
        source = self.source()
        branch = source.split('} else if let target = leaderboardMemberRoute(row) {', 1)[1].split('} else {', 1)[0]
        self.assertIn('ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields, showUnknown: true)', branch)
        self.assertIn('Label("social.profile", systemImage: "person.crop.circle")', branch)
        self.assertIn('selectLeaderboardMember(target)', branch)
        self.assertIn('club.gov.leaderboard.profile.\\(target.memberID)', branch)
    def test_reuses_existing_reader_destination_and_defaults_to_no_profile(self):
        source = self.source()
        self.assertIn('@Environment(\\.clubEnrollmentProfile) private var leaderboardProfile', source)
        self.assertIn('SocialPublicProfileView(memberID: target.memberID, reader: profile.reader,', source)
        self.assertIn('squareReader: profile.squareReader, actions: profile.actions)', source)
        self.assertIn('static let defaultValue: ClubEnrollmentProfileContext? = nil', (ROOT / 'App/ClubEnrollmentView.swift').read_text())
        self.assertIn('enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader', (ROOT / 'App/AppSession.swift').read_text())
    def test_duplicate_selection_and_covered_destination_recheck_current_scope(self):
        source = self.source()
        self.assertIn('guard leaderboardMember == nil, snapshotGeneration == generation, current(target) else { return }', source)
        self.assertIn('.onChange(of: current(target), initial: true)', source)
        self.assertIn('if !valid, leaderboardMember?.id == target.id { leaderboardMember = nil }', source)
        body = source.split('private func current(_ target: ClubLeaderboardMemberRoute)', 1)[1].split('private func current(_ target: ClubFeedClubRoute)', 1)[0]
        for token in ['identity == access.identity', 'access.isConfigured', 'snapshotContext == readContext', 'snapshotGeneration: snapshotGeneration']:
            self.assertIn(token, body)
    def test_refresh_and_identity_invalidation_clear_selection(self):
        source = self.source()
        load = source.split('private func load() async {', 1)[1].split('private func invalidateRead()', 1)[0]
        invalidate = source.split('private func invalidateRead()', 1)[1].split('private func current(', 1)[0]
        self.assertIn('leaderboardMember = nil', load)
        self.assertIn('leaderboardMember = nil', invalidate)
        self.assertIn('.onChange(of: identity) { _, _ in invalidateRead() }', source)
        self.assertIn('.onChange(of: readContext) { _, _ in invalidateRead() }', source)
    def test_no_new_transport_write_or_private_customer_destination(self):
        source = self.source()
        helper = route_contract(source)
        destination = source.split('.navigationDestination(item: $leaderboardMember)', 1)[1].split('.navigationDestination(item: $customerTopic)', 1)[0]
        for forbidden in ['URLSession', 'HTTPTransport', 'saveCustomer', 'operation: .customer', 'phoneText', 'paidAmount', 'tag-remark']:
            self.assertNotIn(forbidden, helper + destination)
        profile = (ROOT / 'App/SocialPublicProfileView.swift').read_text()
        self.assertIn('reader.publicProfile(memberID: memberID)', profile)
        self.assertIn('guard generation == run, key == captured else { return }; value = loaded', (ROOT / 'App/SocialAccountComponents.swift').read_text())
    def test_prior_customer_product_spans_are_exact_published_bytes(self):
        source = self.source()
        spans = [
            ('            if operation == .customers {', '            if operation == .topicCustomers {', '4ff031e8141754314d6d2cc15dfcaa5a91c849b6c92af351df284ad867c9c8e2'),
            ('    @MainActor private func loadCustomersNow()', '    @MainActor private func load() async {', '162f631efc7d2991e12546535fd129c41fcdc2a919e497a4ec91e4d027994805'),
            ('        } else if operation == .customer {', '        } else {\n            ClubGovernanceFactRows(value: value, fields: ClubGovernanceFactRows.summaryFields)', '50f8cab4aa3f2256e6f9fd3faadb37347685f0bef41f6f48f1ed971d3734264a'),
            ('/// P044 keyword-only scheduling.', '/// Mount independently of legacy', '6428a003b8500230f56372b775f14fd0c1f72230c39ed53b8713b9e318c5420f'),
        ]
        for start, end, expected in spans:
            text = source[source.index(start):source.index(end, source.index(start))]
            self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), expected)
    def test_shared_localization_is_existing_bilingual_public_profile(self):
        strings = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for language in ['en', 'zh-Hans']:
            self.assertTrue(strings['social.profile']['localizations'][language]['stringUnit']['value'])
    def test_fixture_uses_matching_retained_readers_and_synchronizes_before_identity_publication(self):
        source = (ROOT / 'App/ClubGovernanceFixtureHost.swift').read_text()
        self.assertIn('profileReader.identity = .init(accountID: replacement.accountID, epoch: replacement.epoch)', source)
        switch = source.split('func switchAccount()', 1)[1]
        self.assertLess(switch.index('profileReader.identity ='), switch.index('identity = replacement'))
        self.assertIn('.environment(\\.clubEnrollmentProfile, store.leaderboardProfile)', source)
        self.assertTrue(source.startswith('#if DEBUG'))
    def test_route_models_and_real_view_tests_are_distinguished(self):
        unit = (ROOT / 'Tests/AppUnitTests/ClubLeaderboardMemberRouteTests.swift').read_text()
        ui = (ROOT / 'Tests/AppUITests/ClubLeaderboardMemberFlowTests.swift').read_text()
        self.assertEqual(unit.count('    func test'), 10)
        self.assertIn('Route/model tests only.', unit)
        self.assertIn('NOT_RUN', unit)
        self.assertEqual(ui.count('    func testLeaderboard'), 6)
        original = (ROOT / 'Tests/AppUITests/ClubGovernanceFlowTests.swift').read_bytes()
        self.assertEqual(hashlib.sha256(original).hexdigest(), '4d41464ed772a0c371669e5dd55c8a06700b5980e2cb6f17e6ece58a7d1ce7ee')
        self.assertIn('final class ClubLeaderboardMemberFlowTests: XCTestCase', ui)
        self.assertIn('app.navigationBars.buttons.firstMatch.tap()', ui)
        self.assertIn('late.isInverted = true', ui)
        self.assertIn('for _ in 0..<2', ui)
    def test_mini_actual_public_member_navigation(self):
        root = os.environ.get('CHENGYIN_CLUB_LEADERBOARD_MINI_ROOT')
        if root is None:
            self.skipTest('NOT_RUN: private Mini source not supplied')
        root = Path(root)
        source = (root / 'pages/club/detail/index.js').read_text()
        wxml = (root / 'pages/club/detail/index.wxml').read_text()
        self.assertIn('catchtap="goMemberProfile" data-member-id="{{item.memberId}}"', wxml)
        start = source.index('  goMemberProfile(e) {')
        end = source.index('\n  },', start) + len('\n  }')
        method = source[start:end]
        script = r'''
const vm = require('vm');
const method = JSON.parse(process.argv[1]);
let routes = [];
const page = vm.runInNewContext('({' + method + '})', { wx: { navigateTo: v => routes.push(v.url) } });
page.data = {clubId: 81};
for (const canRead of [false, true]) {
  page.canReadCustomerProfile = () => canRead;
  page.openChoiceSheet = (_a, _b, _choices, select) => select({key: 'public'});
  routes = []; page.goMemberProfile({currentTarget: {dataset: {memberId: 704}}});
  if (JSON.stringify(routes) !== JSON.stringify(['/pages/userinfo/userinfo?userId=704'])) throw Error('wrong public route');
  routes = []; page.goMemberProfile({currentTarget: {dataset: {}}});
  if (routes.length) throw Error('missing member routed');
}
process.stdout.write('MINI_PUBLIC_MEMBER_ROUTE_4_SCENARIOS_PASS\n');
'''
        result = subprocess.run(['node', '-e', script, json.dumps(method)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('4_SCENARIOS_PASS', result.stdout)

if __name__ == '__main__': unittest.main()
