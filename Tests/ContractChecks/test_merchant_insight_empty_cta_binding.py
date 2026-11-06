"""Static regression source only. Does not exercise SwiftUI or service permissions."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class InsightEmptyCTABindingTests(unittest.TestCase):
    def test_absent_destination_has_no_noop_button(self):
        text = (ROOT / "App/MerchantMarketingHomeSections.swift").read_text()
        self.assertIn("if let onCoopCenter,", text)
        self.assertIn("Button(action: onCoopCenter)", text)
        self.assertNotIn("onCoopCenter?()", text)
    def test_callback_passes_through_original_summary(self):
        text = (ROOT / "App/MerchantInsightAttributionSummary.swift").read_text()
        self.assertIn("onCoopCenter: (() -> Void)? = nil", text)
        self.assertIn("isEmpty: counts.isEmpty, onCoopCenter: onCoopCenter", text)
    def test_both_entries_reuse_original_identity_guard(self):
        text = (ROOT / "App/MerchantMarketingView.swift").read_text()
        self.assertIn("onCoopCenter: cooperationCenterAction(insight: insight)", text)
        self.assertIn("if let openCoopCenter = cooperationCenterAction(insight: insight)", text)
        helper = text.split("private func cooperationCenterAction", 1)[1].split("@ViewBuilder private func insightSections", 1)[0]
        for fence in ["loadedRecommendationOrigin", "recommendationOrigin", "model.service.scope == scope", "scenePhase == .active", "!model.busy", "model.failure == nil", "model.insight == insight"]:
            self.assertIn(fence, helper)
        self.assertIn("onSuggestion(.cooperationCenter(origin))", helper)
if __name__ == "__main__": unittest.main()
