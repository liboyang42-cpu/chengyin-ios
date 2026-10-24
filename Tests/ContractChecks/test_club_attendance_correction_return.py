"""Bounded source contracts. SwiftUI lifecycle and native execution run separately."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
if not (ROOT / 'App').exists(): ROOT = ROOT.parent

class ClubAttendanceCorrectionReturnContracts(unittest.TestCase):
    def setUp(self):
        self.owner = (ROOT / 'App/ClubAttendanceCorrectionReturn.swift').read_text()
        self.host = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        self.tests = (ROOT / 'Tests/AppUnitTests/ClubAttendanceCorrectionReturnTests.swift').read_text()
    def testNormalRosterRoutesThroughExistingCorrectionProof(self):
        self.assertIn('guard editor == nil, source == attendanceSource', self.host)
        self.assertIn('attendanceReturn.open(target, source: source, access: access', self.host)
        self.assertIn('ClubRosterInteraction.formRoute(target', self.owner)
        self.assertIn('ClubRosterPresentation(snapshot: snapshot, context: context)', self.owner)
    def testSourceIncludesActivityAuthorityReaderBucketAndGeneration(self):
        for token in ['context.operation == .roster', 'context.accepts(snapshot)', 'context.identity == access.identity',
                      'context.authorizationGeneration == access.authorizationGeneration', 'context.accessIdentity == ObjectIdentifier(access)',
                      'let generation: UInt64', 'let bucket: ClubRosterBucket', 'access.storageNamespace', 'access.journalRealm']:
            self.assertIn(token, self.owner)
    def testExactReviewAndOriginalVersionBindBeforeOriginalConfirm(self):
        for token in ['review.command.operation == .correctAttendance', 'review.command.scope == expected.route.scope',
                      'review.command.fields["expectedVersion"] == expected.route.seed["expectedVersion"]',
                      'review.command.fields["requestId"]?.string', 'submitted = review', 'submitted == review']:
            self.assertIn(token, self.owner)
        self.assertLess(self.form.index('attendanceReturn?.begin(review)'), self.form.index('try await coordinator.confirm(review)'))
    def testAcknowledgementNeverChangesOriginalLockOrOtherOperation(self):
        self.assertIn('route.operation == .correctAttendance && attendanceReturn?.begin(review) == true', self.form)
        self.assertLess(self.form.index('receipt = value; self.review = nil; locked = true'), self.form.index('attendanceReturn?.acknowledged(review, value)'))
        self.assertIn('state == .acknowledged, submitted == review', self.owner)
        self.assertIn('let id = receipt["id"].int', self.owner)
    def testOrdinaryDismissalReadIsNotAcknowledgement(self):
        self.assertIn('enum ReadReason: Equatable { case acknowledged, dismissed }', self.owner)
        self.assertIn('reason: acknowledged ? .acknowledged : .dismissed', self.owner)
        self.assertIn('guard visible, active, !isPresented, didDismiss', self.owner)
        self.assertIn('testCancellationPreservesOrdinaryReadButNeverClaimsAcknowledgementOrSends', self.tests)
        self.assertIn('testUnknownStaysOpenUntilExplicitCloseThenOnlyOrdinaryReadAndLockPersists', self.tests)
    def testNonNilUUIDPresenterOwnedByWholePage(self):
        self.assertIn('@StateObject private var attendanceReturn', self.host)
        self.assertIn('if let item = attendanceReturn.item {', self.host)
        self.assertIn('didDismiss: finishAttendanceReturn).id(item.id)', self.host)
        self.assertIn('.sheet(isPresented: owner.binding(item,', self.owner)
        self.assertNotIn('Item?', self.owner.split('func binding(',1)[1].split('-> Binding',1)[0])
    def testRealDepartureAndCoverAreDifferent(self):
        self.assertIn('func hide() { visible = false }', self.owner)
        self.assertIn('guard attachment == expected else { return }', self.owner)
        self.assertIn('controller.isBeingDismissed || controller.isMovingFromParent', self.owner)
        self.assertIn('else if wasAttached { leave() }', self.owner)
        self.assertIn('dismantleUIViewController', self.owner)
        self.assertIn('if !attendanceReturn.retainsReturn { attendanceReads.retire(); generation &+= 1; loading = false }', self.host)
    def testVisibleConsumptionAndReadReservationPreventDuplicateReload(self):
        self.assertIn('retire(); readTicket = ticket', self.owner)
        self.assertIn('readTicket == expected', self.owner)
        self.assertIn('!attendanceReturn.retainsReturn, !attendanceReads.loading', self.host)
        self.assertIn('attendanceReturn.appear()\n                finishAttendanceReturn()', self.host)
        self.assertIn('defer { attendanceReturn.finishRead(ticket) }', self.host)
    def testBeforeAndAfterAwaitReadFencesBindRealPage(self):
        body=self.host.split('@MainActor private func load() async {',1)[1].split('@MainActor private func invalidateRead()',1)[0]
        self.assertEqual(body.count('rosterReadIsCurrent(rosterAttachment)'),4)
        self.assertIn('access.identity == expected',body)
        self.assertIn('context.accepts(result)',body)
        self.assertIn('attendanceReturn.visible && scenePhase == .active',self.host)
    def testOldOwnerAndChangedBucketCannotTouchNewPresentation(self):
        for token in ['item?.id == expected.id', 'attachment == expected.attachment', 'expected.source == source',
                      'guard !shown, self.current(expected', 'guard current(expected, source: source, active: active), !isPresented']:
            self.assertIn(token,self.owner)
        for name in ['testOldBindingDismissalAndAckCannotTouchReopenedRoute','testChangedFilterOrSnapshotGenerationRejectsOldReturn',
                     'testRealDepartureBeforeLateSendReplyCannotCloseNewOwner']:
            self.assertIn(name,self.tests)
    def testUnknownFixtureFailsOnlySendWhileOriginalCoordinatorRemainsAuthority(self):
        method=self.tests.split('func testUnknownStaysOpenUntilExplicitCloseThenOnlyOrdinaryReadAndLockPersists()',1)[1].split('    func test',1)[0]
        self.assertIn('access.sendFailure = .unknown',method)
        self.assertNotIn('access.readFailure =',method)
        self.assertIn('XCTAssertTrue(coordinator.isLocked',method)
        for token in ['coordinator.confirm(', 'coordinator.prepare(', 'URLSession', 'unlock(', 'Approval(']:
            self.assertNotIn(token,self.owner)
    def testChangedContextRetiresRealLoadingBeforeReplacementTask(self):
        self.assertIn('@StateObject private var attendanceReads = ClubAttendanceRosterRead()', self.host)
        self.assertIn('if attendanceReads.synchronize(readContext) {\n                    attendanceReturn.retire(); invalidateRead(); loading = false', self.host)
        self.assertIn('result = try await attendanceReads.load(context: context, access: access, check: check)', self.host)
        self.assertIn('guard context != next else { return false }\n        retire(); context = next', self.owner)
        self.assertIn('defer { if runID == run { runID = nil; loading = false } }', self.owner)
        self.assertIn('guard runID == run, context == expected, !Task.isCancelled', self.owner)
        self.assertIn('testActualRosterLoadingOwnerStartsNewAccountReadWhileOldResponseIsPending', self.tests)
        self.assertIn('testOldReadFailureCannotClearNewAuthorizationReadLoading', self.tests)
        self.assertIn('testRetiredHiddenReadCanRestartSameContextAndOldCompletionCannotClearNewLoading', self.tests)
    def testActualLifetimeDepartureRetiresBothOwnersAfterExactAttachmentCheck(self):
        self.assertIn('attendanceReturn.depart(attachment, reads: attendanceReads) { generation &+= 1; loading = false }', self.host)
        self.assertIn('func depart(_ expected: UUID, reads: ClubAttendanceRosterRead, resetParentRead: () -> Void)', self.owner)
        self.assertIn('guard attachment == expected else { return }\n        depart(expected); reads.retire(); resetParentRead()', self.owner)
        self.assertIn('owner.depart(try XCTUnwrap(owner.attachment), reads: reader) { resets += 1 }', self.tests)
        self.assertIn('testOldAttachmentDepartureCannotRetireReplacementReadOrResetParent', self.tests)
    def testOnlyOwnTwoSwiftLeavesRegisteredAndNoNewTranslationTable(self):
        project=(ROOT/'Questify.xcodeproj/project.pbxproj').read_text()
        for path in ['App/ClubAttendanceCorrectionReturn.swift','Tests/AppUnitTests/ClubAttendanceCorrectionReturnTests.swift']:
            self.assertEqual(project.count('"path" = "'+path+'"'),1)
        self.assertNotIn('Text("club.attendanceReturn.',self.owner)

    def testForegroundSceneSchedulesOnlyExistingVisibleFreshRead(self):
        self.assertIn('else { Task { await loadRosterIfNeeded() } }',self.host)
        self.assertIn('guard operation == .roster, attendanceReturn.visible, scenePhase == .active,',self.host)
        self.assertIn('!attendanceReturn.retainsReturn, !attendanceReads.loading,',self.host)
        self.assertIn('snapshotContext != readContext || snapshotGeneration != generation',self.host)
        self.assertIn('testForegroundFreshReadDoesNotReviveRetiredReviewAndKeepsCurrentScope',self.tests)
        self.assertIn('testForegroundCheckCannotReadFromHiddenOrDepartedParent',self.tests)

if __name__ == '__main__': unittest.main()
