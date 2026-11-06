"""Source wiring contracts; native model and presentation tests execute separately."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def part(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class ClubSeriesCreationReturnContracts(unittest.TestCase):
    def setUp(self):
        self.editor = (ROOT / 'App/ClubSeriesScheduleEditor.swift').read_text()
        self.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        self.views = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.quick = (ROOT / 'App/ClubSessionQuickStartView.swift').read_text()
        self.owner = part(self.editor, '@MainActor final class ClubSeriesCreationReturn:', '@MainActor struct ClubSeriesCreationPresentationOwner:')
        self.receipt = part(self.editor, 'struct ClubCreatedSeriesReceipt:', '@MainActor final class ClubSeriesCreationReturn:')

    def test_new_receipt_is_scoped_to_verified_principal_and_original_request_bytes(self):
        for value in ['review.command.operation == .createSeries', 'review.identity.accountID', 'principal > 0',
                      'value["clubId"].int == clubID', 'value["topicId"].int == topicID',
                      'value["createdByMemberId"].int == principal', 'submitted.utf8.elementsEqual(returned.utf8)',
                      '(1...9_007_199_254_740_991).contains(seriesID)']:
            self.assertIn(value, self.receipt)
        self.assertNotIn('trimmingCharacters', self.receipt)

    def test_incomplete_receipt_only_declines_navigation(self):
        ack = part(self.owner, 'func acknowledge(', '@discardableResult func dismissed(')
        self.assertIn('let matched = ClubCreatedSeriesReceipt(review: review, value: value) else { return }', ack)
        self.assertNotIn('throw', ack)
        self.assertNotIn('send(', self.owner)
        self.assertNotIn('unlock', self.owner)

    def test_exact_submission_and_authoritative_ack_are_both_required(self):
        begin = part(self.owner, 'func begin(', 'func acknowledge(')
        ack = part(self.owner, 'func acknowledge(', '@discardableResult func dismissed(')
        for value in ['state == .reviewing', 'review.command.scope == expected.source.scope',
                      'review.identity == expected.source.context.identity', 'review.authorizationGeneration == expected.source.context.authorizationGeneration',
                      'review.storageNamespace == expected.source.namespace', 'review.journalRealm == expected.source.realm']:
            self.assertIn(value, begin)
        for value in ['state == .acknowledged', 'submissionID == review.id', 'receipt == nil', 'current(expected, source: source, active: active)']:
            self.assertIn(value, ack)

    def test_return_waits_for_visible_current_dismissal_and_consumes_once(self):
        consume = part(self.owner, 'func consume(', 'func invalidateForm(')
        for value in ['visible, active, !isPresented, didDismiss', 'destination == nil',
                      'current(item, source: source, active: active)', 'destination = target; retireForm()']:
            self.assertIn(value, consume)
        self.assertIn('item?.id == expected.id', self.owner)

    def test_sheet_and_destination_use_concrete_uuid_owners(self):
        sheet = part(self.editor, '@MainActor struct ClubSeriesCreationPresentationOwner:', '@MainActor struct ClubCreatedSeriesDestinationOwner:')
        self.assertIn('owner.binding(item, source: source, active: active)', sheet)
        self.assertIn('if owner.dismissed(item, source: source(), active: active()) { didDismiss() }', sheet)
        self.assertIn('owner.destinationBinding(target, current: current)', self.editor)
        self.assertIn('guard !shown, self.destination?.id == target.id else { return }', self.owner)
        for host in [self.views, self.quick]:
            self.assertIn('ClubSeriesCreationPresentationOwner(item: item', host)
            self.assertIn('didDismiss: finish', host)
            self.assertIn('.id(item.id)', host)
            self.assertIn('coordinator).id(target.id)', host)

    def test_fresh_detail_rechecks_created_id_club_and_topic(self):
        self.assertIn('expectedCreatedSeries: target.receipt', self.editor)
        self.assertIn('expectedCreatedSeries.accepts(result)', self.views)
        for value in ['snapshot.operation == .seriesDetail && snapshot.scope == scope',
                      'snapshot.value["id"].int == seriesID', 'snapshot.value["clubId"].int == scope.clubID',
                      'snapshot.value["topicId"].int == scope.topicID']:
            self.assertIn(value, self.receipt)

    def test_ordinary_list_source_requires_loaded_current_generation(self):
        source = part(self.views, 'private func seriesCreationSource(', 'private func finishSeriesCreationReturn(')
        for value in ['operation == .eventTopics', '!loading, failure == nil', 'snapshotContext == readContext',
                      'generation == snapshotGeneration', 'topicID: topicID, access: access']:
            self.assertIn(value, source)
        self.assertIn('if operation == .eventTopics, seriesCreationReturn.holdsSource,', self.views)
        self.assertIn('seriesCreationReturn.isBound(context: readContext, access: access) { return }', self.views)

    def test_parent_finish_callbacks_capture_current_item_and_visibility(self):
        ordinary = part(self.views, 'private func finishSeriesCreationReturn()', 'private var seriesUpdateSource:')
        quick = part(self.quick, 'private func finishCreationReturn()', 'private func current(')
        for body, name, visible in [(ordinary, 'seriesCreationReturn', 'seriesHostVisible'), (quick, 'creation', 'hostVisible')]:
            self.assertIn('guard let item = '+name+'.item', body)
            self.assertIn('!Task.isCancelled, '+visible+', scenePhase == .active', body)
            self.assertIn(name+'.item?.id == item.id', body)
            self.assertIn(name+'.consume(', body)

    def test_quick_start_reads_check_visibility_before_and_between_awaits(self):
        read = part(self.quick, '@discardableResult func read(', '@MainActor struct ClubSessionQuickStartEntry')
        self.assertIn('guard isCurrent(), accepts(p)', read)
        self.assertIn('isCurrent() && accepts(p) && generation == request && !Task.isCancelled', read)
        self.assertLess(read.index('guard isCurrent()'), read.index('await reader.clubDetail'))
        self.assertGreaterEqual(read.count('guard current() else'), 4)
        self.assertIn('isCurrent: { hostVisible && scenePhase == .active && pendingSelection == ticket && context == scope }', self.quick)

    def test_quick_start_covered_destination_does_not_retire_source(self):
        self.assertIn('if !creation.holdsSource { model.leave(scope) }', self.quick)
        self.assertIn('if creation.holdsSource, creation.isBound(context: scope.topicsContext, access: governance.access) { return }', self.quick)
        self.assertIn('case .quickStart(let target) = item.source.proof, current(target)', self.quick)
        self.assertIn('model.isCurrent(value, context: context, reader: reader, access: governance.access', self.quick)
        self.assertNotIn('onDismiss: { reload', self.quick)

    def test_form_only_create_callback_follows_original_ack_assignment(self):
        self.assertIn('if route.operation == .createSeries, let seriesCreationReturn', self.form)
        self.assertIn('seriesCreationReturn.begin(review)', self.form)
        callback = self.form.index('seriesCreationReturn?.acknowledged(review, value)')
        self.assertLess(self.form.index('receipt = value; self.review = nil; locked = true'), callback)
        self.assertIn('if route.operation == .createSeries, submittedRequestID == draft.requestID, !Task.isCancelled', self.form)
        self.assertIn('seriesUpdateReturn?.acknowledged(review, value)', self.form)

    def test_authority_changes_are_part_of_source_and_destination_identity(self):
        for value in ['context.authorizationGeneration == access.authorizationGeneration',
                      'context.accessIdentity == ObjectIdentifier(access)', 'namespace == access.storageNamespace && realm == access.journalRealm',
                      'destination?.id == target.id && target.source.live(context: context, access: access)']:
            self.assertIn(value, self.owner)

    def test_native_negative_controls_cover_unknown_incomplete_and_late_owner(self):
        tests = (ROOT / 'Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift').read_text()
        for name in ['testMissingEachRequiredReceiptFieldKeepsAcknowledgedFormWithoutReplay',
                     'testUnknownCannotCreateReturnAndOriginalLockRemains',
                     'testCancelAndLateOldDismissalCannotNavigateOrCloseNewOwner',
                     'testOldDestinationNilSetterCannotPopNewDestination',
                     'testDismissBeforeAppearDefersNavigationUntilVisibleOnce',
                     'testAppearBeforeDismissCannotNavigateUntilCurrentDismissal']:
            self.assertIn('func '+name+'(', tests)

    def test_quick_start_negative_controls_do_not_rely_on_leave_callback(self):
        tests = (ROOT / 'Tests/AppUnitTests/ClubSessionQuickStartViewTests.swift').read_text()
        for name in ['testHiddenBeforeOwnerReadStartsNoRequest', 'testHiddenWhileOwnerSuspendsCannotStartTopicsWithoutLeave',
                     'testInactiveDuringTopicsCannotPublishFormWithoutLeave',
                     'testFreshQuickStartThroughRealCoordinatorMatchesCreateAndDefersUntilVisible']:
            self.assertIn('func '+name+'(', tests)


if __name__ == '__main__':
    unittest.main()
