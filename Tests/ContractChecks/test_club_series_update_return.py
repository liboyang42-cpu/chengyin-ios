"""Focused source contracts. These checks do not execute SwiftUI or Swift tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def span(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


def required(source, tokens):
    for token in tokens:
        if token not in source:
            raise AssertionError('Missing return fence: ' + token)


def acknowledgement_fences(source):
    section = span(source, 'func acknowledge(', '@discardableResult func dismissed(')
    required(section, ['guard isPresented', 'current(expected, source: source, active: active)',
                       'submissionID == review.id', 'acknowledgedID == nil', 'state == .acknowledged',
                       'receipt["id"].int == expected.source.context.scope.seriesID',
                       'acknowledgedID = review.id; isPresented = false'])


class ClubSeriesUpdateReturnContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.owner = (ROOT / 'App/ClubSeriesScheduleEditor.swift').read_text().split(
            '@MainActor final class ClubSeriesUpdateReturn:', 1)[1]
        cls.host = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        cls.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        cls.tests = (ROOT / 'Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift').read_text()

    def test_normal_detail_entry_is_scoped_to_update_only(self):
        edit = span(self.host, 'private func edit(', '@ViewBuilder private func content(')
        required(edit, ['operation == .updateSeries, self.operation == .seriesDetail',
                        'seriesUpdateReturn.open(seriesUpdateSource, visible: seriesHostVisible',
                        'else { editor = .init(operation: operation, scope: scope ?? self.scope, seed: seed) }'])
        self.assertIn('edit(.updateSeries, seed: value.object ?? [:])', self.host)

    def test_stable_parent_and_concrete_item_own_sheet(self):
        required(self.host, ['@StateObject private var seriesUpdateReturn = ClubSeriesUpdateReturn()',
                             'if let item = seriesUpdateReturn.item {',
                             'ClubSeriesUpdatePresentationOwner(item: item', '.id(item.id)'])
        required(self.owner, ['.sheet(isPresented: owner.binding(item, source: source, active: active)',
                              'if owner.dismissed(item, source: source(), active: active()) { didDismiss() }'])

    def test_source_requires_identity_authorization_and_same_snapshot(self):
        source = span(self.owner, 'init?(context:', 'struct Item:')
        required(source, ['context.operation == .seriesDetail', 'context.accepts(snapshot)',
                          'context.identity?.isSignedIn == true', 'context.identity == access.identity',
                          'context.authorizationGeneration == access.authorizationGeneration',
                          'context.accessIdentity == ObjectIdentifier(access)', 'access.isConfigured',
                          'snapshot.value["id"].int == context.scope.seriesID',
                          'snapshot.value["topicId"].int == context.scope.topicID',
                          'let version = snapshot.value["version"].int, version >= 0',
                          'snapshot.permissions?.allows(ClubGovernanceRead.seriesDetail.permission',
                          'namespace = access.storageNamespace; realm = access.journalRealm'])
        required(self.host, ['snapshotContext == readContext, generation == snapshotGeneration'])

    def test_begin_binds_exact_review_and_current_owner(self):
        begin = span(self.owner, 'func begin(', 'func acknowledge(')
        required(begin, ['guard isPresented', 'current(expected, source: source, active: active)',
                         'state == .reviewing', 'review.command.operation == .updateSeries',
                         'review.command.scope == expected.source.context.scope',
                         'review.identity == expected.source.context.identity',
                         'review.authorizationGeneration == expected.source.context.authorizationGeneration',
                         'review.storageNamespace == expected.source.namespace',
                         'review.journalRealm == expected.source.realm',
                         'review.snapshot == expected.source.snapshot',
                         'review.command.fields["expectedVersion"] == expected.source.snapshot.value["version"]',
                         'submissionID = review.id'])

    def test_acknowledgement_requires_authoritative_state_and_id(self):
        acknowledgement_fences(self.owner)

    def test_removing_each_ack_fence_fails_the_contract(self):
        for token in ['guard isPresented', 'submissionID == review.id', 'acknowledgedID == nil',
                      'state == .acknowledged', 'receipt["id"].int == expected.source.context.scope.seriesID']:
            section = span(self.owner, 'func acknowledge(', '@discardableResult func dismissed(')
            changed = self.owner.replace(section, section.replace(token, '', 1), 1)
            with self.subTest(token=token), self.assertRaises(AssertionError):
                acknowledgement_fences(changed)

    def test_form_callbacks_leave_existing_ack_lock_and_are_update_only(self):
        confirm = self.form.split('private func confirm(_ review:', 1)[1]
        required(confirm, ['let submittedRequestID = draft.requestID',
                           'if route.operation == .updateSeries, let seriesUpdateReturn',
                           'self.review?.id == review.id, seriesUpdateReturn.begin(review)',
                           'let value = try await coordinator.confirm(review)',
                           'receipt = value; self.review = nil; locked = true',
                           'route.operation == .updateSeries, submittedRequestID == draft.requestID, !Task.isCancelled',
                           'seriesUpdateReturn?.acknowledged(review, value)',
                           'locked = coordinator.isLocked(review.command, identity: review.identity)'])
        self.assertLess(confirm.index('coordinator.confirm(review)'), confirm.index('seriesUpdateReturn?.acknowledged'))
        self.assertIn('seriesUpdateReturn: ClubSeriesUpdateReturn.Callbacks? = nil', self.form)

    def test_both_dismiss_visibility_orders_wait_for_once_only_consumption(self):
        consume = span(self.owner, 'func consume(', 'func invalidateUnlessCurrent(')
        required(consume, ['guard visible, active, !isPresented, didDismiss, acknowledgedID != nil',
                           'current(item, source: source, active: active)', 'retire()', 'return result'])
        required(self.host, ['.onAppear { seriesHostVisible = true; finishSeriesUpdateReturn() }',
                             '.onDisappear { seriesHostVisible = false }'])
        finish = span(self.host, 'private func finishSeriesUpdateReturn()', 'private var terminalSource:')
        required(finish, ['Task { @MainActor in', '!Task.isCancelled, seriesHostVisible, scenePhase == .active',
                          'seriesUpdateReturn.consume(source: seriesUpdateSource', 'await load()'])

    def test_covering_sheet_does_not_retire_pending_return_on_task_restart(self):
        required(self.host, ['operation == .seriesDetail, snapshotContext == readContext, snapshot != nil, generation == snapshotGeneration { return }',
                             'if operation != .seriesDetail || seriesUpdateReturn.item == nil { generation &+= 1 }',
                             'if phase != .active { seriesUpdateReturn.retire() }'])
        invalidation = span(self.host, 'private func invalidateRead()', 'private func current(')
        self.assertIn('seriesUpdateReturn.retire()', invalidation)

    def test_old_binding_and_dismissal_cannot_change_new_item(self):
        required(self.owner, ['active && item?.id == expected.id && expected.source == source',
                              'guard !shown, self.current(expected, source: source(), active: active())',
                              'guard current(expected, source: source, active: active), !isPresented else { return false }',
                              'if acknowledgedID != nil { didDismiss = true }', 'else { retire() }'])

    def test_return_model_never_dispatches_unlocks_or_sleeps(self):
        for forbidden in ['access.send(', 'coordinator.confirm(', '.reserve(', 'locked.remove', 'Task.sleep', 'asyncAfter', 'requestId']:
            self.assertNotIn(forbidden, self.owner)

    def test_authored_native_regressions_include_real_coordinator_and_binding(self):
        for name in ['testActualAcknowledgementReturnsOnceAndKeepsCoordinatorLock',
                     'testDismissBeforeVisibleKeepsPendingUntilVisible', 'testVisibleBeforeDismissDoesNotConsumeEarly',
                     'testCancelSendsNothingAndNeverCreatesReturn', 'testUnknownWriteStaysPresentedLockedAndCannotReturn',
                     'testRejectedAttemptCanPrepareAgainWithoutInventingSuccess', 'testWrongReceiptIDDoesNotCloseOrRefresh',
                     'testEveryNonAcknowledgedStateRejectsReturn', 'testDifferentSubmissionReviewCannotAcknowledgeCurrentSheet',
                     'testOldBindingCancelAndDismissCannotTouchReopenedOwner', 'testOldAcknowledgementCannotCloseReopenedOwner',
                     'testBackgroundCannotConsumeAndRetirementCannotRevive', 'testSourceRefreshGenerationCannotConsumeOldReceipt',
                     'testSameVersionChangedSourceBytesRejectCurrentOwner', 'testIdentityAuthorizationNamespaceAndReaderChangesInvalidateSource',
                     'testHiddenInactiveAndMissingSourceCannotOpen', 'testInvalidTargetVersionAndPermissionCannotCreateSource',
                     'testCurrentBindingRejectsInvalidSourceBeforeViewObserverRuns']:
            self.assertIn('func ' + name + '(', self.tests)
        required(self.tests, ['try await coordinator.confirm(review)', 'coordinator.isLocked(review.command',
                              'oldBinding.wrappedValue = false', 'state: coordinator.state'])


if __name__ == '__main__':
    unittest.main()
