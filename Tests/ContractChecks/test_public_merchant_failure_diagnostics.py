from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PublicMerchantFailureDiagnostics(unittest.TestCase):
    def test_report_reveals_existing_exact_review_before_original_assertion(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantHomeFlowTests.swift').read_text()
        block=s.split('func testReportRequiresReviewThenReturnsModerationReceipt',1)[1].split('func testFeaturedActivity',1)[0]
        self.assertLess(block.index('revealFixtureElement(app.staticTexts["Fixture review"]'),block.index('app.staticTexts["Fixture review"].waitForExistence'))
        for value in ['PENDING_PLATFORM_REVIEW','merchant.publicHome.confirm','merchant.publicHome.unknown','merchant.publicHome.writeFailure']:
            self.assertIn(value,block)
    def test_failure_only_fixture_snapshot_has_allowlist_and_limits(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantHomeFlowTests.swift').read_text()
        block=s.split('override func tearDownWithError',1)[1].split('private func reveal',1)[0]
        for text in ['totalFailureCount ?? 0) > 0','--public-merchant-home-fixture','attachFailureScreenshot','prefix(65_536)','prefix(48)','prefix(1024)','knownLabels','XCTAttachment']:
            self.assertIn(text,block)
        self.assertEqual(block.count('app.debugDescription'),1)
        self.assertNotIn('app.terminate()',block)
    def test_unresolved_retry_and_new_scope_assertions_are_not_changed(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantHomeFlowTests.swift').read_text()
        self.assertIn('XCTAssertTrue(app.staticTexts["Synthetic activity 602"].waitForExistence(timeout: 5))',s)
        self.assertIn('XCTAssertFalse(app.staticTexts["Synthetic activity 601"].exists)',s)
        self.assertIn('XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))',s)
