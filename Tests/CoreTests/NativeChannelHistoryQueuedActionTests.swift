import XCTest
@testable import QuestifyCore

/// Real history-model admission against synthetic original cursor pages only.
/// No native read-through producer, transport grant or network is supplied.
final class NativeChannelHistoryQueuedActionTests: XCTestCase {
    @MainActor func testPreparedInitialLoadUsesOriginalReaderAndKeepsNewCapabilitiesClosed() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100])])
        let model = try model(reader)
        model.activate()
        let action = try XCTUnwrap(model.prepare(.load))
        await model.perform(action)
        XCTAssertEqual(reader.cursors, [0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [100])
        XCTAssertFalse(model.client.canLoadNewer)
        XCTAssertFalse(model.client.canReadThrough)
        XCTAssertNil(model.prepare(.newer))
        model.observed(100)
        XCTAssertNil(model.prepare(.markSeen))
    }

    @MainActor func testStoppedThenReactivatedVisitCannotConsumeOldQueuedLoad() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100]), try page([40])])
        let model = try model(reader)
        model.activate(); await model.load()
        let old = try XCTUnwrap(model.prepare(.load))
        model.stop(); model.activate()
        await model.perform(old)
        XCTAssertEqual(reader.cursors, [0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [100])
        let fresh = try XCTUnwrap(model.prepare(.load))
        await model.perform(fresh)
        XCTAssertEqual(reader.cursors, [0, 0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [40])
    }

    @MainActor func testPreparedActionCannotBeAppliedToReplacementModel() async throws {
        let firstReader = QueuedChannelHistoryReader(pages: [try page([100])])
        let secondReader = QueuedChannelHistoryReader(pages: [try page([40])])
        let first = try model(firstReader), second = try model(secondReader)
        first.activate(); second.activate()
        let firstAction = try XCTUnwrap(first.prepare(.load))
        await second.perform(firstAction)
        XCTAssertTrue(firstReader.cursors.isEmpty)
        XCTAssertTrue(secondReader.cursors.isEmpty)
        XCTAssertFalse(second.loaded)
        let secondAction = try XCTUnwrap(second.prepare(.load))
        await second.perform(secondAction)
        XCTAssertEqual(secondReader.cursors, [0])
        XCTAssertEqual(second.visibleMessages.map(\.id), [40])
    }

    @MainActor func testPreparedOlderUsesExactCursorButCannotSurviveReplacementRead() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100], cursor: 17, more: true), try page([40])])
        let model = try model(reader)
        model.activate(); await model.load()
        let older = try XCTUnwrap(model.prepare(.older))
        await model.load()
        await model.perform(older)
        XCTAssertEqual(reader.cursors, [0, 0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [40])
        XCTAssertNil(model.prepare(.older))
    }

    @MainActor func testCurrentPreparedOlderRunsOriginalOperationExactlyOnce() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100], cursor: 17, more: true), try page([90])])
        let model = try model(reader)
        model.activate(); await model.load()
        let older = try XCTUnwrap(model.prepare(.older))
        await model.perform(older)
        await model.perform(older)
        XCTAssertEqual(reader.cursors, [0, 17])
        XCTAssertEqual(model.visibleMessages.map(\.id), [90, 100])
    }

    @MainActor func testQueuedDuplicateLoadDoesNotBecomeAnotherReadAfterFirstFinishes() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100]), try page([40])])
        let model = try model(reader)
        model.activate()
        let first = try XCTUnwrap(model.prepare(.load)), duplicate = try XCTUnwrap(model.prepare(.load))
        await model.perform(first)
        await model.perform(duplicate)
        XCTAssertEqual(reader.cursors, [0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [100])
    }

    @MainActor func testCancelledQueuedActionDoesNotEnterModelOrCreateFailedRead() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100])])
        let model = try model(reader)
        model.activate()
        let action = try XCTUnwrap(model.prepare(.load))
        let pending = Task { await model.perform(action) }
        pending.cancel()
        await pending.value
        XCTAssertTrue(reader.cursors.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.loaded)
        XCTAssertNil(model.issue)
        XCTAssertNil(model.failedOperation)
    }

    @MainActor func testRevokedOrChangedReaderIdentityVetoesQueuedAction() async throws {
        for replaceIdentity in [false, true] {
            let reader = QueuedChannelHistoryReader(pages: [try page([100])])
            let model = try model(reader)
            model.activate()
            let action = try XCTUnwrap(model.prepare(.load))
            if replaceIdentity { reader.identity = .init(accountID: 2, epoch: 2) }
            else { reader.isConfigured = false }
            await model.perform(action)
            XCTAssertTrue(reader.cursors.isEmpty)
            XCTAssertNil(model.prepare(.load))
            XCTAssertNil(model.issue)
        }
    }

    @MainActor func testPreparedRetryUsesOriginalFailedOlderCursor() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100], cursor: 17, more: true), try page([90])])
        let model = try model(reader)
        model.activate(); await model.load()
        reader.failure = APIError.malformedResponse
        await model.older()
        XCTAssertEqual(model.failedOperation, .older(17))
        let retry = try XCTUnwrap(model.prepare(.retry))
        reader.failure = nil
        await model.perform(retry)
        XCTAssertEqual(reader.cursors, [0, 17, 17])
        XCTAssertEqual(model.visibleMessages.map(\.id), [90, 100])
        XCTAssertNil(model.failedOperation)
    }

    @MainActor func testRetiredRetryCannotBorrowNewVisitFailureOrPage() async throws {
        let reader = QueuedChannelHistoryReader(pages: [try page([100], cursor: 17, more: true), try page([40])])
        let model = try model(reader)
        model.activate(); await model.load()
        reader.failure = APIError.malformedResponse
        await model.older()
        let retry = try XCTUnwrap(model.prepare(.retry))
        model.stop(); model.activate(); reader.failure = nil
        await model.load()
        await model.perform(retry)
        XCTAssertEqual(reader.cursors, [0, 17, 0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [40])
        XCTAssertNil(model.failedOperation)
    }

    @MainActor private func model(_ reader: QueuedChannelHistoryReader) throws -> NativeChannelHistoryModel {
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_12"}}"#.utf8))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let client = NativeChannelSessionClient(history: reader, currentSession: { session }, isAvailable: { true })
        return NativeChannelHistoryModel(conversation: conversation, client: client)
    }

    private func page(_ ids: [Int], cursor: Int? = nil, more: Bool = false) throws -> MessagingPage {
        var value: [String: Any] = ["list": ids.map { ["id": $0, "conversationId": 9, "status": 0] }, "hasMore": more]
        if let cursor { value["nextCursor"] = cursor }
        return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

@MainActor private final class QueuedChannelHistoryReader: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 1, epoch: 1)
    var pages: [MessagingPage]
    var failure: Error?
    var cursors: [Int] = []
    init(pages: [MessagingPage]) { self.pages = pages }
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        cursors.append(cursor)
        if let failure { throw failure }
        guard !pages.isEmpty else { throw APIError.malformedResponse }
        return pages.removeFirst()
    }
}
