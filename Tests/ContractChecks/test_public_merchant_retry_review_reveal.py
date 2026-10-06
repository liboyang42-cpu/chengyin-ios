"""Lazy review body must be revealed without weakening the exact returned-content assertion."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PublicMerchantRetryReviewRevealChecks(unittest.TestCase):
    def test_retry_keeps_single_taps_and_exact_body_check_after_reveal(self):
        source = (ROOT / 'Tests/AppUITests/PublicMerchantHomeFlowTests.swift').read_text()
        body = source.split('func testRetryRecoversAndReviewsUseBothReturnedIDs() {', 1)[1].split('\n    }', 1)[0]
        self.assertEqual(body.count('retry.tap()'), 1)
        self.assertEqual(body.count('reviews.tap()'), 1)
        self.assertIn('XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))', body)
        reveal = 'XCTAssertTrue(revealFixtureElement(app.staticTexts["Fixture review"], in: app), app.debugDescription)'
        exact = 'XCTAssertTrue(app.staticTexts["Fixture review"].waitForExistence(timeout: 5))'
        self.assertEqual(body.count(reveal), 1)
        self.assertLess(body.index(reveal), body.index(exact))
        self.assertNotIn('coordinate(', body)
