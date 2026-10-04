"""Source wiring checks only; no Swift or backend execution is claimed."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SaleDateWiring(unittest.TestCase):
    def test_existing_form_review_and_payload_are_connected(self):
        ui = (ROOT/'App/ProjectEditDetailForms.swift').read_text()
        for field in ['saleStartTime', 'saleEndTime']:
            self.assertIn('value: ticket.' + field, ui)
            self.assertIn('sale["' + field + '"]', ui)
        core = (ROOT/'Core/ProjectEditContract.swift').read_text()
        self.assertIn('p.merge(try ticket.saleTimePayloads())', core)
        self.assertLess(core.index('if scope == .whitelist'), core.index('ticket.saleTimePayloads()'))
    def test_legacy_and_strict_edit_boundary(self):
        core = (ROOT/'Core/ProjectEditDraft.swift').read_text()
        for text in ['if value == (original?.text ?? "")', 'result[key] = original', 'guard canEditSaleTime(end: end)', 'ProjectEditValidation.dateTime(value, endOfDay: end)', 'result[key] = .null']:
            self.assertIn(text, core)
    def test_existing_model_permission_guards_remain(self):
        model = (ROOT/'App/ProjectEditView.swift').read_text()
        self.assertIn('guard self.fullEdit, let i = self.draft.tickets.firstIndex', model)
        self.assertIn('loadedSession == coordinator.session', model)
        self.assertIn('confirmation = nil; coordinator.cancelReview()', model)
    def test_storage_only_copy_is_bilingual_and_matches_catalog_source(self):
        catalog = json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
        source = json.loads((ROOT/'docs/project-edit-localizations.json').read_text())
        for suffix in ['saleSchedule', 'saleStart', 'saleEnd', 'saleStoredOnly', 'saleLegacy']:
            key = 'projectEdit.' + suffix
            for language in ['en','zh-Hans']:
                self.assertEqual(catalog[key]['localizations'][language]['stringUnit']['value'], source[key][language])
        self.assertIn('do not currently control', source['projectEdit.saleStoredOnly']['en'])
