"""Source guards only. Exact-commit Apple UI execution remains required."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MarketingLargeTypeRevealChecks(unittest.TestCase):
    def case(self):
        source = (ROOT / 'Tests/AppUITests/MerchantMarketingUITests.swift').read_text()
        return source.split('func testPredictionReviewLargeTextKeepsFixtureControlsClearOfOptions()', 1)[1].split('\n    func ', 1)[0]

    def assert_reveal_order(self, case):
        ready = case.index('form.waitForExistence(timeout: 5)')
        reveal = case.index('revealFixtureElement(option, in: app)')
        exists = case.index('XCTAssertTrue(option.exists')
        tap = case.index('option.tap()')
        self.assertLess(ready, reveal)
        self.assertLess(reveal, exists)
        self.assertLess(exists, tap)
        self.assertNotIn('option.waitForExistence', case[:reveal])

    def test_lazy_option_is_revealed_before_existence_is_required(self):
        case = self.case()
        self.assert_reveal_order(case)
        mutant = case.replace('XCTAssertTrue(revealFixtureElement(option, in: app)',
                              'XCTAssertTrue(option.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(option, in: app)', 1)
        with self.assertRaises(AssertionError):
            self.assert_reveal_order(mutant)

    def test_large_type_geometry_acknowledgment_and_cancel_checks_remain(self):
        case = self.case()
        for token in [
            'noticeIdentifier: "merchantMarketing.synthetic", colorScheme: "dark", dynamicTypeSize: "accessibility3"',
            'XCTAssertTrue(signOut.isHittable)',
            'XCTAssertFalse(option.frame.intersects(signOut.frame))',
            'XCTAssertFalse(option.frame.intersects(count.frame))',
            'XCTAssertTrue(option.isEnabled)',
            'XCTAssertFalse(confirm.isEnabled)',
            'cancel.tap()',
            'XCTWaiter.wait(for: [dismissed], timeout: 5)',
            'waitForLabel(count, "0")',
        ]:
            self.assertIn(token, case)
        self.assertNotIn('XCTSkip', case)
