import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PlayAnswerReviewTests: XCTestCase {
    private func ready(text: Bool = false) async -> (AnswerReviewReader, PlayViewModel, UUID) {
        let reader = AnswerReviewReader(); reader.text = text
        let model = PlayViewModel(reader: reader); await model.load()
        return (reader, model, model.beginAnswerVisit())
    }
    func testChoiceReviewFreezesPublicLabelWithoutSending() async throws {
        let (reader, model, visit) = await ready()
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertEqual(review.question, "Synthetic question")
        XCTAssertEqual(review.answer, "A"); XCTAssertEqual(review.displayAnswer, "A. First")
        XCTAssertTrue(model.canConfirmAnswerReview(review)); XCTAssertTrue(reader.sentAnswers.isEmpty)
    }
    func testTextReviewKeepsExactInputBytesAndConfirmationSubmitsThoseBytes() async throws {
        let (reader, model, visit) = await ready(text: true)
        let answer = "  Synthetic line\n第二行  "
        let review = try model.prepareAnswerReview(nodeID: 701, answer: answer, visit: visit)
        XCTAssertEqual(Data(review.answer.utf8), Data(answer.utf8))
        XCTAssertEqual(review.displayAnswer, answer)
        XCTAssertTrue(model.confirmAnswerReview(review)); await model.submit(review)
        XCTAssertEqual(reader.sentAnswers, [answer]); XCTAssertEqual(reader.sentNodes, [701])
    }
    func testCancelHasNoSendAndSameDraftCanBeReviewedAgain() async throws {
        let (reader, model, visit) = await ready()
        let first = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        model.cancelAnswerReview(first)
        XCTAssertFalse(model.canConfirmAnswerReview(first)); XCTAssertTrue(reader.sentAnswers.isEmpty)
        let second = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(second.answer, first.answer)
        XCTAssertTrue(model.canConfirmAnswerReview(second))
    }
    func testUnconfirmedReviewCannotSend() async throws {
        let (reader, model, visit) = await ready()
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        await model.submit(review)
        XCTAssertTrue(reader.sentAnswers.isEmpty); XCTAssertTrue(model.canConfirmAnswerReview(review))
    }
    func testConfirmClaimsOnceAndAdaptiveDismissalDoesNotCancelClaim() async throws {
        let (reader, model, visit) = await ready()
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(review)); XCTAssertFalse(model.confirmAnswerReview(review))
        model.cancelAnswerReview(review)
        await model.submit(review); await model.submit(review)
        XCTAssertEqual(reader.sentAnswers, ["A"])
        XCTAssertEqual(model.visibleReceipt?.nodeID, 701)
        XCTAssertEqual(model.acceptedChoice(for: 701), "A")
        let snapshot = try XCTUnwrap(model.visibleSnapshot)
        XCTAssertTrue(snapshot.isDone(try XCTUnwrap(snapshot.visibleNodes.first)))
        XCTAssertEqual(reader.reads, 2)
    }
    func testAccountChangeBetweenClaimAndAsyncDispatchRejectsOldInput() async throws {
        let (reader, model, visit) = await ready()
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(review))
        reader.identity = .init(accountID: 2, epoch: 2, scope: .activity(41))
        await model.submit(review)
        XCTAssertTrue(reader.sentAnswers.isEmpty); XCTAssertNil(model.visibleReceipt)
    }
    func testSameOwnerFreshReadWithChangedQuestionRejectsOldReview() async throws {
        let (reader, model, visit) = await ready()
        let old = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        reader.question = "Replacement question"; reader.firstLabel = "Replacement choice"
        await model.load()
        XCTAssertFalse(model.confirmAnswerReview(old)); await model.submit(old)
        let fresh = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertEqual(fresh.question, "Replacement question"); XCTAssertEqual(fresh.displayAnswer, "A. Replacement choice")
        XCTAssertTrue(reader.sentAnswers.isEmpty)
    }
    func testSameBytesFreshReadStillInvalidatesGenerationAndClaim() async throws {
        let (reader, model, visit) = await ready()
        let old = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(old)); await model.load()
        await model.submit(old); XCTAssertTrue(reader.sentAnswers.isEmpty)
        let fresh = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertNotEqual(fresh.generation, old.generation)
        XCTAssertEqual(fresh.snapshot, old.snapshot)
    }
    func testDepartureAfterClaimPreventsQueuedDispatchAndReopenRejectsOldGesture() async throws {
        let (reader, model, visit) = await ready()
        let old = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(old)); model.endAnswerVisit(visit)
        let freshVisit = model.beginAnswerVisit()
        await model.submit(old)
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit))
        model.endAnswerVisit(visit)
        XCTAssertNoThrow(try model.prepareAnswerReview(nodeID: 701, answer: "B", visit: freshVisit))
        XCTAssertTrue(reader.sentAnswers.isEmpty)
    }
    func testOldCancelCannotCloseANewerReview() async throws {
        let (_, model, visit) = await ready()
        let old = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        model.cancelAnswerReview(old)
        let fresh = try model.prepareAnswerReview(nodeID: 701, answer: "B", visit: visit)
        model.cancelAnswerReview(old)
        XCTAssertTrue(model.canConfirmAnswerReview(fresh))
    }
    func testMissingVisitForeignNodeAndInvalidChoiceNeverProduceAReview() async throws {
        let (reader, model, visit) = await ready()
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: nil))
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 702, answer: "A", visit: visit))
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 701, answer: "C", visit: visit))
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 701, answer: " ", visit: visit))
        XCTAssertTrue(reader.sentAnswers.isEmpty)
    }
    func testUnknownSendKeepsExistingProgressCheckAndNeverResends() async throws {
        let (reader, model, visit) = await ready(); reader.failSend = true
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(review)); await model.submit(review)
        XCTAssertTrue(model.needsProgressCheck); XCTAssertNotNil(model.actionIssue)
        XCTAssertNil(model.visibleReceipt)
        await model.submit(review); await model.load(keepingReceipt: true)
        XCTAssertEqual(reader.sentAnswers, ["A"])
        XCTAssertThrowsError(try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit))
    }
    func testMismatchedReceiptKeepsUnknownWithoutInventingAcceptedChoice() async throws {
        let (reader, model, visit) = await ready(); reader.wrongReceipt = true
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(review)); await model.submit(review)
        XCTAssertTrue(model.needsProgressCheck); XCTAssertNil(model.acceptedChoice(for: 701))
        XCTAssertNil(model.visibleReceipt); XCTAssertEqual(reader.sentAnswers, ["A"])
    }
    func testCanonicallyEquivalentButDifferentAnswerBytesCannotBorrowTheReview() async throws {
        let (reader, model, visit) = await ready(text: true)
        let original = try model.prepareAnswerReview(nodeID: 701, answer: "é", visit: visit)
        let replacement = "e\u{301}"
        XCTAssertEqual(original.answer, replacement)
        XCTAssertNotEqual(Data(original.answer.utf8), Data(replacement.utf8))
        let changed = PlayAnswerReview(id: original.id, visit: original.visit, generation: original.generation,
            identity: original.identity, snapshot: original.snapshot, nodeID: original.nodeID,
            question: original.question, answer: replacement, displayAnswer: replacement)
        XCTAssertFalse(model.confirmAnswerReview(changed)); await model.submit(changed)
        XCTAssertTrue(reader.sentAnswers.isEmpty); XCTAssertTrue(model.canConfirmAnswerReview(original))
    }
    func testInvalidateClearsPreparedAndConfirmedOwner() async throws {
        let (reader, model, visit) = await ready()
        let review = try model.prepareAnswerReview(nodeID: 701, answer: "A", visit: visit)
        XCTAssertTrue(model.confirmAnswerReview(review)); model.invalidate()
        await model.submit(review); XCTAssertTrue(reader.sentAnswers.isEmpty)
        XCTAssertFalse(model.canConfirmAnswerReview(review))
    }
}

