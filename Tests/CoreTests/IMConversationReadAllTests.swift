import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class IMConversationReadAllTests: XCTestCase {
    private let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
    private func row(_ id: Int, type: Int? = 1, unread: Int? = 3, muted: Int = 0) throws -> MessagingConversation {
        let object: [String: Any] = ["conversationId": id, "type": type as Any? ?? NSNull(),
            "unread": unread as Any? ?? NSNull(), "muted": muted]
        return try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func owners(_ ids: [Int], _ writer: Writer) throws -> [Int: IMExpandedCoordinator] {
        try Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, IMExpandedCoordinator(scope: try IMScope(identity: identity, conversationID: id), writer: writer))
        })
    }
    private func batch(_ rows: [MessagingConversation], _ reader: Reader,
                       _ owners: [Int: IMExpandedCoordinator]) -> IMConversationReadAll {
        IMConversationReadAll(conversations: rows, identity: identity, reader: reader, coordinator: { owners[$0] })
    }
    func testFrozenEligibilityUsesAllLoadedKnownNonGroupUnreadRowsOnce() throws {
        let source = try [row(1), row(2, type: 2), row(3, type: 3, muted: 1), row(4, type: 4),
            row(5, type: 99), row(6, type: nil), row(7, unread: 0), row(8, unread: nil), row(1)]
        XCTAssertEqual(IMConversationReadAll.eligible(source).map(\.id), [1, 2, 3])
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2, 3], writer)
        var fetched = source
        let operation = batch(fetched, reader, owners)
        fetched.append(try row(9))
        XCTAssertEqual(operation.items.map(\.id), [1, 2, 3]); XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testReviewAndCancelWriteNothingAndDoNotReserveAnyOwner() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        let operation = batch(try [row(1), row(2)], reader, owners)
        XCTAssertTrue(operation.canConfirm); XCTAssertEqual(owners[1]?.visibleState, .idle)
        operation.stop(); await operation.confirm()
        XCTAssertEqual(operation.phase, .cancelled); XCTAssertTrue(writer.mutations.isEmpty)
        XCTAssertEqual(reader.reads, 0); XCTAssertEqual(owners[1]?.visibleState, .idle)
    }
    func testExplicitConfirmUsesExactReadMutationsWithoutEditingUnreadOrMuting() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2, 3], writer)
        let operation = batch(try [row(1), row(2, type: 2), row(3, type: 3, muted: 1)], reader, owners)
        await operation.confirm(); await operation.confirm()
        XCTAssertEqual(writer.mutations, [1, 2, 3].map { .read(conversationID: $0) })
        XCTAssertEqual(writer.expectedIdentities, Array(repeating: identity, count: 3))
        XCTAssertEqual(operation.acknowledgedCount, 3); XCTAssertEqual(operation.unknownCount, 0)
        XCTAssertEqual(operation.items.map { $0.conversation.unread }, [3, 3, 3])
        XCTAssertEqual(operation.items.last?.conversation.muted, true); XCTAssertEqual(reader.reads, 0)
    }
    func testPartialRejectionAndUnknownKeepIndividualResultsAndNeverAutoRetry() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2, 3], writer)
        writer.errors[2] = MessagingReadFailure(code: 403); writer.errors[3] = URLError(.timedOut)
        let operation = batch(try [row(1), row(2), row(3)], reader, owners)
        await operation.confirm()
        XCTAssertEqual(operation.items.map(\.outcome), [.acknowledged, .rejected, .outcomeUnknown])
        XCTAssertEqual(operation.acknowledgedCount, 1); XCTAssertEqual(operation.rejectedCount, 1)
        XCTAssertEqual(operation.unknownCount, 1); XCTAssertEqual(operation.remainingCount, 0)
        XCTAssertEqual(owners[3]?.visibleState, .outcomeUnknown(.read(conversationID: 3)))
        let reopened = batch(try [row(3)], reader, owners)
        XCTAssertFalse(reopened.canConfirm); await reopened.confirm()
        XCTAssertEqual(writer.mutations.count, 3)
    }
    func testPendingReadMuteSendAndReviewAreNeverReplaced() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2, 3, 4, 5], writer)
        writer.errors[1] = URLError(.timedOut); writer.errors[2] = URLError(.timedOut)
        writer.errors[3] = URLError(.timedOut)
        let intent = try IMOutgoingIntent(scope: XCTUnwrap(owners[3]).scope, payload: .route(topicID: 10))
        let prior: [IMMutation] = [.read(conversationID: 1), .mute(conversationID: 2, muted: true), .send(intent)]
        for (offset, mutation) in prior.enumerated() {
            let owner = try XCTUnwrap(owners[offset + 1]); XCTAssertTrue(owner.review(mutation)); await owner.confirm()
        }
        let review = IMMutation.mute(conversationID: 4, muted: false)
        XCTAssertTrue(try XCTUnwrap(owners[4]).review(review))
        let operation = batch(try [row(1), row(2), row(3), row(4), row(5)], reader, owners)
        await operation.confirm()
        XCTAssertEqual(writer.mutations, prior + [.read(conversationID: 5)])
        XCTAssertEqual(operation.items.map(\.outcome), [.protectedIntent, .protectedIntent, .protectedIntent, .protectedIntent, .acknowledged])
        XCTAssertEqual(owners[3]?.visibleState, .outcomeUnknown(.send(intent)))
        XCTAssertEqual(owners[4]?.visibleState, .reviewing(review))
    }
    func testAccountChangeAfterFirstReplyStopsRemainingFrozenItems() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        writer.beforeReturn = { _ in reader.identity = .init(accountID: 8, epoch: 2); writer.identity = reader.identity }
        let operation = batch(try [row(1), row(2)], reader, owners)
        await operation.confirm()
        XCTAssertEqual(writer.mutations, [.read(conversationID: 1)])
        XCTAssertFalse(operation.isCurrent); XCTAssertEqual(operation.unknownCount, 1)
        XCTAssertEqual(operation.items[1].outcome, .notAttempted)
    }
    func testReadAuthorityRevokedAfterFirstReplyStopsRemainingItems() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        writer.beforeReturn = { _ in reader.isConfigured = false }
        let operation = batch(try [row(1), row(2)], reader, owners)
        await operation.confirm()
        XCTAssertEqual(writer.mutations.count, 1); XCTAssertFalse(operation.isCurrent)
    }
    func testEachOriginalOwnerRechecksPermissionAndConversationBeforeDispatch() async throws {
        let first = Writer(), second = Writer(), reader = Reader()
        let a = try owners([1], first), b = try owners([2], second)
        first.beforeReturn = { _ in second.isConfigured = false }
        let operation = batch(try [row(1), row(2), row(3)], reader, [1: a[1]!, 2: b[2]!, 3: a[1]!])
        await operation.confirm()
        XCTAssertEqual(first.mutations, [.read(conversationID: 1)]); XCTAssertTrue(second.mutations.isEmpty)
        XCTAssertEqual(operation.items.map(\.outcome), [.acknowledged, .unavailable, .unavailable])
    }
    func testSynchronousReviewCallbackRevocationCannotDispatch() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        let operation = batch(try [row(1), row(2)], reader, owners)
        owners[1]?.onChange = { if let owner = owners[1], case .reviewing = owner.visibleState { reader.isConfigured = false } }
        await operation.confirm()
        XCTAssertTrue(writer.mutations.isEmpty); XCTAssertEqual(operation.attemptedCount, 0)
    }
    func testStopDuringSuspendedRequestKeepsReceiptAndStopsNextItem() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        writer.suspendID = 1
        let suspended = expectation(description: "first write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let operation = batch(try [row(1), row(2)], reader, owners)
        let task = Task { await operation.confirm() }
        await fulfillment(of: [suspended], timeout: 2)
        operation.stop(); await operation.confirm()
        XCTAssertEqual(writer.mutations.count, 1)
        writer.resume(); await task.value
        XCTAssertEqual(operation.items.map(\.outcome), [.acknowledged, .notAttempted])
        XCTAssertEqual(owners[1]?.visibleState, .acknowledged(.read))
        XCTAssertEqual(writer.maximumInFlight, 1)
    }
    func testCancelledTaskKeepsUnknownIntentAndStopsQueue() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1, 2], writer)
        writer.suspendID = 1
        let suspended = expectation(description: "write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let operation = batch(try [row(1), row(2)], reader, owners)
        let task = Task { await operation.confirm() }
        await fulfillment(of: [suspended], timeout: 2)
        task.cancel(); writer.resume(); await task.value
        XCTAssertEqual(writer.mutations.count, 1)
        XCTAssertEqual(owners[1]?.visibleState, .outcomeUnknown(.read(conversationID: 1)))
        XCTAssertEqual(operation.items.map(\.outcome), [.outcomeUnknown, .notAttempted])
    }
    func testLargeFrozenListHasBoundedConcurrencyAndOneAttemptPerID() async throws {
        let writer = Writer(), reader = Reader(), ids = Array(1...500)
        let owners = try owners(ids, writer), rows = try ids.map { try row($0) }
        let operation = batch(rows, reader, owners)
        await operation.confirm()
        XCTAssertEqual(writer.mutations.count, 500); XCTAssertEqual(writer.maximumInFlight, 1)
        XCTAssertEqual(operation.acknowledgedCount, 500); XCTAssertEqual(operation.phase, .finished)
    }
    func testDuplicateConfirmationDuringSubmissionDoesNotDispatchTwice() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1], writer)
        writer.suspendID = 1
        let suspended = expectation(description: "write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let operation = batch(try [row(1)], reader, owners)
        let task = Task { await operation.confirm() }
        await fulfillment(of: [suspended], timeout: 2)
        await operation.confirm(); XCTAssertEqual(writer.mutations.count, 1)
        writer.resume(); await task.value
    }
    func testDormantOrStaleScopeCannotConfirm() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1], writer)
        let operation = batch(try [row(1)], reader, owners)
        writer.isConfigured = false; XCTAssertFalse(operation.canConfirm); await operation.confirm()
        writer.isConfigured = true; reader.identity = .init(accountID: 7, epoch: 2)
        XCTAssertFalse(operation.canConfirm); await operation.confirm()
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testMismatchedReceiptIsNotReportedAsSuccess() async throws {
        let writer = Writer(), reader = Reader(), owners = try owners([1], writer)
        writer.receipts[1] = .muted(true)
        let operation = batch(try [row(1)], reader, owners)
        await operation.confirm()
        XCTAssertEqual(operation.acknowledgedCount, 0); XCTAssertEqual(operation.unknownCount, 1)
        XCTAssertEqual(writer.mutations.count, 1)
    }

    @MainActor private final class Reader: MessagingReading {
        var isConfigured = true
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var reads = 0
        func messagingConversations() async throws -> [MessagingConversation] { reads += 1; return [] }
        func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    }
    @MainActor private final class Writer: IMExpandedWriting {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true
        var mutations: [IMMutation] = [], expectedIdentities: [MessagingReadIdentity] = []
        var errors: [Int: Error] = [:], receipts: [Int: IMMutationReceipt] = [:]
        var beforeReturn: ((Int) -> Void)?
        var suspendID: Int?, didSuspend: (() -> Void)?
        var inFlight = 0, maximumInFlight = 0
        private var continuation: CheckedContinuation<Void, Never>?
        func resume() { let pending = continuation; continuation = nil; pending?.resume() }
        func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
            let id = mutation.conversationID ?? 0
            mutations.append(mutation); expectedIdentities.append(expectedIdentity)
            inFlight += 1; maximumInFlight = max(inFlight, maximumInFlight)
            defer { inFlight -= 1 }
            if suspendID == id { await withCheckedContinuation { continuation = $0; didSuspend?() } }
            beforeReturn?(id)
            if let error = errors[id] { throw error }
            return receipts[id] ?? .read
        }
        func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
    }
}
