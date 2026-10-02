#!/usr/bin/env python3
"""Read-only source/structure checks. Does not compile or execute Swift/iOS code."""
import argparse, json, pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'app-audit'
class TeamSourceChecks(unittest.TestCase):
    def text(self, name): return (ROOT / name).read_text()
    def source(self, name):
        if not (SOURCE / name).is_file(): self.skipTest('Preserved Flutter source is not available in this checkout')
        return (SOURCE / name).read_text()
    def test_owned_and_nearby_are_distinct(self):
        service = self.text('Core/TeamService.swift')
        self.assertIn('api/team/my', service)
        for path in ['api/team/nearby', 'api/team/apply', 'api/team/withdraw', 'api/team/my-applications']:
            self.assertNotIn(path, service)
        self.assertIn("'/api/team/my'", self.source('lib/data/api/team_map_api.dart'))
    def test_read_contracts_are_source_backed_post_json(self):
        source = self.source('lib/data/api/page_parity_api.dart')
        self.assertIn("_post('/api/team/info'", source)
        self.assertIn("'inviteCode': ?inviteCode", source)
        service = self.text('Core/TeamService.swift')
        self.assertIn('request.httpMethod = "POST"', service)
        self.assertIn('JSONSerialization.data(withJSONObject: body', service)
        self.assertIn('["api/team/my", "api/team/info"].contains(path)', service)
    def test_mutation_contracts_are_not_transports(self):
        contracts = self.text('Core/TeamContracts.swift')
        service = self.text('Core/TeamService.swift')
        source = self.source('lib/data/api/page_parity_api.dart')
        for route in ['create','join','quit','kick','disband']:
            self.assertIn('/api/team/' + route, contracts)
            self.assertIn('/api/team/' + route, source)
            self.assertNotIn('/api/team/' + route, service)
        self.assertRegex(service, r'func submit[^\n]+\{ \.notSent \}')
        self.assertNotIn('URLSession', service)
        adapter=self.text('Core/TeamHTTPService.swift')
        for guard in ['approval.allows', 'journal.pending', 'dispatchStarted = true', 'currentSession() == session', 'fresh == context']: self.assertIn(guard,adapter)
        self.assertLess(adapter.index('try journal.write(dispatched)'),adapter.index('transport.send'))
    def test_provisional_join_mode_has_no_mutation_or_toggle(self):
        source = self.source('lib/data/api/team_map_api.dart')
        self.assertIn('请求体形态按 create 的 `joinMode` 推定', source)
        self.assertNotIn('api/team/join-mode', self.text('Core/TeamService.swift'))
        self.assertIn('team.mode.provisional', self.text('App/TeamHomeView.swift'))
    def test_five_statuses_use_expire_time_and_server_count(self):
        source = self.source('lib/feature/team/team_pages.dart')
        for label in ['招募中','已满员','进行中','已结束','已解散']: self.assertIn(label, source)
        contracts = self.text('Core/TeamContracts.swift')
        self.assertIn('inProgress = 2, ended = 3, disbanded = 4', contracts)
        self.assertIn('expireTime', contracts); self.assertNotIn('startTime', contracts)
        self.assertNotIn('members.count', contracts.split('public struct TeamDetail')[0])
    def test_roster_role_zero_matches_source_fixture(self):
        self.assertIn('int role = 0', self.source('test/feature/team/team_pages_test.dart'))
        self.assertIn('$0.role == 0', self.text('Core/TeamContracts.swift'))
        self.assertIn('"role":0', self.text('Core/TeamSyntheticFixtures.swift'))
    def test_creation_matches_source_eligibility_sizes_and_default(self):
        source = self.source('lib/feature/orders/order_detail_sheet.dart')
        self.assertIn('d.ownerType == 2 && d.registrationStatus == 2 && d.teamMode == 2', source)
        self.assertIn('math.max(2, math.min(4, maxMembers ?? 4))', source)
        source = self.source('lib/data/api/team_map_api.dart')
        self.assertIn("if (inviteOnly) 'joinMode': 1", source)
        code = self.text('Core/TeamContracts.swift')
        self.assertIn('registrationStatus == 2 && teamMode == 2', code)
        self.assertIn('if inviteOnly { body["joinMode"] = .integer(1) }', code)
    def test_review_session_and_epoch_safety_are_explicit(self):
        service = self.text('Core/TeamService.swift')
        for word in ['accountID', 'epoch', 'region', 'role', 'let token: String']: self.assertIn(word, service)
        core = self.text('Core/TeamCoordinator.swift')
        for guard in ['currentSession() == session', 'generation == stamp', 'review == value', 'fresh == value.detail', 'action.lookup != activeLookup']:
            self.assertIn(guard, core)
    def test_persist_before_dispatch_and_unknown_has_no_clear(self):
        core = self.text('Core/TeamCoordinator.swift')
        self.assertLess(core.index('try journal.write(record);'), core.index('await service.submit'))
        self.assertIn('case .unknown: writeState = .unknown;', core)
        self.assertNotIn('case .unknown: try journal.clear', core)
        record = core.split('public struct TeamPendingRecord')[1].split('@MainActor')[0]
        for secret in ['inviteCode', 'token:', 'memberName', 'members:']: self.assertNotIn(secret, record)
    def test_release_has_no_synthetic_dispatch(self):
        core = self.text('Core/TeamCoordinator.swift')
        self.assertIn('#if DEBUG\n        return service.authority == .synthetic\n        #else\n        return false', core)
        self.assertTrue(self.text('Core/TeamSyntheticFixtures.swift').startswith('#if DEBUG'))
        self.assertTrue(self.text('App/TeamFixtureSupport.swift').startswith('#if DEBUG'))
    def test_no_invitation_sharing_or_financial_operations(self):
        app = '\n'.join(p.read_text() for p in (ROOT/'App').glob('*Team*.swift'))
        for forbidden in ['ShareLink(', 'UIActivityViewController', 'UIPasteboard', 'openURL(', 'redeem(', 'refund(', 'purchase(']: self.assertNotIn(forbidden, app)
        self.assertIn('team.invite.previewOnly', app)
    def test_all_team_localizations_exist_in_both_languages(self):
        catalog = json.loads(self.text('Resources/TeamLocalizations.fragment.json'))['strings']
        used = set()
        for p in list((ROOT/'App').glob('*Team*.swift')) + list((ROOT/'Core').glob('*.swift')):
            used |= set(re.findall(r'"(team\.[a-zA-Z][a-zA-Z.]+)"', p.read_text()))
        excluded = {'team.review.confirm', 'team.review.cancel', 'team.review.leaveInstead', 'team.detail.card', 'team.invite.code', 'team.invite.close', 'team.create.size', 'team.create.inviteOnly', 'team.message'}
        self.assertEqual(used - set(catalog) - excluded, set())
        for key, item in catalog.items():
            self.assertEqual(set(item['localizations']), {'en','zh-Hans'}, key)
            for value in item['localizations'].values(): self.assertTrue(value['stringUnit']['value'])
    def test_authored_tests_cover_interrupted_flows(self):
        tests = self.text('Tests/CoreTests/TeamCoordinatorTests.swift')
        for name in ['testDoubleConfirm', 'testUnknownOutcomeSurvivesNewCoordinator', 'testWrongTeamReceipt', 'testRoleChangeDuringPreflight', 'testDismissalDuringSubmission']:
            self.assertIn(name, tests)
        ui = self.text('Tests/AppUITests/TeamFlowTests.swift')
        for name in ['testOwnedListDetailBackAndReopen', 'testChineseLargeTextDarkMode', 'testUnknownOutcomeCannotReplayAfterSameAccountReauthentication']:
            self.assertIn(name, ui)
