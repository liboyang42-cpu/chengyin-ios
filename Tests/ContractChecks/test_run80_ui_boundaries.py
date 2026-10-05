"""Supplementary test-source guards; no claim of Swift or simulator execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Run80UIBoundaryChecks(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_cancel_acknowledged_before_single_account_action(self):
        source = self.text('Tests/AppUITests/ClubManagementFlowTests.swift')
        self.assertIn('private func cancelReview(', source)
        helper = source.split('private func cancelReview(', 1)[1].split('func testApprove', 1)[0]
        self.assertIn('bar.buttons.matching', helper)
        self.assertIn('try cancel.snapshot()', helper)
        self.assertIn('bar.frame.contains(snapshot.frame)', helper)
        self.assertEqual(helper.count('.tap()'), 1)
        self.assertLess(helper.index('.tap()'), helper.index('exists == false'))
        self.assertIn('XCTAssertFalse(app.buttons["club.management.confirm"].exists', helper)
        case = source.split('func testCancelThenSwitchAccountSendsNothing()', 1)[1]
        self.assertLess(case.index('try cancelReview'), case.index('accountSwitch.tap()'))
        self.assertLess(case.index('hittable == true AND enabled == true'), case.index('accountSwitch.tap()'))
        self.assertLess(case.index('accountSwitch.tap()'), case.index('account=702;epoch=1'))
        self.assertEqual(case.count('.tap()'), 1)
        for token in ['account=701;epoch=0', 'count(0)', 'XCTAssertFalse(app.navigationBars["Application details"].exists',
                      'XCTAssertFalse(app.buttons["club.management.confirm"].exists']:
            self.assertIn(token, case)

    def test_account_marker_observes_existing_fixture_action_only(self):
        source = self.text('App/ClubManagementFixtureSupport.swift')
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('@StateObject private var store', source)
        self.assertIn('Button("club.management.switch_account") { store.switchAccount() }', source)
        self.assertIn('account=\\(store.identity?.accountID ?? 0);epoch=\\(store.identity?.epoch ?? 0)', source)
        self.assertIn('}.id(store.identity)', source)
        self.assertIn('coordinator.synchronizeSession()', source)

    def test_creator_uses_real_keyboard_and_exact_review_before_confirm(self):
        source = self.text('Tests/AppUITests/PublisherLifecycleUITests.swift')
        case = source.split('func testCreatorFormShowsExactReviewAndDisabledDispatch()', 1)[1]
        self.assertIn('try name.snapshot()', case)
        tap = 'name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()'
        self.assertEqual(case.count(tap), 1)
        self.assertEqual(case.count('name.typeText(expectedName)'), 1)
        keyboard = 'app.keyboards.firstMatch.waitForExistence(timeout: 5)'
        self.assertLess(case.index(tap), case.index(keyboard))
        self.assertLess(case.index(keyboard), case.index('name.typeText(expectedName)'))
        self.assertLess(case.index('value == %@'), case.index('review.tap()'))
        self.assertLess(case.index('XCTAssertEqual(reviewedName.label, expectedName)'), case.index('confirm.tap()'))
        self.assertIn('Not sent. Submission is disabled or review expired.', case)
        self.assertIn('XCTAssertFalse(confirm.exists', case)
        self.assertIn('grants: .init(reads: grant)', self.text('App/PublisherLifecycleFixtureSupport.swift'))
        self.assertNotIn('creatorApplication: grant', self.text('App/PublisherLifecycleFixtureSupport.swift'))

    def test_failure_capture_and_regressions_stay_enabled(self):
        for path in ['Tests/AppUITests/ClubManagementFlowTests.swift', 'Tests/AppUITests/PublisherLifecycleUITests.swift']:
            source = self.text(path)
            for token in ['continueAfterFailure = false', 'attachFailureScreenshot(self, app: app)', 'XCTAttachment(string: app.debugDescription)']:
                self.assertIn(token, source)
            for forbidden in ['XCTSkip', 'Thread.sleep', 'Task.sleep', 'hasKeyboardFocus', 'value(forKey:']:
                self.assertNotIn(forbidden, source)
        self.assertIn('testCancelledReviewCannotDispatchAfterAccountReplacementOrReturn', self.text('Tests/CoreTests/ClubManagementTests.swift'))
        self.assertIn('testCreatorExactReviewWithDormantDispatchNeverWrites', self.text('Tests/CoreTests/PublisherLifecycleTests.swift'))


if __name__ == '__main__':
    unittest.main()
