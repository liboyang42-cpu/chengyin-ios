"""Run51 fixture-isolation regressions; source assertions are not Apple UI execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WorkbenchFixtureIsolationChecks(unittest.TestCase):
    def source(self, path):
        return (ROOT / path).read_text()

    def test_all_cooperation_launches_reset_persisted_language(self):
        source = self.source('Tests/AppUITests/CooperationFlowUITests.swift')
        self.assertEqual(source.count('app.launch()'), 1)
        helper = source.split('private func launch(', 1)[1].split('private func reveal(', 1)[0]
        for token in ['--uitesting-reset-language', '-AppleLanguages', '-AppleLocale',
                      '"Cooperation center" : "合作中心"', 'app.navigationBars[title].waitForExistence']:
            self.assertIn(token, helper)
        self.assertIn('let app = launch()', source.split('func testSyntheticFinanceAndDormantReview()', 1)[1].split('func testTemplatePreviewCannotSubmit()', 1)[0])
        self.assertIn('let app = launch()', source.split('func testTemplatePreviewCannotSubmit()', 1)[1].split('private func launch(', 1)[0])

    def test_merchant_launch_requires_requested_language(self):
        source = self.source('Tests/AppUITests/MerchantEngagementFlowTests.swift')
        helper = source.split('private func launch(', 1)[1].split('private func reveal(', 1)[0]
        for token in ['--uitesting-reset-language', '-AppleLanguages', '-AppleLocale',
                      '"CRM operations" : "客户运营"', 'app.navigationBars[title].waitForExistence']:
            self.assertIn(token, helper)
        self.assertIn('The task was created. Dispatch requires its own review.', source)

    def test_cooperation_signout_is_host_scoped_and_resets_navigation(self):
        source = self.source('App/CooperationFlowFixtures.swift').split('@MainActor struct CoopFlowFixtureHost', 1)[1]
        self.assertLess(source.index('Button("coopflow.fixture.signOut")'), source.index('NavigationStack {'))
        self.assertNotIn('.toolbar', source)
        self.assertIn('reader.session = nil', source)
        self.assertIn('}.id(reader.session == nil)', source)
        tests = self.source('Tests/AppUITests/CooperationFlowUITests.swift')
        signout = tests.split('func testSessionChangeDropsNavigationAndReceivedApplicationData()', 1)[1]
        self.assertIn('XCTAssertTrue(signOut.isHittable)', signout)
        self.assertIn('app.navigationBars["Cooperation center"].waitForExistence', signout)
        self.assertIn('XCTAssertFalse(app.buttons["coopflow.row.0"].exists)', signout)
        self.assertIn('Sign in to view your cooperation', signout)
        self.assertIn('XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)', signout)

    def test_merchant_external_signout_does_not_use_list_reveal(self):
        source = self.source('Tests/AppUITests/MerchantEngagementFlowTests.swift')
        test = source.split('func testSignoutClearsPreviouslyLoadedSegments()', 1)[1]
        self.assertNotIn('tap("merchant.engagement.fixtureSignOut"', test)
        self.assertNotIn('reveal(', test)
        for token in ['signOut.waitForExistence', 'XCTAssertTrue(signOut.isHittable)', 'signOut.tap()',
                      'XCTAssertFalse(app.buttons["merchant.engagement.segment.71001"].exists)',
                      'XCTAssertFalse(app.buttons["merchant.engagement.saveSegment"].exists)',
                      'XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)']:
            self.assertIn(token, test)

    def test_contextual_cooperation_fixture_and_safety_assertions_remain(self):
        fixture = self.source('App/CooperationFlowFixtures.swift')
        for token in ['case .clubs:', 'case .merchants:', 'case .ownedTopics:', 'inviteWindowOpen',
                      'case .nearby, .perks:', '--cooperation-flow-denied']:
            self.assertIn(token, fixture)
        tests = self.source('Tests/AppUITests/CooperationFlowUITests.swift')
        for token in ['XCTAssertFalse(submit.isEnabled)', 'XCTAssertEqual(app.alerts.count, 0)',
                      'XCTAssertEqual(field.value as? String, "Keep this local draft")',
                      'XCTAssertNotEqual(field.value as? String, "Keep this local draft")',
                      'Amount not confirmed', 'Pending settlement']:
            self.assertIn(token, tests)


if __name__ == '__main__':
    unittest.main()
