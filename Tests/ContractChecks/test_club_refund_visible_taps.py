"""Source guards; these do not replace exact-build Apple UI execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ClubRefundVisibleTapChecks(unittest.TestCase):
    def test_shared_viewport_reveal_precedes_single_tap(self):
        source = (ROOT / 'Tests/AppUITests/ClubOwnerRefundFlowTests.swift').read_text()
        helper = source.split('private func tap(', 1)[1].split('\n    func test', 1)[0]
        def check(text):
            self.assertIn('revealFixtureElement(button, in: app)', text)
            self.assertLess(text.index('revealFixtureElement'), text.index('button.tap()'))
            self.assertEqual(text.count('button.tap()'), 1)
            self.assertNotIn('app.swipeUp()', text)
            self.assertIn('XCTAssertTrue(button.isHittable', text)
            self.assertIn('XCTAssertTrue(button.isEnabled', text)
        check(helper)
        with self.assertRaises(AssertionError):
            check(helper.replace('revealFixtureElement(button, in: app)', 'button.isHittable'))
        self.assertIn('attachFailureScreenshot(self, app: runningApp)', source)
        self.assertIn('runningApp?.terminate()', source)

    def test_exact_fixture_controls_bypass_content_viewport(self):
        source = (ROOT / 'Tests/AppUITests/ClubOwnerRefundFlowTests.swift').read_text()
        helper = source.split('private func tap(', 1)[1].split('\n    func test', 1)[0]
        self.assertIn('id == "club.refund.fixtureRecord" || id == "club.refund.fixtureSwitch"', helper)
        self.assertIn(': app.buttons[id]', helper)
        self.assertNotIn('app.toolbars.buttons', helper)
        self.assertIn('app.buttons.matching(identifier: id).count, 1', helper)
        self.assertIn('appFrame.contains(frame)', helper)
        self.assertIn('!$0.intersects(frame)', helper)
        self.assertIn('!frame.isEmpty, !frame.isNull, !frame.isInfinite', helper)
        self.assertIn('id == "club.refund.cancel"', helper)
        self.assertIn('isNavigationControl ? app.navigationBars.buttons[id]', helper)
        toolbar_branch, content_branch = helper.split('if isFixtureControl || isNavigationControl {', 1)[1].split('} else {', 1)
        self.assertIn('button.waitForExistence(timeout: 5)', toolbar_branch)
        self.assertNotIn('revealFixtureElement', toolbar_branch)
        self.assertIn('revealFixtureElement(button, in: app)', content_branch)

    def test_debug_footer_reserves_space_without_shrinking_product(self):
        source = (ROOT / 'App/ClubOwnerRefundFixtureView.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('.safeAreaInset(edge: .bottom)', source)
        self.assertIn('VStack(spacing: 8)', source)
        self.assertNotIn('ToolbarItemGroup', source)
        self.assertNotIn('dynamicTypeSize', source)
        self.assertNotIn('minimumScaleFactor', source)
        self.assertIn('access.markRefundRecorded()', source)
        self.assertIn('access.governance.readFailure = .forbidden', source)

    def test_unknown_readback_keeps_both_reads_and_distinct_receipt_assertion(self):
        source = (ROOT / 'Tests/AppUITests/ClubOwnerRefundFlowTests.swift').read_text()
        case = source.split('func testUnknownReadbackNeverResubmitsAndRefundRecordRemainsDistinct()', 1)[1].split('\n    func ', 1)[0]
        self.assertEqual(case.count('tap("club.refund.readback", app)'), 2)
        for assertion in [
            'XCTAssertFalse(app.buttons["club.refund.review"].exists)',
            'tap("club.refund.fixtureRecord", app)',
            'XCTAssertTrue(app.staticTexts["club.refund.phase"].waitForExistence(timeout: 5))',
            'XCTAssertFalse(app.descendants(matching: .any)["club.refund.receipt"].firstMatch.exists)',
        ]:
            self.assertIn(assertion, case)
