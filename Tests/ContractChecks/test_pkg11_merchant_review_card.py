from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Pkg11MerchantReviewCardContracts(unittest.TestCase):
    def read(self, rel: str) -> str:
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_presentation_model_maps_visibility_and_reply_states_conservatively(self):
        core = self.read("Core/MerchantReviewCardPresentation.swift")
        self.assertIn("public struct MerchantReviewCardPresentation: Equatable", core)
        self.assertIn("guard row.kind == .review else { return nil }", core)
        self.assertIn('case "VISIBLE": visibility = .publicVisible', core)
        self.assertIn('case "PENDING_REVIEW": visibility = .pendingReview', core)
        self.assertIn('case "HIDDEN": visibility = .hidden', core)
        self.assertIn("default: visibility = .unknown", core)
        self.assertIn('case .unknown: return "可见性未知（不按公开处理）"', core)
        for forbidden in ["URLSession", "https://", "http://", "api/merchant/"]:
            self.assertNotIn(forbidden, core)

    def test_review_card_view_and_host_wiring_keep_existing_reply_flow(self):
        card = self.read("App/MerchantReviewCard.swift")
        self.assertIn("struct MerchantReviewCard: View", card)
        self.assertIn('.accessibilityIdentifier("merchant.business.review.visibility")', card)
        self.assertIn('.accessibilityIdentifier("merchant.business.review.replyState")', card)
        views = self.read("App/MerchantBusinessViews.swift")
        self.assertIn("if let card = MerchantReviewCardPresentation(row: row) { MerchantReviewCard(presentation: card) }", views)
        self.assertIn("sourcePageMatches", views)
        self.assertIn("draftReturn.capture(review)", views)


if __name__ == "__main__":
    unittest.main()
