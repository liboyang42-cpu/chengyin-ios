import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the shipping coordinator, client and authenticated adapter together.
/// The HTTP boundary is held locally to inject cancellation-resistant late responses.
@MainActor final class ShopNPCInterruptionTests: XCTestCase {
    @MainActor final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var waiting: [Int: CheckedContinuation<(Data, Int), Never>] = [:]
        var cancelled: [Int: Bool] = [:]
        var hold = false
        var fail = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let index = requests.count; requests.append(request)
            if hold {
                let result = await withCheckedContinuation { waiting[index] = $0 }
                cancelled[index] = Task.isCancelled
                return result
            }
            if fail { throw URLError(.networkConnectionLost) }
            return (Data(#"{"code":200,"data":{"text":"answer"}}"#.utf8), 200)
        }
        func finish(_ index: Int, answer: String = "late answer") {
            let bytes = try! JSONSerialization.data(withJSONObject: ["code": 200, "data": ["text": answer]])
            waiting.removeValue(forKey: index)?.resume(returning: (bytes, 200))
        }
        enum WaitFailure: Error { case requestNotDispatched(Int) }
        func waitFor(_ index: Int) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while waiting[index] == nil {
                guard clock.now < deadline else { throw WaitFailure.requestNotDispatched(index) }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
    }
    @MainActor final class Harness {
        let http = HTTP()
        var session: ShopNPCHostSession?
        var grants: ShopNPCGrants
        var time = Date(timeIntervalSince1970: 100)
        var onSessionRead: (() -> Void)?
        init() throws {
            session = try .init(scope: Self.scope(), token: "unit-test-token")
            var value = ShopNPCGrants()
            value.server = true; value.provider = true; value.legal = true; value.access = true
            grants = value
        }
        static func scope(session: String = "run-a", account: String = "player-a", role: String = "player", revision: UInt64 = 1, node: Int = 17) -> ShopNPCScope {
            .init(sessionID: session, accountID: account, roleID: role, accessRevision: revision, nodeID: ShopNPCNodeID(node)!)
        }
        func coordinator(production: Bool = true) throws -> ShopNPCCoordinator {
            let adapter = ShopNPCAuthenticatedHTTPTransport(
                configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: http,
                productionWritesEnabled: production,
                currentSession: { [unowned self] in self.onSessionRead?(); return self.session },
                currentGrants: { [unowned self] in self.grants })
            return .init(scope: Self.scope(), grants: grants, client: .init(transport: adapter), now: { [unowned self] in self.time })
        }
    }
    final class NoResumeAuthority: ShopNPCHTTPTransport {
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse { XCTFail("Must not dispatch"); throw ShopNPCFailure.disabled }
    }
    private func body(_ request: URLRequest) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? NSDictionary)
    }
    func testUnimplementedRestoreAuthorityDefaultsToDenial() throws {
        let h = try Harness()
        let c = ShopNPCCoordinator(scope: Harness.scope(), grants: h.grants, client: .init(transport: NoResumeAuthority()))
        try c.reviewText("private draft"); c.suspend(); c.resumeAfterInterruption()
        XCTAssertFalse(c.active); XCTAssertFalse(c.isSuspended); XCTAssertNil(c.pending)
        XCTAssertEqual(c.failure, .disabled)
    }
    func testNormalSendThenExplicitRestoreRetainsConversationWithoutDispatch() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("hello"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        let before = c.messages; XCTAssertEqual(before.count, 2)
        c.suspend(); c.suspend(); XCTAssertTrue(c.isSuspended); XCTAssertEqual(c.messages, before)
        XCTAssertTrue(c.revalidateSuspension()); XCTAssertTrue(c.isSuspended)
        XCTAssertEqual(h.http.requests.count, 1)
        c.resumeAfterInterruption(); c.resumeAfterInterruption()
        XCTAssertTrue(c.active); XCTAssertFalse(c.isSuspended); XCTAssertEqual(c.messages, before)
        XCTAssertEqual(h.http.requests.count, 1)
        h.time.addTimeInterval(2); try c.reviewText("next question")
        await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        XCTAssertEqual(c.messages.count, 4); XCTAssertEqual(h.http.requests.count, 2)
    }
    func testReviewedQuestionSurvivesSuspendAndRequiresSeparateSend() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("reviewed question"); let review = try XCTUnwrap(c.pending)
        c.suspend(); c.resumeAfterInterruption()
        XCTAssertEqual(c.pending, review); XCTAssertTrue(h.http.requests.isEmpty)
        await c.transmit(reviewID: review.id)
        XCTAssertEqual(h.http.requests.count, 1); XCTAssertNil(c.pending)
    }
    func testStopWaitingPreservesOriginalIDAndLateReplyCannotReplaceRetry() async throws {
        let h = try Harness(); h.http.hold = true; let c = try h.coordinator()
        try c.reviewText("same question"); let review = try XCTUnwrap(c.pending)
        let old = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(0)
        c.stopWaiting(); c.stopWaiting()
        XCTAssertFalse(c.busy); XCTAssertEqual(c.failure, .unknownOutcome); XCTAssertEqual(c.pending, review)
        h.time.addTimeInterval(2)
        let retry = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(1)
        XCTAssertEqual(try body(h.http.requests[0]), try body(h.http.requests[1]))
        h.http.finish(0); await old.value
        XCTAssertTrue(c.busy); XCTAssertEqual(c.pending, review); XCTAssertTrue(c.messages.isEmpty)
        XCTAssertEqual(h.http.cancelled[0], true)
        h.http.finish(1, answer: "accepted retry"); await retry.value
        XCTAssertEqual(c.messages.map(\.text), ["same question", "accepted retry"])
        XCTAssertFalse(c.busy); XCTAssertNil(c.pending)
    }
    func testBackgroundInFlightKeepsUnknownIDAndDiscardsLateResponse() async throws {
        let h = try Harness(); h.http.hold = true; let c = try h.coordinator()
        try c.reviewText("private question"); let review = try XCTUnwrap(c.pending)
        let old = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(0)
        c.suspend(); XCTAssertTrue(c.isSuspended); XCTAssertFalse(c.busy)
        h.http.finish(0); await old.value
        XCTAssertTrue(c.messages.isEmpty); XCTAssertEqual(c.pending, review); XCTAssertEqual(c.failure, .unknownOutcome)
        c.revalidateSuspension(); XCTAssertTrue(c.isSuspended); XCTAssertEqual(h.http.requests.count, 1)
        c.resumeAfterInterruption(); XCTAssertFalse(c.isSuspended); XCTAssertEqual(c.pending, review)
        XCTAssertEqual(h.http.requests.count, 1)
    }
    func testRevokedGrantPermanentlyClearsSuspendedConversation() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("private"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        c.suspend(); h.grants.access = false; c.revalidateSuspension()
        XCTAssertFalse(c.active); XCTAssertTrue(c.messages.isEmpty); XCTAssertNil(c.pending)
        h.grants.access = true; c.resumeAfterInterruption()
        XCTAssertFalse(c.active); XCTAssertEqual(h.http.requests.count, 1)
    }
    func testAccountRoleNodeRunAndRevisionChangesPermanentlyInvalidate() throws {
        let changes = [Harness.scope(session: "run-b"), Harness.scope(account: "player-b"),
                       Harness.scope(role: "merchant"), Harness.scope(revision: 2), Harness.scope(node: 99)]
        for changed in changes {
            let h = try Harness(); let c = try h.coordinator()
            try c.reviewText("private"); c.suspend()
            h.session = try .init(scope: changed, token: "unit-test-token")
            c.resumeAfterInterruption()
            XCTAssertFalse(c.active); XCTAssertNil(c.pending); XCTAssertTrue(c.messages.isEmpty)
            XCTAssertTrue(h.http.requests.isEmpty)
            h.session = try .init(scope: Harness.scope(), token: "unit-test-token")
            c.resumeAfterInterruption(); XCTAssertFalse(c.active)
        }
    }
    func testMissingAuthorityAtSuspensionClearsImmediately() throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("private"); h.session = nil; c.suspend()
        XCTAssertFalse(c.active); XCTAssertNil(c.pending); XCTAssertFalse(c.isSuspended)
        XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testChangedCredentialDuringResumeValidationFailsClosed() throws {
        let h = try Harness(); let c = try h.coordinator(); try c.reviewText("private"); c.suspend()
        var reads = 0
        h.onSessionRead = {
            reads += 1
            if reads == 2 { h.session = try! .init(scope: Harness.scope(), token: "replacement-test-token") }
        }
        c.resumeAfterInterruption()
        XCTAssertFalse(c.active); XCTAssertNil(c.pending); XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testProductionGateOffCannotRestoreOrDispatch() throws {
        let h = try Harness(); let c = try h.coordinator(production: false)
        try c.reviewText("private"); c.suspend(); c.resumeAfterInterruption()
        XCTAssertFalse(c.active); XCTAssertNil(c.pending); XCTAssertEqual(c.failure, .disabled)
        XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testDestinationInvalidationCannotBeReversedByResume() throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("private"); c.suspend(); c.invalidate()
        c.revalidateSuspension(); c.resumeAfterInterruption(); c.suspend()
        XCTAssertFalse(c.active); XCTAssertFalse(c.isSuspended); XCTAssertNil(c.pending)
        XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testPendingUnknownCannotBeReplacedByNewTextVoiceOrRegeneration() async throws {
        let h = try Harness(); h.grants.voiceTransmission = true; h.grants.voiceFormatVerified = true
        h.http.fail = true; let c = try h.coordinator()
        try c.reviewText("original"); let review = try XCTUnwrap(c.pending)
        await c.transmit(reviewID: review.id)
        XCTAssertEqual(c.failure, .unknownOutcome)
        XCTAssertThrowsError(try c.reviewText("replacement"))
        XCTAssertThrowsError(try c.reviewVoice(.init(bytes: Data([1]), duration: 1)))
        XCTAssertThrowsError(try c.reviewRegeneration(answerID: UUID()))
        XCTAssertEqual(c.pending, review); XCTAssertEqual(h.http.requests.count, 1)
    }
    func testUnknownRetryAfterRestoreRetainsBodyAndCooldown() async throws {
        let h = try Harness(); h.http.fail = true; let c = try h.coordinator()
        try c.reviewText("original"); let review = try XCTUnwrap(c.pending)
        await c.transmit(reviewID: review.id); c.suspend(); c.resumeAfterInterruption()
        await c.transmit(reviewID: review.id)
        XCTAssertEqual(c.failure, .rateLimited); XCTAssertEqual(h.http.requests.count, 1)
        h.time.addTimeInterval(2); h.http.fail = false
        await c.transmit(reviewID: review.id)
        XCTAssertEqual(try body(h.http.requests[0]), try body(h.http.requests[1]))
        XCTAssertEqual(c.messages.count, 2); XCTAssertNil(c.pending)
    }
    func testSuspendedReviewCannotSendOrBeDiscardedUntilExplicitRestore() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("private"); let review = try XCTUnwrap(c.pending); c.suspend()
        c.cancelReview(); await c.transmit(reviewID: review.id)
        XCTAssertEqual(c.pending, review); XCTAssertTrue(c.isSuspended); XCTAssertTrue(h.http.requests.isEmpty)
        c.resumeAfterInterruption(); c.cancelReview(); XCTAssertNil(c.pending)
    }
    func testBusyReviewCannotBeDiscardedAndExplicitDiscardAfterStopIsAllowed() async throws {
        let h = try Harness(); h.http.hold = true; let c = try h.coordinator()
        try c.reviewText("original"); let review = try XCTUnwrap(c.pending)
        let task = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(0)
        c.cancelReview(); XCTAssertEqual(c.pending, review)
        c.stopWaiting(); c.cancelReview(); try c.reviewText("different request")
        let replacement = try XCTUnwrap(c.pending); XCTAssertNotEqual(replacement.id, review.id)
        h.http.finish(0); await task.value
        XCTAssertEqual(c.pending, replacement); XCTAssertTrue(c.messages.isEmpty)
    }
    func testCallerCancellationCannotPublishLateAcceptedResponse() async throws {
        let h = try Harness(); h.http.hold = true; let c = try h.coordinator()
        try c.reviewText("original"); let review = try XCTUnwrap(c.pending)
        let task = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(0)
        task.cancel(); h.http.finish(0); await task.value
        XCTAssertTrue(c.messages.isEmpty); XCTAssertEqual(c.pending, review)
        XCTAssertEqual(c.failure, .unknownOutcome); XCTAssertFalse(c.busy)
    }
    func testInterruptedRegenerationPreservesOriginalAnswerAndReplacesItOnlyOnce() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("question"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        let original = c.messages; h.time.addTimeInterval(2); h.http.hold = true
        try c.reviewRegeneration(answerID: original[1].id); let review = try XCTUnwrap(c.pending)
        let old = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(1)
        c.suspend(); c.resumeAfterInterruption(); XCTAssertEqual(c.messages, original)
        h.time.addTimeInterval(2)
        let retry = Task { await c.transmit(reviewID: review.id) }; try await h.http.waitFor(2)
        h.http.finish(2, answer: "new approved answer"); await retry.value
        h.http.finish(1); await old.value
        XCTAssertEqual(c.messages.count, 2); XCTAssertEqual(c.messages[1].id, original[1].id)
        XCTAssertEqual(c.messages[1].text, "new approved answer")
        XCTAssertEqual(try body(h.http.requests[1]), try body(h.http.requests[2]))
    }
    func testVoiceGrantRevocationWhileSuspendedPreventsResumeAndUpload() throws {
        let h = try Harness(); h.grants.voiceTransmission = true; h.grants.voiceFormatVerified = true
        let c = try h.coordinator(); try c.reviewVoice(.init(bytes: Data([1]), duration: 1))
        c.suspend(); h.grants.voiceTransmission = false; c.resumeAfterInterruption()
        XCTAssertFalse(c.active); XCTAssertNil(c.pending); XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testQueuedIntentFromBeforeBackgroundCannotSendAfterResume() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("queued question"); let review = try XCTUnwrap(c.pending)
        let queued = try c.prepareTransmission(reviewID: review.id)
        // The UI Task has not begun. These lifecycle events happen before its first instruction.
        c.suspend(); c.resumeAfterInterruption()
        await c.transmit(reviewID: review.id, intent: queued)
        XCTAssertTrue(h.http.requests.isEmpty); XCTAssertEqual(c.pending, review); XCTAssertNil(c.failure)
        let explicitNewAction = try c.prepareTransmission(reviewID: review.id)
        await c.transmit(reviewID: review.id, intent: explicitNewAction)
        XCTAssertEqual(h.http.requests.count, 1); XCTAssertEqual(c.messages.count, 2)
    }
    func testCapturedIntentIsConsumedOnceAndCannotDispatchDuplicateTask() async throws {
        let h = try Harness(); h.http.hold = true; let c = try h.coordinator()
        try c.reviewText("one action"); let review = try XCTUnwrap(c.pending)
        let intent = try c.prepareTransmission(reviewID: review.id)
        let first = Task { await c.transmit(reviewID: review.id, intent: intent) }; try await h.http.waitFor(0)
        await c.transmit(reviewID: review.id, intent: intent)
        XCTAssertEqual(h.http.requests.count, 1); XCTAssertTrue(c.busy); XCTAssertNil(c.failure)
        h.http.finish(0); await first.value
        await c.transmit(reviewID: review.id, intent: intent)
        XCTAssertEqual(h.http.requests.count, 1); XCTAssertEqual(c.messages.count, 2)
    }
    func testQueuedIntentCannotReturnAfterExitOrReplaceANewerExplicitAction() async throws {
        let h = try Harness(); let c = try h.coordinator()
        try c.reviewText("reviewed question"); let review = try XCTUnwrap(c.pending)
        let earlier = try c.prepareTransmission(reviewID: review.id)
        let newer = try c.prepareTransmission(reviewID: review.id)
        await c.transmit(reviewID: review.id, intent: earlier)
        XCTAssertTrue(h.http.requests.isEmpty); XCTAssertEqual(c.pending, review)
        c.invalidate()
        await c.transmit(reviewID: review.id, intent: newer)
        XCTAssertTrue(h.http.requests.isEmpty); XCTAssertNil(c.pending); XCTAssertFalse(c.active)
    }

}
