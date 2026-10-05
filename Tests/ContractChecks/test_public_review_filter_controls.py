from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PublicReviewFilterControls(unittest.TestCase):
    def test_thumbnail_hit_shape_is_explicit_while_media_stays_disabled_by_default(self):
        s=(ROOT/'App/RetainedPublicReviewImages.swift').read_text()
        for text in ['Button { selected = raw }', '.frame(maxWidth: .infinity, minHeight: 88)', '.contentShape(Rectangle())', '.buttonStyle(.plain)',
                     '.accessibilityIdentifier("image.retained.reviewPhoto.\\(index)")','guard reader.enabled, let url = URL(string: raw) else { return }',
                     '.onDisappear { selected = nil }']:
            self.assertIn(text,s)
        self.assertNotIn('URLSession',s)
        self.assertNotIn('enabled: true',s)
    def test_summary_values_remain_exact_and_are_not_confused_with_filtered_count(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantReviewFilterFlowTests.swift').read_text()
        self.assertIn('app.staticTexts["merchant.publicHome.total"]',s)
        self.assertIn('total.label, "Reviews, 22"',s)
        self.assertIn('rating.label, "Rating, 4.7"',s)
        self.assertIn('waitForReads(2, completed: 2, in: app)',s)
    def test_large_text_select_reveals_lazy_picker_before_required_existence(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantReviewFilterFlowTests.swift').read_text()
        block=s.split('private func select',1)[1].split('private func waitForReads',1)[0]
        self.assertLess(block.index('reveal(picker, in: app)'),block.index('picker.waitForExistence'))
        self.assertIn('XCTAssertFalse(app.buttons["Awaiting reply"].exists)',block)
    def test_photo_and_identity_journeys_keep_no_write_and_old_401_checks(self):
        s=(ROOT/'Tests/AppUITests/PublicMerchantReviewFilterFlowTests.swift').read_text()
        for text in ['waitForReads(1, completed: 1, in: app)','waitForReads(3, completed: 3, account: 9, in: app)',
                     'XCTAssertFalse(app.buttons["merchant.publicHome.retry"].exists)',
                     'XCTAssertFalse(app.staticTexts["merchant.publicHome.review.2"].exists)',
                     'XCTAssertFalse(app.buttons["merchant.publicHome.createReview"].exists)',
                     'XCTAssertFalse(app.buttons["merchant.publicHome.report.3"].exists)']:
            self.assertIn(text,s)
