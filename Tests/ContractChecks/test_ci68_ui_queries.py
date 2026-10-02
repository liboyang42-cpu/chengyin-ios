from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class CI68QueryTests(unittest.TestCase):
    def test_observed_lazy_form_and_combined_labels_keep_exact_outcomes(self):
        template=(ROOT/'Tests/AppUITests/MerchantTemplateAssistFlowTests.swift').read_text()
        case=template.split('func testCancelReviewDoesNotFillAndReopenHasNoCandidate()')[1].split('func testPermissionError')[0]
        self.assertIn('revealFixtureElement(apply, in: app)',case)
        self.assertIn('XCTAssertTrue(apply.isEnabled)',case)
        self.assertNotIn('apply.tap()',case)
        self.assertIn('XCTAssertFalse(app.buttons["merchant.assist.apply"].exists)',case)
        report=(ROOT/'Tests/AppUITests/SquareReportFlowTests.swift').read_text()
        self.assertIn('element.staticTexts["Synthetic versioned community post"]',report)
        self.assertIn('if id != "social.post.actions" { element.tap(); return }',report)
        self.assertIn('"Server status, IN_REVIEW"',report)
        self.assertIn('wait(for: [readback], timeout: 5)',report)
if __name__=='__main__':unittest.main()
