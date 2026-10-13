"""Focused source contracts; native lifecycle execution is a separate acceptance step."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
if not (ROOT / 'App').exists(): ROOT = ROOT.parent

class ClubCaseSubmissionReturnContracts(unittest.TestCase):
    def setUp(self):
        self.owner = (ROOT / 'App/ClubCaseSubmissionReturn.swift').read_text()
        self.host = (ROOT / 'App/ClubGovernanceViews.swift').read_text()
        self.form = (ROOT / 'App/ClubGovernanceCommandForm.swift').read_text()
        self.tests = (ROOT / 'Tests/AppUnitTests/ClubCaseSubmissionReturnTests.swift').read_text()
    def testOnlyTwoExistingCaseOperationsCanOpen(self):
        self.assertIn('guard [.report, .appeal].contains(operation), item == nil, readID == nil, visible, active, let source', self.owner)
        self.assertIn('if self.operation == .cases, [.report, .appeal].contains(operation)', self.host)
        self.assertIn('if operation == .cases { edit(.report); edit(.appeal) }', self.host)
    def testSourceProvesCurrentCasesSnapshotAndAccount(self):
        for token in ['context.operation == .cases', 'context.accepts(snapshot)', 'context.identity == access.identity',
                      'context.authorizationGeneration == access.authorizationGeneration',
                      'context.accessIdentity == ObjectIdentifier(access)', 'snapshot.permissions?.allows']:
            self.assertIn(token, self.owner)
    def testExactReviewAndRequestRecordedBeforeDispatch(self):
        for token in ['review.command.scope == expected.source.context.scope', 'review.snapshot == expected.source.snapshot',
                      'review.storageNamespace == expected.source.namespace', 'review.journalRealm == expected.source.realm',
                      'review.command.fields["requestId"]?.string', 'submitted = review', 'submitted == review']:
            self.assertIn(token, self.owner)
        self.assertLess(self.form.index('!caseSubmissionReturn.begin(review)'), self.form.index('try await coordinator.confirm(review)'))
    def testAcknowledgementFollowsOriginalReceiptAndLock(self):
        self.assertLess(self.form.index('receipt = value; self.review = nil; locked = true'), self.form.index('caseSubmissionReturn?.acknowledged(review)'))
        self.assertIn('state == .acknowledged, submitted == review', self.owner)
        self.assertNotIn('value["id"]', self.owner)
    def testCancellationUnknownAndOldCallbacksDoNotAuthorizeReturn(self):
        for token in ['!isPresented, didDismiss, acknowledged', 'if acknowledged { didDismiss = true } else { retire() }',
                      'item?.id == expected.id', 'guard !shown, self.current(expected', 'let result = item.source; retire(); readID = UUID(); return result']:
            self.assertIn(token, self.owner)
    def testConcreteNonNilStablePresenterOutsideLazyRows(self):
        self.assertIn('@StateObject private var caseSubmissionReturn', self.host)
        self.assertIn('if let item = caseSubmissionReturn.item {', self.host)
        self.assertIn('didDismiss: finishCaseSubmissionReturn).id(item.id)', self.host)
        self.assertIn('.sheet(isPresented: owner.binding(item,', self.owner)
        self.assertIn('guard owner.isPresented, owner.current(item,', self.owner)
    def testBothVisibleDismissOrdersAndOldTaskUUIDAreFenced(self):
        self.assertIn('.onAppear { caseHostVisible = true; finishCaseSubmissionReturn() }', self.host)
        self.assertIn('caseSubmissionReturn.item?.id == item.id', self.host)
        self.assertIn('visible: caseHostVisible, active: scenePhase == .active) != nil', self.host)
        self.assertIn('guard visible, active, !isPresented, didDismiss, acknowledged', self.owner)
    def testCoverDoesNotInvalidateButBackgroundDoes(self):
        self.assertIn('if operation != .cases || caseSubmissionReturn.item == nil {', self.host)
        self.assertIn('if phase != .active { caseSubmissionReturn.retire(); generation &+= 1 }', self.host)
        self.assertIn('if caseSubmissionReturn.item != nil || caseSubmissionReturn.readID != nil { return }', self.host)
    def testReadCurrentFenceBeforeAndAfterAwaitRetainsOriginalContextChecks(self):
        section = self.host.split('@MainActor private func load() async {', 1)[1].split('@MainActor private func invalidateRead()', 1)[0]
        self.assertIn('guard caseReadIsCurrent() else { return }', section)
        self.assertEqual(section.count('guard caseReadIsCurrent(), revision == generation,'), 3)
        self.assertIn('snapshot = nil; failure = nil; loading = true', section)
        self.assertIn('access.identity == expected, !Task.isCancelled', section)
    def testAutomaticReadReservationAndOldCompletionFence(self):
        self.assertIn('readID = UUID(); return result', self.owner)
        self.assertIn('guard readID == expected else { return }; readID = nil', self.owner)
        self.assertIn('caseSubmissionReturn.finishRead(readID)', self.host)
        self.assertIn('if operation == .cases { caseSubmissionReturn.retire() }', self.host)
    def testNoServiceWritePermissionOrLockResetInOwner(self):
        for forbidden in ['URLSession', 'transport.send', 'coordinator.confirm(', 'coordinator.prepare(', 'Approval(', 'unlock(', 'removeLock', 'recipient']:
            self.assertNotIn(forbidden, self.owner)
    def testUnknownFixtureFailsSendNotPreflightRead(self):
        unknown = self.tests.split('func testUnknownAfterSendCannotDismissReturnOrUnlock()', 1)[1].split('    func test', 1)[0]
        self.assertIn('access.sendFailure = .unknown', unknown)
        self.assertNotIn('access.readFailure =', unknown)
        self.assertIn('XCTAssertEqual(access.sends, 1)', unknown)
        self.assertIn('XCTAssertTrue(coordinator.isLocked', unknown)
    def testNewSourcesAreRegisteredAndExistingLabelsAreReused(self):
        project = (ROOT / 'Questify.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(project.count('"path" = "App/ClubCaseSubmissionReturn.swift"'), 1)
        self.assertEqual(project.count('"path" = "Tests/AppUnitTests/ClubCaseSubmissionReturnTests.swift"'), 1)
        self.assertNotIn('Text("club.caseReturn.', self.owner)

if __name__ == '__main__': unittest.main()
