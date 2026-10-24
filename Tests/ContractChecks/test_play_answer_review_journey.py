"""Source checks only; Swift/XCTest runtime validation remains separate."""
from pathlib import Path
import json
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PlayAnswerReviewJourneyContracts(unittest.TestCase):
    def read(self, p): return (ROOT / p).read_text()
    def require(self, source, *items):
        for item in items: self.assertIn(item, source)

    def test_frozen_memory_only_review(self):
        s = self.read('App/PlayAnswerReview.swift')
        self.require(s, 'let id: UUID', 'let visit: UUID', 'let generation: UInt64', 'let identity: PlayReadIdentity',
                     'let snapshot: PlaySnapshot', 'let nodeID: Int', 'let question: String', 'let answer: String',
                     'let displayAnswer: String', 'if isCurrent {', 'Text(verbatim: review.question)',
                     'Text(verbatim: review.displayAnswer)', '.privacySensitive()')
        for x in ['Codable', 'UserDefaults', 'FileManager', 'URLSession', 'print(']: self.assertNotIn(x, s)

    def test_prepare_uses_current_question_and_original_answer_gate(self):
        s = self.read('App/PlayComponents.swift').split('func prepareAnswerReview(', 1)[1].split('func canConfirmAnswerReview', 1)[0]
        self.require(s, 'visit == answerVisit', 'pendingAnswerReview == nil', '!isLoading, !isSubmitting, !needsProgressCheck',
                     'reader.supportsAnswerSubmission, reader.canSubmitAnswer', 'identity == reader.identity',
                     'snapshot = visibleSnapshot', '$0.id == nodeID', 'question = node.question',
                     'try snapshot.validateAnswer(nodeID: nodeID, answer: answer)', 'generation: generation',
                     'snapshot: snapshot, nodeID: nodeID, question: question, answer: answer')
        for x in ['submitAnswer', 'Task {', 'trimmingCharacters']: self.assertNotIn(x, s)

    def test_synchronous_claim_and_dispatch_recheck_full_owner(self):
        s = self.read('App/PlayComponents.swift')
        part = s.split('private func matchesAnswerReview', 1)[1].split('private func clearAnswerReview', 1)[0]
        self.require(part, 'answerVisit == review.visit', 'pending == review', 'pending.answer.utf8.elementsEqual(review.answer.utf8)', 'pending.question.utf8.elementsEqual(review.question.utf8)', 'pending.displayAnswer.utf8.elementsEqual(review.displayAnswer.utf8)', 'generation == review.generation',
                     'loadedIdentity == review.identity', 'reader.identity == review.identity', 'visibleSnapshot == review.snapshot',
                     '!isLoading && !isSubmitting && !needsProgressCheck', 'reader.supportsAnswerSubmission && reader.canSubmitAnswer')
        self.require(s, '!answerReviewConfirmed && matchesAnswerReview(review)',
                     'guard canConfirmAnswerReview(review) else { return false }\n        answerReviewConfirmed = true')
        part = s.split('private func dispatchAnswer', 1)[1]
        self.require(part, 'guard answerReviewConfirmed, matchesAnswerReview(reviewed) else { return }')
        self.assertLess(part.index('clearAnswerReview()'), part.index('reader.submitAnswer('))
        self.assertEqual(part.count('reader.submitAnswer('), 1)

    def test_cancel_fresh_read_exit_and_background_retire_old_owner(self):
        s = self.read('App/PlayComponents.swift')
        self.require(s, 'guard let visit, visit == answerVisit else { return }',
                     'guard pendingAnswerReview?.id == review.id, !answerReviewConfirmed else { return }',
                     'func invalidate() {\n        clearAnswerReview(); answerVisit = nil',
                     'guard !isSubmitting else { return }\n        clearAnswerReview()\n        generation &+= 1')
        s = self.read('App/PlayAnswerReview.swift')
        self.require(s, 'guard self.root === root', 'root.isActuallyLeaving', 'func detach(',
                     'if review != nil, attached { return }', 'model.endAnswerVisit(visit)',
                     'if !active { retire() }', 'else if visible, visit == nil',
                     'visit == offered.visit', 'model.answerReviewGeneration(visit: offered.visit) == offered.generation',
                     'model.visibleSnapshot == offered.snapshot')
        cancel = s.split('func cancel(_ offered:', 1)[1].split('func dismissed(', 1)[0]
        self.require(cancel, 'review?.id == offered.id', 'model.cancelAnswerReview(offered)')
        self.assertNotIn('answer =', cancel)

    def test_normal_sheet_has_concrete_uuid_presenter_and_claims_before_task(self):
        v = self.read('App/PlayNodeDetailView.swift')
        self.require(v, '@StateObject private var reviewOwner:', 'if let offered = reviewOwner.review {',
                     'PlayAnswerReviewPresenter(owner: reviewOwner, offered: offered).id(offered.id)',
                     'PlayAnswerReviewRoot(owner: reviewOwner)', 'let offeredAnswer = reviewOwner.capture(nodeID: nodeID)',
                     'try reviewOwner.prepare(answer: answer, offered: offeredAnswer)')
        self.require(v, '.onChange(of: reviewOwner.readGeneration)', 'reviewOwner.discardInvalidUnclaimedReview()')
        self.require(self.read('App/PlayAnswerReview.swift'), 'guard showing, let offered = review, claimedID == nil, !model.canConfirmAnswerReview(offered)')
        self.assertNotIn('.sheet(item:', v)
        self.assertNotIn('model.submit(nodeID:', v)
        s = self.read('App/PlayAnswerReview.swift')
        self.require(s, 'let offered: PlayAnswerReview', 'owner.isPresented(offered)', 'owner.cancel(offered)',
                     'onDismiss: { owner.dismissed(offered) }', 'isCurrent(offered), model.confirmAnswerReview(offered)',
                     'claimedID == offered.id, visible, active, attached, visit == offered.visit')
        confirm = s.split('PlayAnswerReviewSheet(review: offered', 1)[1].split('}, cancel:', 1)[0]
        self.assertLess(confirm.index('guard owner.confirm(offered)'), confirm.index('Task { await owner.sendClaimed(offered) }'))
        self.require(s, 'isBeingDismissed || current.isMovingFromParent', 'navigation.topViewController !== current',
                     'tabs.selectedViewController !== current', 'return !attachedWindow',
                     'root.owner?.detach(root)', 'self.owner?.nativeDisappeared(self)')

    def test_original_receipt_and_fresh_read_no_resend(self):
        s = self.read('App/PlayComponents.swift')
        self.require(s, 'guard !isLoading, !isSubmitting, reader.canSubmitAnswer',
                     'do { try snapshot.validateAnswer(nodeID: nodeID, answer: answer) } catch { return }',
                     'guard current(request, identity) else { return }',
                     'guard result.nodeID == nodeID else { throw APIError.malformedResponse }',
                     'receiptChoice = node?.validationMethod == 3 && node?.options?[answer] != nil ? answer : nil',
                     'await load(keepingReceipt: true)', 'needsProgressCheck = true',
                     'await dispatchAnswer(nodeID: nodeID, answer: answer, reviewed: nil)')
        self.assertEqual(s.count('reader.submitAnswer('), 1)
        self.assertNotIn('submitAnswer', s.split('private func dispatchAnswer', 1)[1].split('} catch is CancellationError {', 1)[1])
        self.require(self.read('App/PlayNodeDetailView.swift'), 'else if model.needsProgressCheck', 'model.acceptedChoice(for: nodeID) ?? answer')

    def test_dedicated_table_and_registration(self):
        j = json.loads(self.read('Resources/PlayAnswerReview.xcstrings'))
        self.assertEqual(set(j['strings']), {'title', 'answer', 'detail', 'confirm', 'cancel', 'expired', 'review'})
        for v in j['strings'].values():
            self.assertEqual(set(v['localizations']), {'en', 'zh-Hans'})
            for loc in v['localizations'].values():
                self.assertEqual(loc['stringUnit']['state'], 'translated'); self.assertTrue(loc['stringUnit']['value'].strip())
        for p in ['App/PlayAnswerReview.swift', 'App/PlayNodeDetailView.swift']:
            self.require(self.read(p), 'table: "PlayAnswerReview", locale: locale')
        self.require(self.read('Questify.xcodeproj/project.pbxproj'), 'App/PlayAnswerReview.swift',
                     'Resources/PlayAnswerReview.xcstrings', 'Tests/AppUnitTests/PlayAnswerReviewTests.swift')

    def test_native_cases_and_ui_preserve_business_assertions(self):
        s = self.read('Tests/AppUnitTests/PlayAnswerReviewTests.swift')
        self.assertEqual(len(re.findall(r'    func (test\w+)\(', s)), 20)
        self.require(s, 'testTextReviewKeepsExactInputBytesAndConfirmationSubmitsThoseBytes',
                     'testAccountChangeBetweenClaimAndAsyncDispatchRejectsOldInput',
                     'testSameBytesFreshReadStillInvalidatesGenerationAndClaim',
                     'testDepartureAfterClaimPreventsQueuedDispatchAndReopenRejectsOldGesture',
                     'testOldCancelCannotCloseANewerReview', 'testUnknownSendKeepsExistingProgressCheckAndNeverResends',
                     'testMismatchedReceiptKeepsUnknownWithoutInventingAcceptedChoice',
                     'testNormalHostFirstOpenCreatesConcretePresenterAndCancelAllowsReopen',
                     'testNormalHostOwnSheetCoverageKeepsVisitUntilSingleConfirmedSend',
                     'testNormalHostRemovalRetiresConfirmedSendAndOldPrepareTicket',
                     'testHostedPreparationRejectsFreshReadAndBackgroundTickets')
        s = self.read('Tests/AppUITests/ModuleFlowTests.swift').split('func testPlayChoiceSubmissionUsesOfflineReadback', 1)[1].split('func testTextComposer', 1)[0]
        self.require(s, 'Cancelling a review never submits', 'Cancelling keeps the staged choice',
                     'play.answer.review.cancel', 'play.answer.review.confirm', 'receipt.waitForExistence(timeout:10)',
                     'Server-confirmed node cannot be submitted twice',
                     'The exact accepted A choice stays selected after authoritative readback',
                     'Accepted choice remains locked against duplicate submission')

if __name__ == '__main__': unittest.main()
