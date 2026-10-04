"""Structural contracts only; Swift/Apple behavior requires its own execution."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class TicketThemeSync(unittest.TestCase):
    def test_visible_free_only_toggle_and_manual_fallback(self):
        ui = (ROOT/'App/ProjectEditDetailForms.swift').read_text()
        self.assertIn('if model.draft.product == .freeExplore {\n                    Toggle("projectEdit.syncThemeDates", isOn: model.ticketDateSync(ticketID))', ui)
        self.assertIn('.disabled(!ticket.wrappedValue.canEditThemeDateSync)', ui)
        self.assertIn('value: ticket.startTime', ui)
        self.assertIn('ticket.schedule(in: confirmation.draft)', ui)
    def test_validation_payload_review_use_same_effective_dates_with_stored_flag(self):
        draft = (ROOT/'Core/ProjectEditDraft.swift').read_text()
        contract = (ROOT/'Core/ProjectEditContract.swift').read_text()
        for text in ['let schedule = ticket.schedule(in: draft)', 'dateTime(schedule.start)', 'dateTime(schedule.end, endOfDay: true)']:
            self.assertIn(text, draft); self.assertIn(text, contract)
        self.assertIn('if let sync = ticket.localMetadata["syncWithTheme"] { p["syncWithTheme"] = sync }', contract)
        self.assertIn('draft.product == .freeExplore && syncsWithThemeDates', draft)
    def test_legacy_unknown_and_session_guards(self):
        draft = (ROOT/'Core/ProjectEditDraft.swift').read_text()
        model = (ROOT/'App/ProjectEditView.swift').read_text()
        self.assertIn('if case .bool = raw { return true }', draft)
        self.assertIn('guard draft.product == .freeExplore, canEditThemeDateSync', draft)
        self.assertIn('guard self.fullEdit, let index = self.draft.tickets.firstIndex', model)
        self.assertIn('loadedSession == coordinator.session', model)
        self.assertIn('!coordinator.isLocked', model)
        self.assertIn('confirmation = nil; coordinator.cancelReview()', model)
    def test_bilingual_catalog_agrees(self):
        catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        source=json.loads((ROOT/'docs/project-edit-localizations.json').read_text())
        for suffix in ['syncThemeDates','syncThemeDatesHint','syncThemeDatesLegacy']:
            key='projectEdit.'+suffix
            for lang in ['en','zh-Hans']:
                self.assertEqual(source[key][lang],catalog[key]['localizations'][lang]['stringUnit']['value'])
