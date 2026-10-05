"""Source-only wiring and scope checks. Apple compilation/execution is a separate gate."""
from pathlib import Path
import re
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class IntegratedNativeAcceptanceContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_debug_factory_enters_the_existing_container_and_root(self):
        fixture = self.read('App/IntegratedNativeAcceptanceFixture.swift')
        app = self.read('App/QuestifyApp.swift')
        self.assertTrue(fixture.startswith('#if DEBUG\n'))
        self.assertTrue(fixture.rstrip().endswith('#endif'))
        self.assertIn('IntegratedNativeAcceptanceFixture.selected(arguments: arguments)', app)
        self.assertIn('fixture.makeComposition().makeSession()', app)
        self.assertIn('fixture.session = acceptedSession', app)
        self.assertIn('SessionRootView(session:session)', app)
        for forbidden in ['session.login(', 'loginWithPhone(', 'WelcomeView(', 'TabView', 'NavigationStack', 'URLSession', 'CLLocationManager']:
            self.assertNotIn(forbidden, fixture)
        production = self.read('App/RegionalLaunchConfiguration.swift')
        self.assertIn('.init(deployment: .unconfigured,', production)
        self.assertIn('let approved:[RegionalMarket:Set<String>]=[:]', production)

    def test_single_recorder_fails_closed_and_grants_exact_current_context(self):
        source = self.read('App/IntegratedNativeAcceptanceFixture.swift')
        self.assertEqual(source.count(': ObservableObject, HTTPTransport'), 1)
        for required in ['https://native-acceptance.example/native', 'canonical.httpBody', 'default: try reject(',
                         'context.session.epoch == session.sessionRevision', 'context.session.token == vault.value',
                         'context.session.namespace == deployment.storageScope.service',
                         'ContentDraftContextFence.matches(retained.context, context)', 'playReadApprovalID: UUID()',
                         'play: [.reads]', 'retained?.orders.revoke()', 'request.httpBodyStream == nil',
                         'playRecovery: .synthetic(anchors: recoveryAnchors, ciphertexts: recoveryCiphertexts)']:
            self.assertIn(required, source)
        for forbidden in ['.allowsDevice', '.runPersistence', '.classicCompletion', 'requestWhenInUseAuthorization',
                          'UserDefaults.standard', 'ProcessInfo.processInfo.environment']:
            self.assertNotIn(forbidden, source)

    def test_bounded_ui_cases_use_phone_inputs_and_normal_destinations(self):
        source = (self.read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift') + '\n' + self.read('Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift'))
        self.assertEqual(len(re.findall(r'func\s+test\w+\(', source)), 8)
        for required in ['auth.channels.sendCode', 'auth.channels.phoneSignIn', 'homeFeed.nearby.activity.21', 'roam.area.select',
                         'activity.openPlay', 'profile.open.orders', 'profile.order.41',
                         'final.ledger.dropFirst(9)', 'assertIdentity(', 'try closeFrontSheet(app)',
                         'app.terminate(); app.launch()', 'profile.orders.unavailable']:
            self.assertIn(required, source)
        self.assertNotIn('--uitesting-module', source)
        self.assertNotIn('loginWithPhone(', source)
        self.assertNotIn('.lastMatch', source)
        self.assertIn('tapFixtureSheetAction("Sign out", in: confirmation, app: app)', source)
        self.assertIn('self.availableEvidence(app).map(condition)', source)
        self.assertIn('XCTAssertTrue(value.manualArea)', source)

    def test_shelf_next_page_uses_bounded_native_container_progress(self):
        source = (self.read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift') + '\n' + self.read('Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift'))
        block = source.split('private func tapOwnedShelfNextPage', 1)[1].split('private func closeFrontSheet', 1)[0]
        for required in ['app.collectionViews', 'app.tables', 'app.scrollViews', 'memberTemplate.mine.',
                         '0..<30', 'bounds.contains(target.frame)', 'target.isEnabled', 'target.isHittable',
                         'before == visibleRows(viewport())', 'XCTFail(']:
            self.assertIn(required, block)
        self.assertNotIn('sleep', block)
        self.assertNotIn('maximumSwipes:', block)

    def test_map_overflow_requires_unique_visible_native_leaf_then_exact_action(self):
        source = (self.read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift') + '\n' + self.read('Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift'))
        block = source.split('private func tapRoamOverflowToggle', 1)[1].split('private func tapOwnedShelfNextPage', 1)[0]
        for required in ['navigation.buttons["Official city"]', 'frame.minX >= city.frame.maxX',
                         'navigation.frame.contains(frame)', 'app.frame.contains(frame)',
                         '$0.isEnabled && $0.isHittable', 'leaves.count == 1', 'overflow.tap()',
                         'NSPredicate(format: "label == %@", "Show list only")', 'exact.count == 1',
                         'toggle.isEnabled, toggle.isHittable', '!toggle.frame.isEmpty', 'app.frame.contains(toggle.frame)']:
            self.assertIn(required, block)
        self.assertEqual(block.count('overflow.tap()'), 1)
        self.assertNotIn('sleep', block)
        self.assertNotIn('"More"', block)
        self.assertIn('"-AppleLanguages", "(en)", "-AppleLocale", "en_US"', source)
        self.assertNotIn('label CONTAINS', block)
        self.assertNotIn('firstMatch.tap()', block)

    def test_phone_fixture_matches_real_provisional_and_authoritative_parser_shapes(self):
        source = self.read('App/IntegratedNativeAcceptanceFixture.swift')
        phone = source.split('} else if path == "api/login/phone" {', 1)[1].split('} else if path == "api/userInfo" {', 1)[0]
        user_info = source.split('} else if path == "api/userInfo" {', 1)[1].split('} else if path == "api/logout" {', 1)[0]
        # Inspect the actual interpolated JSON literals; this is not Swift execution.
        for owner in [7, 8]:
            def payload(block):
                literal = re.search(r'json = (".*")', block).group(1)
                return json.loads(json.loads(literal.replace(r'\(owner)', str(owner))))
            provisional, authoritative = payload(phone), payload(user_info)
            self.assertEqual(provisional['data']['id'], owner)
            self.assertGreater(provisional['data']['id'], 0)
            self.assertEqual(authoritative['appUser']['userId'], provisional['data']['id'])
            self.assertEqual(authoritative['appUser']['role'], 'player')
            self.assertEqual(provisional['token'], f'synthetic-{owner}')
        service = self.read('Core/AuthChannelService.swift')
        coordinator = self.read('Core/AuthChannelCoordinator.swift')
        self.assertIn('let account = body.data, account.id > 0', service)
        self.assertIn('account.id == result.account.id', coordinator)
        self.assertIn('if path == "api/sms/send"', source)

    def test_generated_project_contains_all_new_swift_sources(self):
        project = self.read('Questify.xcodeproj/project.pbxproj')
        for path in ['App/IntegratedNativeAcceptanceFixture.swift',
                     'Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift',
                     'Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift',
                     'Tests/AppUnitTests/IntegratedNativeAcceptanceFactoryTests.swift']:
            self.assertIn(path, project)
        proof = self.read('Tests/AppUnitTests/IntegratedNativeAcceptanceFactoryTests.swift')
        for required in ['@MainActor final class', 'Decimal(string: "12.3456")',
                         'oldOrderApproval.isRevoked', 'XCTAssertNil(oldPlay.identity)',
                         'XCTAssertNil(root.manualMapReadApproval(first))', 'XCTAssertEqual(fixture.ledger.count, count)',
                         'capturedTransport.send(oldRequest)', 'retainedReader === session.ownedOrderReader',
                         'case tokenOnly, malformedID, nonPositiveID, mismatchedID', 'assertPhoneProjectionRejected(fault)']:
            self.assertIn(required, proof)

    def test_play_tap_excludes_actual_registration_inset_and_fixture_supplies_mode(self):
        source = (self.read('Tests/AppUITests/IntegratedNativeAcceptanceFlowTests.swift') + '\n' + self.read('Tests/AppUITests/IntegratedActivityPlayJourneyFlowTests.swift'))
        block = source.split('private func tapActivityPlay(', 1)[1].split('private func tapRoamOverflowToggle', 1)[0]
        for required in ['activity.openRegistration', 'app.tabBars.firstMatch',
                         'registration.frame.minY - 12', 'tabs.frame.minY - 4',
                         'activityPlayRowFits(row.frame, viewport: viewport)', 'row.isEnabled', 'row.isHittable',
                         '0...10', 'row.tap(); return', 'XCTFail(']:
            self.assertIn(required, block)
        self.assertNotIn('sleep', block)
        self.assertIn('tapActivityPlay(app)', source)
        self.assertIn('XCTAssertFalse(app.navigationBars["Activity registration"].exists)', source)
        fixture = self.read('App/IntegratedNativeAcceptanceFixture.swift')
        play = fixture.split('json = route == "play-nodes" ? ', 1)[1].split(' : ', 1)[0]
        play = play.replace(r'\(graph)', '{}')
        data = json.loads(json.loads(play))['data']
        self.assertEqual(data['mode'], 1)
        self.assertEqual(data['topicName'], 'Synthetic read-only play')

if __name__ == '__main__':
    unittest.main()
