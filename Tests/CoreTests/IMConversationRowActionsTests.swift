import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class IMConversationRowActionsTests: XCTestCase {
    private func conversation(unread: Int = 3, muted: String = "0") throws -> MessagingConversation {
        try JSONDecoder().decode(MessagingConversation.self, from: Data("{\"conversationId\":9,\"unread\":\(unread),\"muted\":\(muted)}".utf8))
    }
    private func make(_ writer: Writer, _ reader: Reader, row: MessagingConversation? = nil,
                      owner: IMExpandedCoordinator? = nil) throws -> IMConversationRowActions {
        let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
        return IMConversationRowActions(conversation: try row ?? conversation(), identity: identity,
            coordinator: try owner ?? IMExpandedCoordinator(scope: IMScope(identity: identity, conversationID: 9), writer: writer), reader: reader)
    }
    func testAvailableActionsUseOnlyConfirmedUnreadAndMuteFields() throws {
        XCTAssertEqual(IMConversationRowAction.available(for: try conversation()), [.markRead, .setMuted(true)])
        XCTAssertEqual(IMConversationRowAction.available(for: try conversation(unread: 0, muted: "1")), [.setMuted(false)])
        XCTAssertEqual(IMConversationRowAction.available(for: try conversation(unread: 0, muted: "null")), [])
        XCTAssertNil(IMConversationRowAction(mutation: .start(targetMemberID: 9), conversationID: 9))
        XCTAssertNil(IMConversationRowAction(mutation: .read(conversationID: 8), conversationID: 9))
    }
    func testOpeningAndCancellingReviewNeverDispatches() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        XCTAssertTrue(actions.prepare(.markRead)); XCTAssertTrue(writer.mutations.isEmpty)
        actions.cancelReview(); XCTAssertEqual(actions.state, .idle)
        let accepted = await actions.confirm(); XCTAssertFalse(accepted)
        XCTAssertTrue(writer.mutations.isEmpty); XCTAssertEqual(reader.reads, 0)
    }
    func testExactReadAndMuteAcknowledgmentsRequestRefreshWithoutPatchingRows() async throws {
        for action in [IMConversationRowAction.markRead, .setMuted(true)] {
            let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
            XCTAssertTrue(actions.prepare(action)); let accepted = await actions.confirm()
            XCTAssertTrue(accepted); XCTAssertEqual(writer.mutations, [action.mutation(conversationID: 9)])
            XCTAssertEqual(actions.conversation.unread, 3); XCTAssertEqual(actions.conversation.muted, false)
            // This adapter is not a readback. The list host must fetch server rows.
            XCTAssertEqual(reader.reads, 0)
            let duplicate = await actions.confirm(); XCTAssertFalse(duplicate)
            XCTAssertEqual(writer.mutations.count, 1)
        }
    }
    func testUnknownReopenUsesOriginalActionAndExplicitSameIntentRetry() async throws {
        let writer = Writer(), reader = Reader(), first = try make(writer, reader)
        writer.error = URLError(.timedOut)
        XCTAssertTrue(first.prepare(.setMuted(true)))
        let accepted = await first.confirm(); XCTAssertFalse(accepted)
        first.cancelReview()
        let reopened = try make(writer, reader, owner: first.coordinator)
        XCTAssertTrue(reopened.prepare(.markRead)); XCTAssertEqual(reopened.action, .setMuted(true))
        XCTAssertEqual(writer.mutations, [.mute(conversationID: 9, muted: true)])
        writer.error = nil
        let retry = await reopened.retryUnchanged(); XCTAssertTrue(retry)
        XCTAssertEqual(writer.mutations, [.mute(conversationID: 9, muted: true), .mute(conversationID: 9, muted: true)])
    }
    func testUnknownMessageCannotBeReplacedOrRetriedByRowControls() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        let intent = try IMOutgoingIntent(scope: actions.coordinator.scope, payload: .route(topicID: 11))
        writer.error = URLError(.timedOut)
        XCTAssertTrue(actions.coordinator.review(.send(intent))); await actions.coordinator.confirm()
        XCTAssertFalse(actions.canPrepare); XCTAssertFalse(actions.prepare(.markRead))
        let accepted = await actions.retryUnchanged(); XCTAssertFalse(accepted)
        XCTAssertEqual(writer.mutations, [.send(intent)])
    }
    func testDormantExpiredAndMismatchedScopeDoNotReviewOrDispatch() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        writer.isConfigured = false; XCTAssertFalse(actions.prepare(.markRead))
        writer.isConfigured = true; reader.isConfigured = false; XCTAssertFalse(actions.prepare(.markRead))
        reader.isConfigured = true; reader.identity = .init(accountID: 7, epoch: 2)
        XCTAssertFalse(actions.prepare(.markRead))
        reader.identity = .init(accountID: 7, epoch: 1)
        let wrong = IMExpandedCoordinator(scope: try IMScope(identity: reader.identity!, conversationID: 8), writer: writer)
        let mismatched = try make(writer, reader, owner: wrong)
        XCTAssertFalse(mismatched.prepare(.markRead)); XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testAccountChangeDuringReplyNeverRequestsListRefresh() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        XCTAssertTrue(actions.prepare(.markRead))
        writer.beforeReturn = { reader.identity = .init(accountID: 8, epoch: 2); writer.identity = reader.identity }
        let accepted = await actions.confirm(); XCTAssertFalse(accepted); XCTAssertEqual(actions.state, .idle)
    }
    func testReadRevocationDuringReplyNeverRequestsListRefresh() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        XCTAssertTrue(actions.prepare(.markRead)); writer.beforeReturn = { reader.isConfigured = false }
        let accepted = await actions.confirm(); XCTAssertFalse(accepted)
    }
    func testMismatchedReceiptDoesNotRequestListRefresh() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        writer.receipt = .muted(false); XCTAssertTrue(actions.prepare(.setMuted(true)))
        let accepted = await actions.confirm(); XCTAssertFalse(accepted)
        XCTAssertFalse(actions.hasMatchingAcknowledgment)
    }
    func testSecondTapCannotDuplicateInFlightMutation() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        writer.suspend = true; XCTAssertTrue(actions.prepare(.markRead))
        let waiting = expectation(description: "row mutation suspended")
        writer.onSuspend = { waiting.fulfill() }
        let task = Task { await actions.confirm() }
        await fulfillment(of: [waiting], timeout: 2)
        let duplicate = await actions.confirm(); XCTAssertFalse(duplicate)
        XCTAssertTrue(actions.prepare(.setMuted(true))); XCTAssertEqual(actions.action, .markRead)
        XCTAssertEqual(writer.mutations, [.read(conversationID: 9)])
        writer.resume(); let accepted = await task.value; XCTAssertTrue(accepted)
    }
    func testBusinessRejectionDoesNotClearBadgeOrAutoRetry() async throws {
        let writer = Writer(), reader = Reader(), actions = try make(writer, reader)
        writer.error = MessagingReadFailure(code: 403)
        XCTAssertTrue(actions.prepare(.markRead)); let accepted = await actions.confirm(); XCTAssertFalse(accepted)
        XCTAssertEqual(actions.state, .rejected(.read(conversationID: 9)))
        XCTAssertEqual(actions.conversation.unread, 3)
        let retry = await actions.retryUnchanged(); XCTAssertFalse(retry); XCTAssertEqual(writer.mutations.count, 1)
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
        var mutations: [IMMutation] = []
        var error: Error?
        var receipt: IMMutationReceipt?
        var beforeReturn: (() -> Void)?
        var suspend = false, onSuspend: (() -> Void)?
        private var continuation: CheckedContinuation<Void, Never>?
        func resume() { let pending = continuation; continuation = nil; pending?.resume() }
        func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
            mutations.append(mutation)
            if suspend { await withCheckedContinuation { continuation = $0; onSuspend?() } }
            beforeReturn?(); if let error { throw error }; if let receipt { return receipt }
            switch mutation { case .read: return .read; case .mute(_, let muted): return .muted(muted); default: throw APIError.invalidRequest }
        }
        func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
    }
}