@MainActor private final class AnswerReviewReader: PlayReading {
    let scope = PlaySessionScope.activity(41)
    let isConfigured = true
    var identity: PlayReadIdentity? = .init(accountID: 1, epoch: 1, scope: .activity(41))
    var canSubmitAnswer = true
    let supportsAnswerSubmission = true
    var text = false, failSend = false, wrongReceipt = false
    var question = "Synthetic question", firstLabel = "First"
    var sentAnswers: [String] = [], sentNodes: [Int] = []
    var reads = 0
    private var done = false
    func playSession() async throws -> PlaySnapshot {
        reads += 1
        let node: [String: Any] = ["nodeId": 701, "done": done, "arrived": true, "locked": false,
            "validationMethod": text ? 1 : 3, "question": question, "options": ["A": firstLabel, "B": "Second"]]
        let raw: [String: Any] = ["topicId": 71, "mode": 1, "registered": true, "playable": true, "nodes": [node]]
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try PlaySnapshot(scope: scope, result: JSONDecoder().decode(PlayNodesResult.self, from: data))
    }
    func submitAnswer(nodeID: Int, answer: String) async throws -> PlayAnswerReceipt {
        sentNodes.append(nodeID); sentAnswers.append(answer); canSubmitAnswer = false
        if failSend { throw APIError.httpStatus(503) }
        done = true
        let raw = "{\"nodeId\":\(wrongReceipt ? 702 : nodeID),\"firstTime\":true,\"completed\":true}"
        return try JSONDecoder().decode(PlayAnswerReceipt.self, from: Data(raw.utf8))
    }
}

