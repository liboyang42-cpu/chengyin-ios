"""Focused source contracts. Native lifecycle and Keychain execution run separately."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
if not (ROOT / 'App').exists(): ROOT = ROOT.parent

class ClubRoleManagementReturnContracts(unittest.TestCase):
    def setUp(self):
        self.owner=(ROOT/'App/ClubRoleManagementReturn.swift').read_text()
        self.host=(ROOT/'App/ClubGovernanceViews.swift').read_text()
        self.form=(ROOT/'App/ClubGovernanceCommandForm.swift').read_text()
        self.tests=(ROOT/'Tests/AppUnitTests/ClubRoleManagementReturnTests.swift').read_text()
    def testOnlyExistingTwoRoleActionsUseTheNewReturn(self):
        self.assertIn('if self.operation == .roles, [.assignRole, .revokeRole].contains(operation)',self.host)
        self.assertIn('roleManagementReturn.open(operation, seed: seed, source: source, active: scenePhase == .active)',self.host)
        self.assertIn('else { editor = .init(operation: operation, scope: scope ?? self.scope, seed: seed) }',self.host)
        self.assertIn('[.assignRole, .revokeRole].contains(operation)',self.owner)
    def testExistingScopedRoleSnapshotAndAuthorityGate(self):
        for token in ['context.operation == .roles','context.accepts(snapshot)','context.identity == access.identity',
                      'context.authorizationGeneration == access.authorizationGeneration','context.accessIdentity == ObjectIdentifier(access)',
                      'snapshot.permissions?.allows(ClubGovernanceRead.roles.permission, scope: context.scope) == true',
                      'ClubGovernanceValidation.validate(snapshot.value, operation: .roles, scope: context.scope)']:
            self.assertIn(token,self.owner)
    def testRevokeBindsUniqueAssignmentAndVersion(self):
        self.assertIn('$0["id"].int == id && $0["version"].int == version',self.owner)
        self.assertIn('review.command.fields["assignmentId"] == expected.route.seed["assignmentId"]',self.owner)
        self.assertIn('review.command.fields["version"] == expected.route.seed["version"]',self.owner)
    def testFullRequestReviewAndScopePrecedeOriginalDispatch(self):
        for token in ['review.command.scope == expected.route.scope','review.identity == expected.source.context.identity',
                      'review.storageNamespace == expected.source.namespace','review.journalRealm == expected.source.realm',
                      'review.command.fields["requestId"]?.string','submitted = review','submitted == review']:
            self.assertIn(token,self.owner)
        self.assertLess(self.form.index('roleManagementReturn?.begin(review)'),self.form.index('try await coordinator.confirm(review)'))
    def testOriginalReceiptAndLockBeforeNullDataAcknowledgementCallback(self):
        self.assertLess(self.form.index('receipt = value; self.review = nil; locked = true'),self.form.index('roleManagementReturn?.acknowledged(review, value)'))
        self.assertIn('state == .acknowledged, submitted == review',self.owner)
        self.assertIn('receipt _: ClubGovernanceValue',self.owner)
        self.assertNotIn('receipt["id"]',self.owner)
    def testCancelAndUnknownDoNotConsumeSuccessRead(self):
        self.assertIn('if acknowledged { didDismiss = true } else { retire() }',self.owner)
        self.assertIn('guard visible, active, !isPresented, didDismiss, acknowledged, let item',self.owner)
        body=self.tests.split('func testUnknownSendDoesNotAutomaticallyReturnOrUnlock()',1)[1].split('    func test',1)[0]
        self.assertIn('access.sendFailure = .unknown',body);self.assertNotIn('access.readFailure =',body)
        self.assertIn('XCTAssertTrue(coordinator.isLocked',body)
    def testStableParentConcretePresenterAndOldCallbackUUID(self):
        for token in ['@StateObject private var roleManagementReturn','if let item = roleManagementReturn.item {',
                      'didDismiss: finishRoleManagementReturn).id(item.id)']:
            self.assertIn(token,self.host)
        for token in ['item?.id == expected.id','attachment == expected.attachment','expected.source == source',
                      '.sheet(isPresented: owner.binding(item,']:
            self.assertIn(token,self.owner)
    def testReturnReadIsReservedAndOnlyCurrentVisibleScopeCanRun(self):
        self.assertIn('retire(); readTicket = ticket',self.owner)
        self.assertIn('readTicket == expected && expected.source.context == context',self.owner)
        self.assertIn('!roleManagementReturn.retainsReturn, !roleReads.loading',self.host)
        self.assertIn('roleManagementReturn.visible && scenePhase == .active',self.host)
        self.assertIn('defer { roleManagementReturn.finishRead(ticket) }',self.host)
    def testScopeChangeRetiresActualOldLoadingBeforeNewTask(self):
        self.assertIn('if roleReads.synchronize(readContext) {\n                    roleManagementReturn.retire(); invalidateRead(); loading = false',self.host)
        self.assertIn('result = try await roleReads.load(context: context, access: access, check: check)',self.host)
        self.assertIn('defer { if runID == run { runID = nil; loading = false } }',self.owner)
        self.assertIn('guard runID == run, context == expected, !Task.isCancelled',self.owner)
    def testRealDepartureRetiresBothOwnersWithExactAttachmentGate(self):
        self.assertIn('roleManagementReturn.depart(attachment, reads: roleReads) { generation &+= 1; loading = false }',self.host)
        self.assertIn('guard attachment == expected else { return }\n        depart(expected); reads.retire(); resetParentRead()',self.owner)
        self.assertIn('controller.isBeingDismissed || controller.isMovingFromParent',self.owner)
        self.assertIn('else if wasAttached { leave() }',self.owner)
    def testNoRolePickerWritesGrantsOrServicesAdded(self):
        for token in ['URLSession','coordinator.confirm(','coordinator.prepare(','Approval(','unlock(','targetMemberId','EVENT_CHECKIN','CLUB_OPERATOR']:
            self.assertNotIn(token,self.owner)
        self.assertIn('testAssignAndRevokeBothClubAndEventReturnOnlyTheirOwnFreshListOnce',self.tests)
        self.assertIn('testLoadingContextReplacementStartsFreshWhileOldReadIsHeld',self.tests)
        self.assertIn('testActualDepartureRetiresLoadingAndOldAttachmentCannotRetireReplacement',self.tests)
    def testForegroundSceneSchedulesOnlyExistingVisibleFreshRead(self):
        self.assertIn('else { Task { await loadRolesIfNeeded() } }',self.host)
        self.assertIn('guard operation == .roles, roleManagementReturn.visible, scenePhase == .active,',self.host)
        self.assertIn('!roleManagementReturn.retainsReturn, !roleReads.loading,',self.host)
        self.assertIn('snapshotContext != readContext || snapshotGeneration != generation',self.host)
        self.assertIn('testForegroundFreshReadDoesNotReviveRetiredReviewAndKeepsCurrentScope',self.tests)
        self.assertIn('testForegroundCheckCannotReadFromHiddenOrDepartedParent',self.tests)
    def testOwnReferencesOnlyAndExistingLocalizations(self):
        project=(ROOT/'Questify.xcodeproj/project.pbxproj').read_text()
        for path in ['App/ClubRoleManagementReturn.swift','Tests/AppUnitTests/ClubRoleManagementReturnTests.swift']:
            self.assertEqual(project.count('"path" = "'+path+'"'),1)
        self.assertNotIn('Text("club.roleReturn.',self.owner)

if __name__=='__main__':unittest.main()
