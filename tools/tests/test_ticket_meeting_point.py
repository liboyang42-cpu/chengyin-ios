"""Static ticket meeting-point contracts; not Swift compilation/runtime evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

class TicketMeetingPointContracts(unittest.TestCase):
    def test_existing_ticket_and_frozen_review_mount_same_projection(self):
        forms = read('App/ProjectEditDetailForms.swift')
        self.assertEqual(forms.count('ProjectTicketMeetingPointFields(model: model, ticketID: ticketID)'), 1)
        self.assertEqual(forms.count('ProjectTicketMeetingPointSummary(ticket: ticket)'), 1)
        ticket = forms.split('@MainActor struct ProjectEditTicketView: View {', 1)[1].split('struct ProjectEditReviewView:', 1)[0]
        self.assertIn('if model.draft.product == .city {\n                    ProjectTicketMeetingPointFields', ticket)
        self.assertNotIn('text: ticket.meetingPoint', ticket)

    def test_decode_and_wire_are_number_aware_without_arbitrary_metadata_copy(self):
        contract = read('Core/ProjectEditContract.swift')
        self.assertIn('p.merge(try ProjectTicketMeetingPoint.wireFields(ticket))', contract)
        for key in ('gatherLng', 'gatherLat'):
            self.assertIn(f'ProjectTicketMeetingPoint.coordinateText("", original: source["{key}"])', contract)
        core = read('Core/ProjectTicketMeetingPoint.swift')
        self.assertIn('result[key] = .number(coordinate)', core)
        self.assertNotIn('result.merge(ticket.localMetadata', core)
        self.assertLess(contract.index('if scope == .whitelist'), contract.index('ProjectTicketMeetingPoint.wireFields(ticket)'))

    def test_unknown_source_types_are_readonly_and_full_validation_blocks(self):
        core = read('Core/ProjectTicketMeetingPoint.swift')
        self.assertIn('case .string where key == "meetingPoint" || key == "meetingPointAddress"', core)
        self.assertIn('case .number where key == "gatherLng" || key == "gatherLat"', core)
        self.assertIn('default: return false', core)
        self.assertIn('guard supportsEditing(ticket), value.hasValidCoordinates', core)
        validation = read('Core/ProjectEditDraft.swift')
        self.assertLess(validation.index('guard scope == .full'), validation.index('ProjectTicketMeetingPoint.wireFields(ticket)'))
        self.assertIn('"projectTicketMeetingPoint.invalidStored"', validation)

    def test_coordinate_pair_bounds_zero_and_null_are_explicit(self):
        core = read('Core/ProjectTicketMeetingPoint.swift')
        for text in ('x.isEmpty && y.isEmpty', 'coordinate(x, limit: 180)', 'coordinate(y, limit: 90)',
                     '.doubleValue.isFinite', 'number >= Decimal(-limit)', 'number <= Decimal(limit)',
                     'ticket.localMetadata[key] == .null'):
            self.assertIn(text, core)
        self.assertNotIn('number != 0', core)
        self.assertNotIn('Double(value)', core)

    def test_controller_captures_exact_draft_and_identity(self):
        ui = read('App/ProjectTicketMeetingPointFields.swift')
        for text in ('value.controllerID == controllerID', 'value.generation == generation',
                     'model.isCurrentStarterLease(value.lease)', 'model.draftMutationRevision == value.revision',
                     'ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes',
                     'filter({ $0.id == ticketID }).count == 1', 'model.draft.product == .city',
                     'self.model === model && self.ticketID == ticketID'):
            self.assertIn(text, ui)

    def test_apply_cancel_noop_and_stale_dismissal_have_no_storage_or_remote_path(self):
        ui = read('App/ProjectTicketMeetingPointFields.swift')
        for text in ('guard isCurrent(original)', 'next.tickets[index] = nextTicket',
                     'ProjectEditPendingMaterials.exactData(next) != original.capture.draftBytes',
                     'guard presentation?.id == value.id', '.onDisappear { controller.retire() }'):
            self.assertIn(text, ui)
        for text in ('persistLocalChange(', 'saveLocal(', 'URLRequest', 'CLLocationManager', 'MKMapView', '.submit(', 'suspendLocalWritesAfterChapterRemoval('):
            self.assertNotIn(text, ui)

    def test_bilingual_localizations_cover_all_new_references_and_label_datum(self):
        catalog = json.loads(read('Resources/ProjectTicketMeetingPointLocalizations.fragment.json'))['strings']
        references = set(re.findall(r'"(projectTicketMeetingPoint\.[a-zA-Z]+)"',
            read('App/ProjectTicketMeetingPointFields.swift') + read('Core/ProjectEditDraft.swift')))
        # Accessibility identifiers share the namespace but do not require catalog entries.
        references -= {'cancel', 'summary'}
        references -= {'projectTicketMeetingPoint.cancel', 'projectTicketMeetingPoint.summary', 'projectTicketMeetingPoint.longitude', 'projectTicketMeetingPoint.latitude'}
        self.assertTrue(references.issubset(catalog), sorted(references - catalog.keys()))
        for key, value in catalog.items():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}, key)
            for translation in value['localizations'].values():
                self.assertTrue(translation['stringUnit']['value'])
        for lang in ('en', 'zh-Hans'):
            self.assertIn('GCJ-02', catalog['projectTicketMeetingPoint.datum']['localizations'][lang]['stringUnit']['value'])

    def test_authored_behavior_and_race_coverage_is_present(self):
        core = read('Tests/CoreTests/ProjectTicketMeetingPointTests.swift')
        app = read('Tests/AppUnitTests/ProjectTicketMeetingPointTests.swift')
        self.assertGreaterEqual(len(re.findall(r'func test', core)), 10)
        self.assertGreaterEqual(len(re.findall(r'func test', app)), 9)
        for text in ('testExplicitClearUsesNull', 'testUnsupportedOriginalTypes', 'testAuthoritativeDecodeAndFullPayload',
                     'testInvalidImportedCoordinateBlocksFullButNotWhitelist'):
            self.assertIn(text, core)
        for text in ('testAccountEpochLogoutRestoreDiscardVisitAndMode', 'testUnconfirmedChapterRemovalFreeze',
                     'testUnknownSubmissionLocks', 'testWrongControllerReplacementHost', 'testOpenCancelAndNoOp',
                     'testApplyChangesOnlyCapturedTicketThenExistingSaveColdRestore'):
            self.assertIn(text, app)

if __name__ == '__main__':
    unittest.main()
