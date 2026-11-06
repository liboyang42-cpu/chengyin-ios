"""Bounded cancellation readback source contracts, not native execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def span(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class ClubOccurrenceCancellationReturnContracts(unittest.TestCase):
    def setUp(self):
        self.editor = (ROOT / 'App/ClubSeriesScheduleEditor.swift').read_text()
        self.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        self.host = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.owner = span(self.editor, '@MainActor final class ClubOccurrenceCancellationReturn:', '@MainActor struct ClubOccurrenceCancellationPresentationOwner:')
        self.presenter = span(self.editor, '@MainActor struct ClubOccurrenceCancellationPresentationOwner:', '/// A navigation proof,')

    def test_only_existing_occurrence_entry_uses_callback(self):
        self.assertIn('else if operation == .cancelOccurrence, self.operation == .occurrenceStatus', self.host)
        self.assertIn('if route.operation == .cancelOccurrence, let occurrenceCancellationReturn', self.form)
        self.assertIn('route: .init(operation: .cancelOccurrence, scope: source.context.scope)', self.owner)
        self.assertIn('value["activityCancelled"] == .bool(false), occurrenceCancellationReturn.readback == nil', self.host)

    def test_source_is_exact_active_occurrence_and_authorized_snapshot(self):
        for token in ['context.operation == .occurrenceStatus, context.accepts(snapshot)',
                      'snapshot.value["activityId"].int == context.scope.activityID',
                      'snapshot.value["occurrenceStatus"] == .string("ACTIVE")',
                      'snapshot.value["activityCancelled"] == .bool(false)',
                      'snapshot.value["publishStatus"] == .integer(1)',
                      'snapshot.permissions?.allows(ClubGovernanceRead.occurrenceStatus.permission',
                      'context.authorizationGeneration == access.authorizationGeneration']:
            self.assertIn(token, self.owner)

    def test_specific_review_and_ack_required(self):
        for token in ['state == .reviewing', 'review.command.operation == .cancelOccurrence',
                      'review.command.scope == expected.source.context.scope', 'review.snapshot == expected.source.snapshot',
                      'review.storageNamespace == expected.source.namespace', 'review.journalRealm == expected.source.realm',
                      'state == .acknowledged', 'submissionID == review.id',
                      'value["activityId"].int == expected.source.context.scope.activityID', 'value["refundStatus"].string != nil']:
            self.assertIn(token, self.owner)

    def test_ack_and_lock_assignment_precedes_optional_return(self):
        a = self.form.index('receipt = value; self.review = nil; locked = true')
        b = self.form.index('occurrenceCancellationReturn?.acknowledged(review, value)')
        self.assertLess(a, b)
        self.assertIn('if route.operation == .cancelOccurrence, submittedRequestID == draft.requestID, !Task.isCancelled', self.form)
        self.assertNotIn('send(', self.owner)
        self.assertNotIn('unlock', self.owner)
        self.assertNotIn('sleep', self.owner)

    def test_dismiss_and_visible_consumption_are_once_only(self):
        for token in ['active && item?.id == expected.id && expected.source == source',
                      'guard visible, active, !isPresented, didDismiss, readback == nil',
                      'readback = acknowledged; confirmed = false; retireForm()',
                      'if acknowledged != nil { didDismiss = true } else { retireForm() }']:
            self.assertIn(token, self.owner)
        self.assertIn('occurrenceCancellationReturn.item?.id == item.id', self.host)
        self.assertIn('!Task.isCancelled, seriesHostVisible, scenePhase == .active', self.host)

    def test_current_uuid_sheet_belongs_to_stable_parent(self):
        self.assertIn('@StateObject private var occurrenceCancellationReturn', self.host)
        self.assertIn('.sheet(isPresented: owner.binding(item, source: source, active: active)', self.presenter)
        self.assertIn('if owner.dismissed(item, source: source(), active: active()) { didDismiss() }', self.presenter)
        self.assertIn('didDismiss: finishOccurrenceCancellationReturn)\n                    .id(item.id)', self.host)

    def test_readback_proof_binds_review_owner_context_and_visibility(self):
        current = span(self.owner, 'func readIsCurrent(', '@discardableResult func observe(')
        for token in ['visible && active', 'readback?.id == expected.id',
                      'readback?.reviewID == expected.reviewID', 'expected.source.live(context: context, access: access)']:
            self.assertIn(token, current)
        load = span(self.host, '@MainActor private func load() async', '@MainActor private func invalidateRead()')
        self.assertIn('let cancellationTicket = occurrenceCancellationReturn.readback', load)
        self.assertIn('guard cancellationCurrent() else { return }', load)
        self.assertEqual(load.count('guard cancellationCurrent(), revision == generation'), 3)
        self.assertIn('occurrenceCancellationReturn.observe(result, for: cancellationTicket', load)

    def test_only_independent_cancelled_consistency_confirms(self):
        observe = span(self.owner, '@discardableResult func observe(', 'func invalidateForm(')
        for token in ['result.value["activityId"].int == expected.source.context.scope.activityID',
                      'result.value["occurrenceStatus"] == .string("CANCELLED")',
                      'result.value["activityCancelled"] == .bool(true)', 'result.value["publishStatus"] == .integer(0)']:
            self.assertIn(token, observe)
        self.assertNotIn('refundStatus', observe)
        self.assertLess(observe.index('readIsCurrent('), observe.index('confirmed = false'))

    def test_unconfirmed_state_and_refund_progress_remain_distinct(self):
        self.assertIn('if !occurrenceCancellationReturn.confirmed', self.host)
        self.assertIn('Text("club.gov.unknown").accessibilityIdentifier("club.cancel.readback.unconfirmed")', self.host)
        self.assertIn('ClubGovernanceFactRows(value: readback.receipt, fields: ["refundStatus"])', self.host)
        self.assertIn('if let status = value["occurrenceStatus"].string', self.host)
        self.assertIn('LabeledContent("club.gov.field.status") { Text(verbatim: status) }', self.host)

    def test_occurrence_reads_have_one_visibility_aware_task_owner(self):
        self.assertIn('if operation == .occurrenceStatus { return }', self.host)
        self.assertIn('guard operation == .occurrenceStatus, seriesHostVisible, scenePhase == .active else { return }', self.host)
        self.assertIn('item.source.live(context: readContext, access: access) { return }', self.host)
        self.assertIn('if operation != .occurrenceStatus || occurrenceCancellationReturn.item == nil', self.host)
        self.assertIn('if phase != .active { occurrenceCancellationReturn.retire() }', self.host)

    def test_new_native_negatives_cover_unknown_and_late_reads_without_retire(self):
        tests = (ROOT / 'Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift').read_text()
        for name in ['testUnknownAckCannotReturnReadbackOrUnlock', 'testBothDismissAndAppearOrdersConsumeOnlyOnceWhenVisible',
                     'testHiddenDuringHeldStatusReadCannotConsumeLateResponseWithoutRetire',
                     'testIdentityAuthorizationAndOldReadbackCannotAffectNewOwner',
                     'testReadFailureRetainsPendingReceiptAndOriginalPermanentLock']:
            self.assertIn('func '+name+'(', tests)

    def test_financial_confirmation_and_other_return_paths_still_exist(self):
        self.assertIn('seriesCreationReturn?.acknowledged(review, value)', self.form)
        self.assertIn('seriesUpdateReturn?.acknowledged(review, value)', self.form)
        self.assertIn('coordinator.confirm(review)', self.form)
        core = (ROOT / 'Core/ClubGovernanceCommands.swift').read_text()
        self.assertIn('case .cancelOccurrence, .endTopic, .reportHours, .submitEvidence, .dissolve: return .financial', core)


if __name__ == '__main__':
    unittest.main()
