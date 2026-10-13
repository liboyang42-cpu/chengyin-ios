"""Bounded source wiring checks; native SwiftUI execution is verified separately."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
if not (ROOT / 'App').exists(): ROOT = ROOT.parent

class ClubTopicSettingsReturnContracts(unittest.TestCase):
    def setUp(self):
        self.owner = (ROOT/'App/ClubTopicSettingsReturn.swift').read_text()
        self.host = (ROOT/'App/ClubGovernanceViews.swift').read_text()
        self.form = (ROOT/'App/ClubGovernanceCommandForm.swift').read_text()
        self.tests = (ROOT/'Tests/AppUnitTests/ClubTopicSettingsReturnTests.swift').read_text()
    def testNormalEntryUsesOnlyCurrentThreeFlagSource(self):
        self.assertIn('if self.operation == .topicSettings, operation == .saveTopicSettings',self.host)
        self.assertIn('guard editor == nil, source == topicSettingsSource',self.host)
        self.assertIn('topicSettingsReturn.open(seed: seed, source: source',self.host)
        self.assertIn('Set(seed.keys) == Set(["coopOpen", "pinned", "memberOnly"])',self.owner)
        self.assertIn('$0.value == source.snapshot.value[$0.key]',self.owner)
    def testExactTopicIdentityAuthorizationAndPermissionRequired(self):
        for t in ['context.operation == .topicSettings','context.accepts(snapshot)',
                  '(context.scope.clubID ?? 0) > 0','(context.scope.topicID ?? 0) > 0',
                  'snapshot.value["canManage"] == .bool(true)','context.identity == access.identity',
                  'context.authorizationGeneration == access.authorizationGeneration',
                  'context.accessIdentity == ObjectIdentifier(access)','access.isConfigured',
                  'ClubGovernanceRead.topicSettings.permission']:
            self.assertIn(t,self.owner)
    def testCompleteExistingCommandWithoutInventedRequestID(self):
        for t in ['review.command.operation == .saveTopicSettings','review.command.scope == expected.route.scope',
                  'review.snapshot == expected.source.snapshot','Set(["clubId", "topicId", "coopOpen", "pinned", "memberOnly"])',
                  'review.identity == expected.source.context.identity','review.authorizationGeneration == expected.source.context.authorizationGeneration',
                  'review.storageNamespace == expected.source.namespace','review.journalRealm == expected.source.realm','submitted = review']:
            self.assertIn(t,self.owner)
        self.assertNotIn('requestId',self.owner)
        command=(ROOT/'Core/ClubGovernanceCommands.swift').read_text()
        self.assertIn('case .saveTopicSettings: scopeKeys = ["clubId", "topicId"]; requiredKeys = ["coopOpen", "pinned", "memberOnly"]',command)
    def testOriginalConfirmAndLockRemainTheOnlyWrite(self):
        self.assertEqual(self.form.count('try await coordinator.confirm(review)'),1)
        self.assertIn('route.operation == .saveTopicSettings && topicSettingsReturn?.begin(review) == true',self.form)
        self.assertLess(self.form.index('topicSettingsReturn?.begin(review)'),self.form.index('try await coordinator.confirm(review)'))
        self.assertLess(self.form.index('receipt = value; self.review = nil; locked = true'),self.form.index('topicSettingsReturn?.acknowledged(review, value)'))
        for t in ['coordinator.confirm(', 'coordinator.prepare(', 'access.send(', 'unlock(', 'Approval(', 'URLSession']:
            self.assertNotIn(t,self.owner)
    def testOnlyExactAcknowledgementAndValidatedReceiptCanClose(self):
        self.assertIn('state == .acknowledged, submitted == review',self.owner)
        self.assertIn('ClubGovernanceValidation.validate(receipt, operation: .topicSettings',self.owner)
        self.assertIn('if acknowledged { didDismiss = true } else { retire() }',self.owner)
        self.assertIn('testMissingOrMalformedReceiptDoesNotConsumeTheOriginalAcknowledgement',self.tests)
        self.assertIn('testUnknownSendKeepsOriginalOutcomeLockAndDoesNotReturn',self.tests)
    def testStableConcretePresentationAndOldCallbackFences(self):
        self.assertIn('@StateObject private var topicSettingsReturn',self.host)
        self.assertIn('if let item = topicSettingsReturn.item {',self.host)
        self.assertIn('didDismiss: finishTopicSettingsReturn).id(item.id)',self.host)
        self.assertIn('.sheet(isPresented: owner.binding(item,',self.owner)
        self.assertIn('item?.id == expected.id && attachment == expected.attachment',self.owner)
        self.assertIn('guard !shown, self.current(expected',self.owner)
        self.assertIn('testOldBindingDismissalAndAcknowledgementCannotCloseReopenedEditor',self.tests)
    def testReturnWaitsForVisiblePageAndReservesOnce(self):
        self.assertIn('guard visible, active, !isPresented, didDismiss, acknowledged',self.owner)
        self.assertIn('retire(); readTicket = ticket',self.owner)
        self.assertIn('readTicket == expected',self.owner)
        self.assertIn('defer { topicSettingsReturn.finishRead(ticket) }',self.host)
        self.assertIn('testBothVisibleAndDismissOrderingsConsumeOnce',self.tests)
    def testRealDepartureRetiresBothOwnersAndRejectsOldAttachment(self):
        self.assertIn('topicSettingsReturn.depart(attachment, reads: topicSettingsReads) { generation &+= 1; loading = false }',self.host)
        self.assertIn('guard attachment == expected else { return }\n        depart(expected); reads.retire(); resetParentRead()',self.owner)
        self.assertIn('controller.isBeingDismissed || controller.isMovingFromParent',self.owner)
        self.assertIn('static func dismantleUIViewController',self.owner)
        self.assertIn('testActualDepartureRetiresReadButOldAttachmentCannotRetireReplacement',self.tests)
    def testLoadingScopeReplacementRetiresOldRunBeforeNewRead(self):
        self.assertIn('if topicSettingsReads.synchronize(readContext) {\n                    topicSettingsReturn.retire(); invalidateRead(); loading = false',self.host)
        self.assertIn('guard context != next else { return false }\n        retire(); context = next',self.owner)
        self.assertIn('defer { if runID == run { runID = nil; loading = false } }',self.owner)
        self.assertIn('guard runID == run, context == expected, !Task.isCancelled',self.owner)
        self.assertIn('testContextReplacementReadsWhileOldResponseCannotClearNewLoading',self.tests)
    def testForegroundOnlySchedulesCurrentVisibleScopeRead(self):
        self.assertIn('else { Task { await loadTopicSettingsIfNeeded() } }',self.host)
        self.assertIn('guard operation == .topicSettings, topicSettingsReturn.visible, scenePhase == .active,',self.host)
        self.assertIn('!topicSettingsReturn.retainsReturn, !topicSettingsReads.loading,',self.host)
        self.assertIn('snapshotContext != readContext || snapshotGeneration != generation',self.host)
    def testExactReadFencesBeforeAndAfterAwaitNoOptimisticFlags(self):
        body=self.host.split('@MainActor private func load() async {',1)[1].split('@MainActor private func invalidateRead()',1)[0]
        self.assertEqual(body.count('topicSettingsReadIsCurrent(topicSettingsAttachment)'),4)
        self.assertIn('guard context.accepts(result)',body)
        self.assertIn('snapshot = result',body)
        self.assertNotIn('receipt',body)
        self.assertIn('try await access.read(.topicSettings, scope: expected.scope, options: [:], check: current)',self.owner)
        self.assertIn('testNormalSavePreservesAllThreeFlagsAndReturnsAuthoritativeFreshSnapshotOnce',self.tests)
    def testOwnRegistrationAndExistingLocalizationOnly(self):
        project=(ROOT/'Questify.xcodeproj/project.pbxproj').read_text()
        for path in ['App/ClubTopicSettingsReturn.swift','Tests/AppUnitTests/ClubTopicSettingsReturnTests.swift']:
            self.assertEqual(project.count('"path" = "'+path+'"'),1)
        self.assertNotIn('Text("club.topicSettingsReturn.',self.owner)

if __name__=='__main__':unittest.main()
