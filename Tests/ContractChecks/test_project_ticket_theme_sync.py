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

class TicketThemeSyncUIInteractionContracts(unittest.TestCase):
    def test_native_control_transition_precedes_exact_combined_date_labels(self):
        source = (ROOT / 'Tests/AppUITests/ProjectEditFlowTests.swift').read_text()
        method = source.split('func testFreeExploreTicketThemeDateSyncAndReturnToManualDates()')[1].split('func testLocalEditReviewAndCancelledConfirmation')[0]
        self.assertIn('let nativeSwitch = sync.switches.firstMatch', method)
        self.assertEqual(method.count('if nativeSwitch.exists { nativeSwitch.tap() }'), 2)
        self.assertEqual(method.count('CGVector(dx: 0.93, dy: 0.5)'), 2)
        self.assertNotIn('sync.tap()', method)
        self.assertNotIn('while ', method)
        self.assertNotIn('for ', method)
        self.assertIn('NSPredicate(format: "value == %@", "1")', method)
        self.assertIn('NSPredicate(format: "value == %@", "0")', method)
        self.assertLess(method.index('XCTWaiter.wait(for: [enabled], timeout: 3)'), method.index('XCTAssertEqual(syncedStart.label, "Start or meeting time, 2030-05-01 00:00:00"'))
        self.assertIn('let syncedStart = app.staticTexts["projectEdit.ticketStart"]', method)
        self.assertIn('let syncedEnd = app.staticTexts["projectEdit.ticketEnd"]', method)
        self.assertIn('XCTAssertTrue(syncedStart.waitForExistence(timeout: 3)', method)
        self.assertIn('XCTAssertTrue(syncedEnd.exists', method)
        self.assertIn('XCTAssertEqual(syncedEnd.label, "End time, 2030-05-30 23:59:59"', method)
        self.assertNotIn('label.contains', method)
        self.assertIn('XCTAssertFalse(app.textFields["projectEdit.ticketStart"].exists)', method)
        self.assertIn('XCTAssertEqual(app.textFields["projectEdit.ticketStart"].value as? String, "2030-05-01 00:00:00")', method)
        self.assertIn('app.buttons["projectEdit.review"].tap()', method)
        self.assertIn('app.buttons["projectEdit.cancelReview"]', method)
