import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class NativeChannelHistoryLaunchTests: XCTestCase {
    private func page(_ ids: [Int], conversation: Int = 9, cursor: Int? = nil,
                      more: Bool = false, contents: [String]? = nil) throws -> MessagingPage {
        var value: [String: Any] = ["list": ids.enumerated().map { index, id -> [String: Any] in
            var row: [String: Any] = ["id": id, "conversationId": conversation, "status": 0]
            if let contents { row["content"] = contents[index] }
            return row
        }, "hasMore": more]
        if let cursor { value["nextCursor"] = cursor }
        return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testNewerDuplicatesUseLastIncomingCopyWithoutSortingIDs() throws {
        var history = NativeChannelHistory(conversationID: 9)
        try history.replace(page([100]))
        try history.append(page([40, 30, 40], contents: ["old", "middle", "updated"]),
                           requestedAfter: 100, nextAfter: 40)
        XCTAssertEqual(history.messages.map(\.id), [100, 40, 30])
        XCTAssertEqual(history.messages.map(\.content), [nil, "updated", "middle"])
        XCTAssertEqual(history.nextAfter, 40) // wire cutoff, not the deduplicated last row or max ID
    }

    func testOlderOverlapRefreshesNewerPayloadWithoutMovingItsPosition() throws {
        var history = NativeChannelHistory(conversationID: 9)
        try history.replace(page([100], cursor: 17, more: true))
        try history.append(page([40, 120], contents: ["before", "tail"]), requestedAfter: 100, nextAfter: 120)
        try history.prepend(page([90, 40, 40], contents: ["older", "stale", "refreshed"]), cursor: 17)
        XCTAssertEqual(history.messages.map(\.id), [90, 100, 40, 120])
        XCTAssertEqual(history.messages.first { $0.id == 40 }?.content, "refreshed")
        XCTAssertEqual(history.nextAfter, 120)
    }

    func testMalformedPagesAreAtomicForBothDirectionsAndReplacement() throws {
        var history = NativeChannelHistory(conversationID: 9)
        try history.replace(page([100], cursor: 17, more: true))
        try history.append(page([40]), requestedAfter: 100, nextAfter: 40)
        let before = history
        XCTAssertThrowsError(try history.replace(page([200], conversation: 8)))
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.prepend(page([90], conversation: 8), cursor: 17))
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.prepend(page([90]), cursor: 18))
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.append(page([30], conversation: 8), requestedAfter: 40, nextAfter: 30))
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.append(page([30]), requestedAfter: 100, nextAfter: 30))
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.append(page([30]), requestedAfter: 40, nextAfter: 31))
        XCTAssertEqual(history, before)
        let oversized = try page(Array(1...51))
        XCTAssertThrowsError(try history.replace(oversized))
        XCTAssertThrowsError(try history.prepend(oversized, cursor: 17))
        XCTAssertThrowsError(try history.append(oversized, requestedAfter: 40, nextAfter: 51))
        XCTAssertEqual(history, before)
    }

    func testCursorCyclesAndEmptyNewerPageCannotEraseOrAdvanceHistory() throws {
        var history = NativeChannelHistory(conversationID: 9)
        try history.replace(page([100], cursor: 17, more: true))
        try history.prepend(page([90], cursor: 12, more: true), cursor: 17)
        let before = history
        XCTAssertThrowsError(try history.prepend(page([80], cursor: 17, more: true), cursor: 12))
        XCTAssertThrowsError(try history.append(page([], cursor: 1, more: true), requestedAfter: 100, nextAfter: 100))
        XCTAssertThrowsError(try history.append(page([]), requestedAfter: 100, nextAfter: 99))
        XCTAssertEqual(history, before)
        try history.append(page([]), requestedAfter: 100, nextAfter: 100)
        XCTAssertEqual(history.messages.map(\.id), [90, 100])
        try history.append(page([40]), requestedAfter: 100, nextAfter: 40)
        let caughtUp = history
        XCTAssertThrowsError(try history.append(page([100]), requestedAfter: 40, nextAfter: 100))
        XCTAssertEqual(history, caughtUp)
    }

    @MainActor func testSeenThroughUsesServerPositionAcrossPrependAndLateApproval() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100, 110], cursor: 17, more: true), try page([90])])
        let transport = LaunchHistoryTransport([
            (#"{"code":200,"data":{"list":[{"id":40,"conversationId":9,"status":0}],"hasMore":false,"nextAfter":40}}"#, 200),
            (receipt(40, unread: 3), 200)
        ])
        let model = try model(reader, transport)
        model.activate(); await model.load()
        model.observed(110); model.observed(999); model.observed(100)
        XCTAssertEqual(model.seenThrough, 110)
        await model.older(); model.observed(100)
        XCTAssertEqual(model.seenThrough, 110)
        await model.newer(); model.observed(40); model.observed(110)
        XCTAssertEqual(model.seenThrough, 40)
        XCTAssertEqual(model.visibleMessages.map(\.id), [90, 100, 110, 40])
        XCTAssertNil(model.receipt)
        XCTAssertEqual(transport.requests.count, 1) // page completion never marks read
        await model.markSeen()
        XCTAssertEqual(model.receipt?.readTo, 40)
        XCTAssertEqual(model.receipt?.unread, 3)
    }

    @MainActor func testUnknownReadLocksOriginalCutoffEvenAfterObservationAdvances() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100, 40])])
        let transport = LaunchHistoryTransport([(#"{"code":500}"#, 500), (receipt(100), 200)])
        let model = try model(reader, transport)
        model.activate(); await model.load(); model.observed(100); await model.markSeen()
        model.observed(40)
        await model.markSeen(); await model.load(); await model.newer()
        XCTAssertEqual(model.failedOperation, .read(100))
        XCTAssertNil(model.receipt)
        XCTAssertEqual(reader.cursors, [0])
        XCTAssertEqual(transport.requests.count, 1)
        model.stop(); model.activate()
        XCTAssertEqual(transport.requests.count, 1)
        await model.retry()
        XCTAssertEqual(model.receipt?.readTo, 100)
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests { assertRead(request, target: 100) }
    }

    @MainActor func testHTTPReadRejectionRecoversByReloadingInsteadOfRetryingUnloadedTarget() async throws {
        for status in [401, 403, 404] {
            let reader = LaunchHistoryReader(pages: [try page([40]), try page([30])])
            let transport = LaunchHistoryTransport([("{\"code\":\(status)}", status)])
            let model = try model(reader, transport)
            model.activate(); await model.load(); model.observed(40); await model.markSeen()
            XCTAssertTrue(model.visibleMessages.isEmpty)
            XCTAssertNil(model.seenThrough)
            XCTAssertNil(model.receipt)
            XCTAssertEqual(model.failedOperation, .latest, "HTTP \(status)")
            await model.retry()
            XCTAssertEqual(reader.cursors, [0, 0])
            XCTAssertEqual(model.visibleMessages.map(\.id), [30])
            XCTAssertNil(model.failedOperation)
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    @MainActor func testClosedConversationDuringOlderReadCanRecoverWithFreshLatestPage() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100], cursor: 17, more: true), try page([40])])
        let model = try model(reader, LaunchHistoryTransport([]))
        model.activate(); await model.load(); model.observed(100)
        reader.failure = MessagingReadFailure(code: 409, errorCode: "IM_CONVERSATION_CLOSED")
        await model.older()
        XCTAssertTrue(model.visibleMessages.isEmpty)
        XCTAssertEqual(model.failedOperation, .latest)
        reader.failure = nil
        await model.retry()
        XCTAssertEqual(reader.cursors, [0, 17, 0])
        XCTAssertEqual(model.visibleMessages.map(\.id), [40])
    }

    @MainActor func testAmbiguousHTTPFailureWithRejectionMetadataStillPreservesUnknownCutoff() async throws {
        for status in [302, 408, 429, 500, 503] {
            let reader = LaunchHistoryReader(pages: [try page([40])])
            let transport = LaunchHistoryTransport([(#"{"code":403}"#, status), (receipt(40), 200)])
            let model = try model(reader, transport)
            model.activate(); await model.load(); model.observed(40); await model.markSeen()
            XCTAssertEqual(model.failedOperation, .read(40), "HTTP \(status)")
            XCTAssertEqual(model.visibleMessages.map(\.id), [40])
            await model.retry()
            XCTAssertEqual(model.receipt?.readTo, 40)
            XCTAssertEqual(reader.cursors, [0])
        }
    }

    @MainActor func testStoppedLatestResponseCannotOverwriteReactivatedScreen() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100]), try page([40])])
        let model = try model(reader, LaunchHistoryTransport([]))
        model.activate(); await model.load()
        let dispatched = expectation(description: "latest request suspended")
        reader.pause = true; reader.onPause = { dispatched.fulfill() }
        let pending = Task { await model.load() }
        await fulfillment(of: [dispatched], timeout: 1)
        model.stop(); XCTAssertTrue(model.visibleMessages.isEmpty)
        model.activate(); reader.pause = false
        await model.load()
        reader.finish(try page([999])); await pending.value
        XCTAssertEqual(model.visibleMessages.map(\.id), [40])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.issue)
    }

    @MainActor func testStoppedReadResponseRequiresExplicitSameCutoffRetry() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100, 40])])
        let transport = LaunchHistoryTransport([(receipt(100), 200), (receipt(100), 200)])
        let model = try model(reader, transport)
        model.activate(); await model.load(); model.observed(100)
        let dispatched = expectation(description: "read suspended")
        transport.pause = true; transport.onPause = { dispatched.fulfill() }
        let pending = Task { await model.markSeen() }
        await fulfillment(of: [dispatched], timeout: 1)
        model.stop(); model.activate(); model.observed(40)
        await model.load(); await model.markSeen()
        transport.finish(); await pending.value
        XCTAssertNil(model.receipt)
        XCTAssertEqual(model.failedOperation, .read(100))
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(reader.cursors, [0])
        transport.pause = false
        await model.retry()
        XCTAssertEqual(model.receipt?.readTo, 100)
        for request in transport.requests { assertRead(request, target: 100) }
    }

    @MainActor func testWrongConversationResponseKeepsSnapshotAndRetryUsesSamePageCursor() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100], cursor: 17, more: true),
                                                try page([90], conversation: 8), try page([80])])
        let model = try model(reader, LaunchHistoryTransport([]))
        model.activate(); await model.load(); await model.older()
        XCTAssertEqual(model.visibleMessages.map(\.id), [100])
        XCTAssertEqual(model.failedOperation, .older(17))
        await model.retry()
        XCTAssertEqual(reader.cursors, [0, 17, 17])
        XCTAssertEqual(model.visibleMessages.map(\.id), [80, 100])
    }

    @MainActor func testSessionReaderUnauthorizedClearsHistoryForRefreshAndOlderRetry() async throws {
        for older in [false, true] {
            let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!)
            let transport = LaunchHistoryTransport([
                (#"{"code":200,"data":{"list":[{"id":100,"conversationId":9,"status":0}],"nextCursor":17,"hasMore":true}}"#, 200),
                (#"{"code":401}"#, 401),
                (#"{"code":200,"data":{"list":[{"id":40,"conversationId":9,"status":0}],"hasMore":false}}"#, 200)
            ])
            let session = try MessagingReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
            var unauthorized = 0
            let reader = MessagingSessionReader(service: MessagingService(configuration: configuration, transport: transport),
                currentSession: { session }, onUnauthorized: { _ in unauthorized += 1 })
            let model = try model(reader, LaunchHistoryTransport([]))
            model.activate(); await model.load(); model.observed(100)
            if older { await model.older() } else { await model.load() }
            XCTAssertEqual(unauthorized, 1)
            XCTAssertEqual(model.issue as? APIError, .unauthorized)
            XCTAssertTrue(model.visibleMessages.isEmpty)
            XCTAssertNil(model.detailMessage(100))
            XCTAssertFalse(model.loaded)
            XCTAssertNil(model.seenThrough)
            XCTAssertEqual(model.failedOperation, .latest)
            model.stop(); model.activate()
            XCTAssertEqual(transport.requests.count, 2) // reactivation never retries implicitly
            await model.retry()
            XCTAssertEqual(model.visibleMessages.map(\.id), [40])
            let body = String(data: transport.requests[2].httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"cursor_id\"\r\n\r\n0\r\n"))
        }
    }

    @MainActor func testNewReadClearsPreviousReceiptBeforeDispatchAndUnknownRetry() async throws {
        let reader = LaunchHistoryReader(pages: [try page([100, 40])])
        let transport = LaunchHistoryTransport([(receipt(100, unread: 3), 200),
                                                (#"{"code":500}"#, 500), (receipt(40, unread: 1), 200)])
        let model = try model(reader, transport)
        model.activate(); await model.load(); model.observed(100); await model.markSeen()
        XCTAssertEqual(model.receipt?.unread, 3)
        model.observed(40)
        let dispatched = expectation(description: "replacement read dispatched")
        transport.pause = true; transport.onPause = { dispatched.fulfill() }
        let pending = Task { await model.markSeen() }
        await fulfillment(of: [dispatched], timeout: 1)
        XCTAssertNil(model.receipt) // prior success cannot represent this in-flight cutoff
        transport.finish(); await pending.value
        XCTAssertNil(model.receipt)
        XCTAssertEqual(model.failedOperation, .read(40))
        XCTAssertEqual(model.visibleMessages.map(\.id), [100, 40])
        model.stop(); model.activate()
        transport.pause = false
        await model.retry()
        XCTAssertEqual(model.receipt?.readTo, 40)
        XCTAssertEqual(model.receipt?.unread, 1)
        XCTAssertEqual(transport.requests.count, 3)
        for request in transport.requests.dropFirst() { assertRead(request, target: 40) }
    }

    @MainActor private func model(_ reader: any MessagingReading, _ transport: LaunchHistoryTransport) throws -> NativeChannelHistoryModel {
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":9,"type":4}"#.utf8))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let service = NativeChannelService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
                                           transport: transport, allowsNewer: true, allowsReadReceipt: true)
        let client = NativeChannelSessionClient(history: reader, service: service, currentSession: { session }, isAvailable: { true })
        return NativeChannelHistoryModel(conversation: conversation, client: client)
    }
    private func receipt(_ target: Int, unread: Int = 0) -> String {
        "{\"code\":200,\"data\":{\"conversationId\":9,\"readTo\":\(target),\"lastReadMessageId\":\(target),\"unread\":\(unread)}}"
    }
    private func assertRead(_ request: URLRequest, target: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.url?.path, "/fixture/api/native/channels/read-through", file: file, line: line)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"conversation_id\"\r\n\r\n9\r\n"), file: file, line: line)
        XCTAssertTrue(body.contains("name=\"read_to\"\r\n\r\n\(target)\r\n"), file: file, line: line)
    }
}

@MainActor private final class LaunchHistoryReader: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 1, epoch: 1)
    var pages: [MessagingPage]
    var cursors: [Int] = []
    var failure: Error?
    var pause = false
    var onPause: (() -> Void)?
    private var continuation: CheckedContinuation<MessagingPage, Error>?
    init(pages: [MessagingPage]) { self.pages = pages }
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        cursors.append(cursor)
        if let failure { throw failure }
        if pause {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation; onPause?()
            }
        }
        guard !pages.isEmpty else { throw APIError.malformedResponse }
        return pages.removeFirst()
    }
    func finish(_ page: MessagingPage) { continuation?.resume(returning: page); continuation = nil }
}

@MainActor private final class LaunchHistoryTransport: HTTPTransport {
    var replies: [(String, Int)]
    var requests: [URLRequest] = []
    var pause = false
    var onPause: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ replies: [(String, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw APIError.malformedResponse }
        let reply = replies.removeFirst()
        if pause {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; onPause?()
            }
        }
        return (Data(reply.0.utf8), reply.1)
    }
    func finish() { continuation?.resume(); continuation = nil }
}
