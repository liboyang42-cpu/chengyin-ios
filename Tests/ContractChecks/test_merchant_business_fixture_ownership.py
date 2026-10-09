"""Advisory DEBUG ownership checks, not Swift compilation or hosted XCTest evidence."""
from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'App/MerchantBusinessFixtureSupport.swift'
HOSTED = ROOT / 'Tests/AppUnitTests/MerchantBusinessFixtureOwnershipTests.swift'


class MerchantBusinessFixtureOwnershipChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = FIXTURE.read_text()
        cls.tests = HOSTED.read_text()
        cls.owner = cls.fixture.split('@MainActor final class MerchantBusinessFixtureOwner {', 1)[1].split(
            '@MainActor struct MerchantBusinessFixtureHostView', 1)[0]
        cls.host = cls.fixture.split('@MainActor struct MerchantBusinessFixtureHostView', 1)[1].split(
            '@MainActor private struct MerchantBusinessFixtureOwnerProbe', 1)[0]
        cls.probe = cls.fixture.split('@MainActor private struct MerchantBusinessFixtureOwnerProbe', 1)[1]

    def test_reader_and_journal_are_owned_by_one_mounted_debug_state(self):
        self.assertTrue(self.fixture.startswith('#if DEBUG\n'))
        self.assertTrue(self.fixture.endswith('#endif\n'))
        self.assertEqual(self.fixture.count('#if'), 1)
        self.assertIn('@State private var owner: MerchantBusinessFixtureOwner', self.host)
        self.assertIn('_owner = State(initialValue: MerchantBusinessFixtureOwner(scenario: scenario))', self.host)
        self.assertIn('let reader = owner.reader, journal = owner.journal', self.host)
        self.assertIn('let reader: MerchantBusinessFixtureReader', self.owner)
        self.assertIn('let journal = MerchantBusinessMemoryIntentStore()', self.owner)
        self.assertIn('reader = .init(scenario: scenario)', self.owner)
        for forbidden in ['static ', 'shared', 'MerchantBusinessAccessModel', 'UserDefaults', 'Keychain']:
            self.assertNotIn(forbidden, self.owner)
        self.assertNotIn('private let reader:', self.host)
        self.assertNotIn('private let journal:', self.host)
        self.assertNotIn('MerchantBusinessMemoryIntentStore()', self.host)

    def test_launch_scenario_and_signout_behavior_are_preserved(self):
        self.assertIn('--uitesting-merchant-business-scenario', self.host)
        self.assertIn('name.flatMap(MerchantBusinessFixtureReader.Scenario.init(rawValue:)) ?? .ready', self.host)
        self.assertIn('if reader.scenario == .changedSession {', self.host)
        self.assertIn('Button("merchant.business.fixtureSignOut") { reader.scope = nil; revision += 1 }', self.host)
        self.assertIn('NavigationStack { MerchantBusinessHomeView(reader: reader, journal: journal) }.id(revision)', self.host)
        self.assertNotIn('.id(probeRevision)', self.host)
        for forbidden in ['.reserve(', '.complete(', '.execute(', '.confirm(', 'URLSession', 'Task.sleep']:
            self.assertNotIn(forbidden, self.owner + self.host + self.probe)

    def test_probe_is_optional_zero_size_noninteractive_and_observation_only(self):
        self.assertIn('ownerObserver: ((MerchantBusinessFixtureOwner, Int) -> Void)? = nil', self.host)
        self.assertIn('probeRevision: Int = 0', self.host)
        self.assertIn('if let ownerObserver {', self.host)
        self.assertIn('MerchantBusinessFixtureOwnerProbe(owner: owner, revision: probeRevision, observe: ownerObserver)', self.host)
        self.assertIn('.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)', self.host)
        self.assertIn('UIViewRepresentable', self.probe)
        self.assertIn('func updateUIView(_ uiView: UIView, context: Context) { observe(owner, revision) }', self.probe)
        for forbidden in ['Button(', 'Task {', 'Task.detached', 'DispatchQueue', 'Timer', 'URLRequest',
                          'URLSession', '.scope =', '.reserve(', '.complete(']:
            self.assertNotIn(forbidden, self.probe)

    def test_real_parent_redraw_uses_render_event_without_sleep_or_polling(self):
        self.assertTrue(self.tests.startswith('#if DEBUG\n'))
        self.assertTrue(self.tests.endswith('#endif\n'))
        for token in ['@ObservedObject var signal: RebuildSignal',
                      'MerchantBusinessFixtureHostView(ownerObserver: observe, probeRevision: signal.revision)',
                      'UIHostingController(rootView: RebuildingParent(',
                      'private let sceneWindow: HostedNavigationSceneWindow',
                      'init() throws { sceneWindow = try HostedNavigationSceneWindow() }',
                      'sceneWindow.retire()',
                      'window.rootViewController = host; window.makeKeyAndVisible()',
                      'guard observedRevision == revision, result == nil else { return }',
                      'await fulfillment(of: [rendered], timeout: 2)',
                      'mount.signal.revision = revision', 'for revision in [1, 2]',
                      'XCTAssertTrue(current === original, file: file, line: line)',
                      'XCTAssertTrue(current.reader === original.reader, file: file, line: line)',
                      'XCTAssertTrue(current.journal === original.journal, file: file, line: line)',
                      'XCTAssertEqual(try current.journal.intents(), [intent]',
                      'XCTAssertThrowsError(try current.journal.reserve(intent)',
                      'XCTAssertTrue(route.isCurrent(reader: current.reader, journal: current.journal))']:
            self.assertIn(token, self.tests)
        for forbidden in ['Task.sleep', 'Thread.sleep', 'usleep(', 'RunLoop', 'XCTSkip', 'continueAfterFailure = false', 'UIWindow(frame:']:
            self.assertNotIn(forbidden, self.tests)

    def test_distinct_hosts_capture_and_restore_scene_windows_in_lifo_order(self):
        first_render = self.tests.index('let first = try await renderedOwner(firstMount')
        second_mount = self.tests.index('let secondMount = try FixtureMount()')
        first_defer = self.tests.index('defer { firstMount.close() }')
        second_defer = self.tests.index('defer { secondMount.close() }')
        self.assertLess(first_defer, first_render)
        self.assertLess(first_render, second_mount)
        self.assertLess(second_mount, second_defer)
        self.assertNotIn('defer { firstMount.close(); secondMount.close() }', self.tests)

    def test_authored_hosted_cases_cover_isolation_and_all_context_changes(self):
        names = re.findall(r'func (test\w+)\(', self.tests)
        self.assertEqual(names, [
            'testActualHostedParentRedrawRetainsReaderJournalAndPreexistingRoutes',
            'testIndependentlyMountedHostsIsolateReaderJournalAndUnknownIntents',
            'testHostedSignOutRejectsOldRoutesWithoutClearingUnknownIntent',
            'testHostedNewAccountRejectsOldRoutesWithoutRebindingDependencies',
            'testHostedNewEpochRejectsOldRoutesWithoutRebindingDependencies',
        ])
        for token in ['XCTAssertFalse(first === second)', 'XCTAssertFalse(first.reader === second.reader)',
                      'XCTAssertFalse(first.journal === second.journal)',
                      'XCTAssertTrue(try second.journal.intents().isEmpty)',
                      'XCTAssertEqual(try first.journal.intents(), [intent])',
                      'second.reader.scope = nil', 'XCTAssertEqual(firstAfter.reader.scope, firstScope)',
                      'XCTAssertFalse(route.isCurrent(reader: current.reader, journal: current.journal))',
                      'XCTAssertEqual(route.context.scope, scope)',
                      'XCTAssertNotEqual(route, MerchantBusinessHomeRoute(',
                      'try await assertContextChangeRejectsPreexistingRoutes { _ in nil }',
                      'accountID: $0.accountID + 1, epoch: $0.epoch',
                      'accountID: $0.accountID, epoch: $0.epoch + 1']:
            self.assertIn(token, self.tests)

    def test_production_home_owns_its_access_model_and_route_guards_remain_exact(self):
        home = (ROOT / 'App/MerchantBusinessViews.swift').read_text()
        model = (ROOT / 'App/MerchantBusinessAccessModel.swift').read_text()
        self.assertIn('@StateObject private var accessModel = MerchantBusinessAccessModel()', home)
        self.assertIn('if route.isCurrent(reader: reader, journal: journal) {', home)
        self.assertIn('MerchantBusinessPage(reader: route.reader, journal: route.journal, query: query)', home)
        self.assertIn('else { Text("merchant.business.stale") }', home)
        self.assertEqual(hashlib.sha256(model.encode()).hexdigest(),
                         'aff601f64622ef1286026eaa9646a6f1b8ebf8f468677a165e0d2a0e1eeb8724')

    def test_all_ten_existing_ui_methods_remain_byte_identical(self):
        source = (ROOT / 'Tests/AppUITests/MerchantBusinessFlowTests.swift').read_bytes()
        self.assertEqual(hashlib.sha256(source).hexdigest(),
                         '6f7abf0f8348ef9c53137270d0fdb3150a5e1cefb625710a218aa4b5c4aa305c')
        self.assertEqual(len(re.findall(rb'func test\w+\(', source)), 10)


if __name__ == '__main__':
    unittest.main()
