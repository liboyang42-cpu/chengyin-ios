"""Test-only viewport/acknowledgement guard; Apple lost-tap causality remains unproven."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class TeamCreateReviewNavigationChecks(unittest.TestCase):
    def case(self):
        s = (ROOT/'Tests/AppUITests/TeamFlowTests.swift').read_text()
        return s.split('func testCreatePrivateTeamReviewCancelPreservesForm()', 1)[1].split('\n    func ', 1)[0]

    def test_viewport_precedes_one_tap_and_review_arrival(self):
        s = self.case()
        helper = s.split('func openCreationReview()', 1)[1].split('guard openCreationReview()', 1)[0]
        self.assertLess(helper.index('revealFixtureElement(review, in: app)'), helper.index('review.tap()'))
        self.assertLess(helper.index('review.tap()'), helper.index('reviewBar.waitForExistence(timeout: 5)'))
        self.assertEqual(helper.count('review.tap()'), 1)
        self.assertNotIn('for ', helper)
        self.assertEqual(helper.count('XCTFail(app.debugDescription); return false'), 2)
        self.assertEqual(s.count('guard openCreationReview() else { return }'), 2)

    def test_cancel_form_and_second_review_simulation_checks_remain(self):
        s = self.case()
        for token in ['NSPredicate(format: "value == %@", "1")', 'cancel.tap()',
                      'XCTAssertEqual(toggle.value as? String, "1")', 'confirm.tap()', 'assertSimulationCompleted()',
                      'revealFixtureElement(cancel, in: app)', 'revealFixtureElement(confirm, in: app)']:
            self.assertIn(token, s)
        self.assertLess(s.index('cancel.tap()'), s.index('XCTWaiter.wait(for: [dismissed], timeout: 5)'))
        self.assertLess(s.index('XCTWaiter.wait(for: [dismissed], timeout: 5)'), s.index('XCTAssertEqual(toggle.value as? String, "1")'))
        for token in ['let reviewBar = app.navigationBars["Review team change"]',
                      'NSPredicate(format: "exists == false"), object: reviewBar',
                      'XCTAssertTrue(cancel.isEnabled', 'XCTAssertTrue(cancel.isHittable',
                      'XCTAssertTrue(confirm.isEnabled', 'XCTAssertTrue(confirm.isHittable']:
            self.assertIn(token, s)
        self.assertNotIn('XCTSkip', s)
