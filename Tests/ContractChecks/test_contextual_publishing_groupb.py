#!/usr/bin/env python3
"""Native-only contract checks. Apple execution is a separate gate."""
from pathlib import Path
import json, unittest
ROOT = Path(__file__).resolve().parents[2]
class ContextPublishingChecks(unittest.TestCase):
    def test_ai_is_contextual_and_optional(self):
        view = (ROOT/'App/PublishingModesViews.swift').read_text()
        self.assertIn('PublishingAIDraftSheet(client: makeAIDraft?()', view)
        self.assertIn('var makeAIDraft: (() -> any PublishingAIDraftServing)? = nil', view)
        self.assertIn('draft = value; draftID = UUID()', view)
    def test_current_source_request_and_cancel(self):
        flow = (ROOT/'Core/PublishingAIDraftFlow.swift').read_text()
        self.assertIn('client.session == openedSession', flow)
        self.assertIn('generation += 1', flow)
        self.assertIn('case .unknown: throw PublishModesError.uncertain', flow)
        contract = (ROOT/'Core/PublishingAuxiliaryService.swift').read_text()
        self.assertIn('"productType": .number(Decimal(product.rawValue))', contract)
    def test_mode_copy_and_current_result_handoff(self):
        flow = (ROOT/"Core/ProjectDraftModeCopy.swift").read_text()
        self.assertIn("source.owner != .merchant", flow)
        self.assertIn("pending.serverAcknowledged == true", flow)
        coordinator = (ROOT/"Core/ProjectEditCoordinator.swift").read_text()
        self.assertIn("isolatedOwner != session", coordinator)
        self.assertIn("coordinator.isolatedDraftIdentity = try ProjectEditDraftIdentity()", coordinator)
        view = (ROOT/"App/ProjectEditView.swift").read_text()
        self.assertIn("ProjectEditModeReviewSheet(controller: modeReview", view)
        mode = (ROOT/"App/ProjectEditModeReviewController.swift").read_text()
        self.assertIn("PublishingModePickerSheet(current: picker.product)", mode)
        self.assertIn("copyForMode(original.draft, to: original.product)", mode)
        self.assertIn("PublishingSubmissionResultSheet(receipt:", view)
    def test_complete_bilingual_delta(self):
        fragment = json.loads((ROOT/'Resources/ContextPublishingLocalizations.fragment.json').read_text())
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())
        for key, value in fragment['strings'].items():
            self.assertEqual(value, catalog['strings'][key])
            self.assertEqual(set(value['localizations']), {'en','zh-Hans'})
if __name__ == '__main__': unittest.main()