@MainActor extension PlayAnswerReviewTests {
    private func hosted() async throws -> (UIWindow, UINavigationController, PlayAnswerReviewRootController, PlayAnswerReviewPresentation, AnswerReviewReader, PlayViewModel) {
        let reader = AnswerReviewReader()
        // Use the same reader/model and normal view construction as the ordinary destination.
        let actualModel = PlayViewModel(reader: reader); await actualModel.load()
        let host = UIHostingController(rootView: PlayNodeDetailView(nodeID: 701, model: actualModel))
        let navigation = UINavigationController(rootViewController: host)
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; window.makeKeyAndVisible()
        func root(_ current: UIViewController) -> PlayAnswerReviewRootController? {
            if let value = current as? PlayAnswerReviewRootController { return value }
            return current.children.compactMap(root).first
        }
        for _ in 0..<100 {
            if let value = root(host), value.owner?.capture(nodeID: 701) != nil {
                return (window, navigation, value, try XCTUnwrap(value.owner), reader, actualModel)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw APIError.invalidRequest
    }
    private func waitForReview(_ root: UIViewController) async throws -> UIViewController {
        func presented(_ root: UIViewController) -> UIViewController? {
            if let value = root.presentedViewController { return value }
            return root.children.compactMap(presented).first
        }
        for _ in 0..<100 {
            if let value = presented(root) { return value }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return try XCTUnwrap(presented(root))
    }
    func testNormalHostFirstOpenCreatesConcretePresenterAndCancelAllowsReopen() async throws {
        let (window, nav, _, owner, reader, _) = try await hosted()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertNil(owner.review)
        try owner.prepare(answer: "A", offered: owner.capture(nodeID: 701))
        let first = try XCTUnwrap(owner.review); _ = try await waitForReview(nav)
        XCTAssertTrue(owner.isCurrent(first)); XCTAssertTrue(reader.sentAnswers.isEmpty)
        owner.cancel(first)
        for _ in 0..<100 { if owner.review == nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(owner.review)
        try owner.prepare(answer: "A", offered: owner.capture(nodeID: 701))
        let second = try XCTUnwrap(owner.review); _ = try await waitForReview(nav)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(second.answer, first.answer)
        owner.dismissed(first); XCTAssertEqual(owner.review?.id, second.id)
    }
    func testNormalHostOwnSheetCoverageKeepsVisitUntilSingleConfirmedSend() async throws {
        let (window, nav, _, owner, reader, _) = try await hosted()
        defer { window.isHidden = true; window.rootViewController = nil }
        try owner.prepare(answer: "A", offered: owner.capture(nodeID: 701))
        let review = try XCTUnwrap(owner.review); _ = try await waitForReview(nav)
        owner.disappear() // The lifecycle notification a covering own sheet can deliver.
        XCTAssertTrue(owner.hasVisibleVisit); XCTAssertTrue(owner.isCurrent(review))
        XCTAssertTrue(owner.confirm(review)); XCTAssertFalse(owner.confirm(review))
        await owner.sendClaimed(review); await owner.sendClaimed(review)
        XCTAssertEqual(reader.sentAnswers, ["A"])
    }
    func testNormalHostRemovalRetiresConfirmedSendAndOldPrepareTicket() async throws {
        let (window, nav, _, owner, reader, _) = try await hosted()
        defer { window.isHidden = true; window.rootViewController = nil }
        let ticket = try XCTUnwrap(owner.capture(nodeID: 701))
        try owner.prepare(answer: "A", offered: ticket); let review = try XCTUnwrap(owner.review)
        _ = try await waitForReview(nav); XCTAssertTrue(owner.confirm(review))
        window.rootViewController = nil
        for _ in 0..<100 { if !owner.hasVisibleVisit { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        // Actual native host removal, without manually invoking the owner cleanup.
        await owner.sendClaimed(review)
        XCTAssertFalse(owner.hasVisibleVisit); XCTAssertTrue(reader.sentAnswers.isEmpty)
        XCTAssertThrowsError(try owner.prepare(answer: "A", offered: ticket))
    }
    func testNormalHostFreshReadBeforePresentationClearsExpiredReviewAndAllowsReopen() async throws {
        let (window, nav, _, owner, reader, model) = try await hosted()
        defer { window.isHidden = true; window.rootViewController = nil }
        try owner.prepare(answer: "A", offered: owner.capture(nodeID: 701))
        let old = try XCTUnwrap(owner.review)
        await model.load()
        for _ in 0..<100 { if owner.review == nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(owner.review); XCTAssertFalse(owner.isCurrent(old)); XCTAssertTrue(reader.sentAnswers.isEmpty)
        try owner.prepare(answer: "B", offered: owner.capture(nodeID: 701))
        let fresh = try XCTUnwrap(owner.review); _ = try await waitForReview(nav)
        XCTAssertTrue(owner.isCurrent(fresh)); XCTAssertNotEqual(fresh.id, old.id)
        owner.dismissed(old); XCTAssertEqual(owner.review?.id, fresh.id)
    }
    func testHostedPreparationRejectsFreshReadAndBackgroundTickets() async throws {
        let (window, _, _, owner, reader, model) = try await hosted()
        defer { window.isHidden = true; window.rootViewController = nil }
        let old = try XCTUnwrap(owner.capture(nodeID: 701)); await model.load()
        XCTAssertThrowsError(try owner.prepare(answer: "A", offered: old))
        let visible = try XCTUnwrap(owner.capture(nodeID: 701))
        owner.sceneChanged(active: false); owner.sceneChanged(active: true)
        XCTAssertThrowsError(try owner.prepare(answer: "A", offered: visible))
        XCTAssertTrue(reader.sentAnswers.isEmpty)
    }
}
