"""Keep exact cancel outcomes and useful runtime diagnostics; Apple CI executes them."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class MerchantReviewDismissalTests(unittest.TestCase):
    def test_cancel_waits_for_both_controls_to_disappear_without_success(self):
        text = (ROOT / "Tests/AppUITests/MerchantEngagementFlowTests.swift").read_text()
        for value in ['XCTWaiter.wait(for: [dismissed], timeout: 5)', '!app.buttons["merchant.engagement.confirm"].exists', '!app.buttons["merchant.engagement.cancelReview"].exists', 'attachFailureScreenshot(self, app: currentApp)', 'XCTAttachment(string: app.debugDescription)', 'Chinese CRM review canceled without receipt']:
            self.assertIn(value, text)
        self.assertEqual(text.count('func testChineseOrdinaryHTTPProductionReviewCanBeCancelled'), 1)
        self.assertIn('continueAfterFailure = false', text)
if __name__ == "__main__": unittest.main()
