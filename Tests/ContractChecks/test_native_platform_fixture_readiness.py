"""Advisory source regressions; actual navigation still requires Apple execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativePlatformFixtureReadinessChecks(unittest.TestCase):
    def test_runtime_keeps_the_same_state_lifetime_as_its_fixture_graph(self):
        source = (ROOT / 'App/NativePlatformFixtureHost.swift').read_text()
        host = source.split('@MainActor struct NativePlatformFixtureHost: View {', 1)[1]

        def check(text):
            for name, kind in [('data', 'NativePlatformFixtureData'),
                               ('advanced', 'PlayAdvancedCoordinator'),
                               ('runtime', 'NativePlatformRuntime')]:
                self.assertIn(f'@State private var {name}: {kind}', text)
                self.assertIn(f'_{name} = State(initialValue:', text)
            self.assertNotIn('private let runtime:', text)

        check(host)
        with self.assertRaises(AssertionError):
            check(host.replace('@State private var runtime:', 'private let runtime:'))
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertNotIn('URLSession', source)

    def test_both_real_navigation_links_wait_for_current_loaded_state(self):
        source = (ROOT / 'App/NativePlatformFixtureHost.swift').read_text()
        links = source.split('var body: some View {', 1)[1].split('Text(verbatim: String(data.requests))', 1)[0]
        self.assertEqual(links.count('NavigationLink('), 2)
        self.assertEqual(links.count('.disabled(!advanced.canInteract)'), 2)
        self.assertEqual(links.count('.accessibilityValue(Text(verbatim: advanced.phase))'), 2)
        for kind in ['steps', 'timeWindow']:
            self.assertIn(f'PlayKitScreen(model: advanced, kind: .{kind})', links)
        self.assertIn('.task { await advanced.start() }', source)

    def test_single_navigation_tap_has_strict_screen_and_native_host_boundaries(self):
        source = (ROOT / 'Tests/AppUITests/NativePlatformFlowTests.swift').read_text()
        helper = source.split('private func openFixture(', 1)[1].split('\n    func test', 1)[0]
        self.assertIn('enabled == true AND value == %@', helper)
        self.assertEqual(helper.count('tap(id, app: app)'), 1)
        self.assertLess(helper.index('XCTWaiter.wait'), helper.index('tap(id, app: app)'))
        self.assertIn('app.scrollViews["playkit.screen." + kind].waitForExistence', helper)
        self.assertIn('"nativePlatform." + destination + ".host"', helper)
        self.assertNotIn('for ', helper)
        self.assertNotIn('while ', helper)
        action = source.split('private func tap(', 1)[1].split('private func openFixture(', 1)[0]
        self.assertEqual(action.count('button.tap()'), 1)
        self.assertNotIn('for ', action)
        self.assertNotIn('while ', action)
        self.assertEqual(source.count('openFixture("steps", app: app)'), 3)
        self.assertEqual(source.count('openFixture("reminder", app: app)'), 3)

    def test_denial_and_write_consent_assertions_remain_strict(self):
        source = (ROOT / 'Tests/AppUITests/NativePlatformFlowTests.swift').read_text()
        denied = source.split('func testDeniedNotificationDoesNotShowScheduled()', 1)[1].split('\n    func test', 1)[0]
        for token in ['launch("denied")', 'openFixture("reminder", app: app)',
                      'XCTAssertTrue(app.staticTexts["nativePlatform.reminder.issue"].waitForExistence(timeout: 5)',
                      'Permission is off. You can change it in iPhone Settings.',
                      'XCTAssertFalse(app.staticTexts["nativePlatform.reminder.scheduled"].exists)',
                      'XCTAssertEqual(app.alerts.count, 0)']:
            self.assertIn(token, denied)
        self.assertEqual(source.count('tap("nativePlatform.steps.consent", app: app)'), 1)
        self.assertEqual(source.count('tap("nativePlatform.reminder.consent", app: app)'), 1)
        self.assertEqual(source.count('tap("nativePlatform.steps.send", app: app)'), 1)
        self.assertEqual(source.count('tap("nativePlatform.reminder.cancel", app: app)'), 1)
