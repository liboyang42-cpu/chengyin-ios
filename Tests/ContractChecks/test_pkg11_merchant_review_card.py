import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Pkg11MerchantReviewCardContracts(unittest.TestCase):
    def read(self, rel: str) -> str:
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_presentation_model_maps_visibility_and_reply_states_conservatively_via_localization_keys(self):
        core = self.read("Core/MerchantReviewCardPresentation.swift")
        self.assertIn("public struct MerchantReviewCardPresentation: Equatable", core)
        self.assertIn('public static let localizationTableName = "MerchantReviewAndCustomerDetail"', core)
        self.assertIn("guard row.kind == .review else { return nil }", core)
        self.assertIn('case "VISIBLE": visibility = .publicVisible', core)
        self.assertIn('case "PENDING_REVIEW": visibility = .pendingReview', core)
        self.assertIn('case "HIDDEN": visibility = .hidden', core)
        self.assertIn("default: visibility = .unknown", core)
        self.assertIn('public var titleKey: String { "merchant.review.visibility." + rawValue }', core)
        self.assertIn('public var titleKey: String { "merchant.review.reply." + rawValue }', core)
        for hardcoded in ["公开展示", "审核中（暂未公开）", "已隐藏（未公开）", "可见性未知（不按公开处理）", "已回复", "待回复", "不可回复"]:
            self.assertNotIn(hardcoded, core)
        for forbidden in ["URLSession", "https://", "http://", "api/merchant/"]:
            self.assertNotIn(forbidden, core)

    def test_review_card_view_uses_localization_table_and_host_wiring_keeps_existing_reply_flow(self):
        card = self.read("App/MerchantReviewCard.swift")
        self.assertIn("struct MerchantReviewCard: View", card)
        self.assertIn("tableName: MerchantReviewCardPresentation.localizationTableName", card)
        self.assertNotIn("已核销用户", card)
        self.assertNotIn("张图", card)
        self.assertIn('.accessibilityIdentifier("merchant.business.review.visibility")', card)
        self.assertIn('.accessibilityIdentifier("merchant.business.review.replyState")', card)
        views = self.read("App/MerchantBusinessViews.swift")
        self.assertIn("if let card = MerchantReviewCardPresentation(row: row) { MerchantReviewCard(presentation: card) }", views)
        self.assertIn("sourcePageMatches", views)
        self.assertIn("draftReturn.capture(review)", views)

        catalog = json.loads(self.read("Resources/MerchantReviewAndCustomerDetail.xcstrings"))["strings"]
        for key in [
            "merchant.review.visibility.publicVisible",
            "merchant.review.visibility.pendingReview",
            "merchant.review.visibility.hidden",
            "merchant.review.visibility.unknown",
            "merchant.review.reply.replied",
            "merchant.review.reply.awaitingReply",
            "merchant.review.reply.noReplyAvailable",
            "merchant.review.verifiedRedemption",
            "merchant.review.photoCount %lld",
        ]:
            self.assertIn(key, catalog)
            self.assertEqual(set(catalog[key]["localizations"].keys()), {"en", "zh-Hans"})


if __name__ == "__main__":
    unittest.main()
