import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class NativeChannelTests: XCTestCase {
    private func page(_ ids: [Int], conversation: Int = 9, cursor: Int? = nil, more: Bool = false) throws -> MessagingPage {
        var value: [String: Any] = ["list": ids.map { ["id": $0, "conversationId": conversation, "status": 0] }, "hasMore": more]
        if let cursor { value["nextCursor"] = cursor }
        return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func conversations() throws -> [MessagingConversation] {
        try JSONDecoder().decode([MessagingConversation].self, from: Data(#"[{"conversationId":1,"type":4,"counterparty":{"bizKey":"club_12","nickname":"Club"}},{"conversationId":2,"type":4,"counterparty":{"bizKey":"team_7"}},{"conversationId":3,"type":1,"counterparty":{"bizKey":"club_12"}},{"conversationId":4,"type":4,"counterparty":{"bizKey":"club_012"}},{"conversationId":5,"type":4,"counterparty":{"bizKey":"unknown_7"}},{"conversationId":6,"type":4,"counterparty":{"bizKey":"hangout_3"}}]"#.utf8))
    }
    func testDirectoryIncludesOnlyServerReturnedKnownGroupsAndExactSpaceIDs() throws {
        let spaces = NativeChannelSpace.project(try conversations())
        XCTAssertEqual(spaces.map(\.id), ["club_12", "team_7", "hangout_3"])
        XCTAssertEqual(spaces.flatMap(\.channels).map(\.id), [1, 2, 6])
        XCTAssertTrue(NativeChannelSpace.project([]).isEmpty)
    }
    func testLateApprovedLowerIDAppendsInVisibilityOrderAndOlderCursorIsIndependent() throws {
        var state = NativeChannelHistory(conversationID: 9)
        try state.replace(page([100, 110], cursor: 100, more: true))
        try state.append(page([40, 120], cursor: 120, more: true), requestedAfter: 110, nextAfter: 120)
        XCTAssertEqual(state.messages.map(\.id), [100, 110, 40, 120])
        XCTAssertEqual(state.older.nextCursor, 100)
        try state.prepend(page([90]), cursor: 100)
        XCTAssertEqual(state.messages.map(\.id), [90, 100, 110, 40, 120])
        XCTAssertEqual(state.nextAfter, 120)
    }
    func testBadNewerResponseCannotAdvanceOrEraseThePreviousPage() throws {
        var state = NativeChannelHistory(conversationID: 9)
        try state.replace(page([100]))
        let before = state
        XCTAssertThrowsError(try state.append(page([1], conversation: 8), requestedAfter: 100, nextAfter: 1))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.append(page([30]), requestedAfter: 100, nextAfter: 31))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.append(page([30]), requestedAfter: 99, nextAfter: 30))
        XCTAssertEqual(state, before)
        try state.append(page([30]), requestedAfter: 100, nextAfter: 30)
        XCTAssertEqual(state.messages.map(\.id), [100, 30])
    }
    func testEmptyCatchupDoesNotAdvanceAndCyclesAreRejected() throws {
        var state = NativeChannelHistory(conversationID: 9)
        try state.replace(page([100]))
        try state.append(page([]), requestedAfter: 100, nextAfter: 100)
        try state.append(page([40]), requestedAfter: 100, nextAfter: 40)
        let before = state
        XCTAssertThrowsError(try state.append(page([100]), requestedAfter: 40, nextAfter: 100))
        XCTAssertEqual(state, before)
    }
    func testUnknownStatusNeverExposesPayloadInChannelHistory() throws {
        let page = try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[{"id":1,"conversationId":9,"status":9,"content":"private","extraJson":"private"}],"hasMore":false}"#.utf8))
        var history = NativeChannelHistory(conversationID: 9)
        try history.replace(page)
        XCTAssertNil(history.messages[0].content)
        XCTAssertNil(history.messages[0].extraJSON)
    }
    func testCapabilitiesAreClosedByDefaultAndDoNotSend() async throws {
        let transport = MessagingTestTransport([])
        let service = NativeChannelService(configuration: try configuration(), transport: transport)
        do { _ = try await service.newer(conversationID: 9, after: 0, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await service.readThrough(conversationID: 9, readTo: 4, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testIncrementalUsesAfterIDWithoutNumericMaxOrCursorAndIsBounded() async throws {
        let transport = MessagingTestTransport([.json(#"{"code":200,"data":{"list":[{"id":40,"conversationId":9,"status":0}],"nextCursor":40,"nextAfter":40,"hasMore":false}}"#)])
        let config = try configuration()
        let service = NativeChannelService(configuration: config, transport: transport, allowsNewer: true)
        let page = try await service.newer(conversationID: 9, after: 100, token: "synthetic-token")
        XCTAssertEqual(page.nextAfter, 40)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(NativeChannelRuntimeRoute(request: request, baseURL: config.baseURL), .incremental(conversationID: 9, after: 100))
        XCTAssertNil(MessagingHistoryReadRoute(request: request, baseURL: config.baseURL))
    }
    func testReadReceiptRequiresExactTargetAndAllowsNonNumericVisibleOrder() async throws {
        let transport = MessagingTestTransport([.json(#"{"code":200,"data":{"conversationId":9,"readTo":40,"lastReadMessageId":3,"unread":5}}"#)])
        let config = try configuration()
        let service = NativeChannelService(configuration: config, transport: transport, allowsReadReceipt: true)
        let result = try await service.readThrough(conversationID: 9, readTo: 40, token: "synthetic-token")
        XCTAssertEqual(result.unread, 5)
        XCTAssertEqual(result.lastReadMessageId, 3)
        XCTAssertEqual(NativeChannelRuntimeRoute(request: try XCTUnwrap(transport.requests.first), baseURL: config.baseURL), .readThrough(conversationID: 9, target: 40))
    }
    func testIndependentChannelFeaturesDoNotBorrowLegacyReadOrEachOther() throws {
        let incremental = try BusinessRuntimeRoute.post("api/im/messages")
        let receipt = try BusinessRuntimeRoute.post("api/native/channels/read-through")
        XCTAssertTrue(BusinessRuntimeFeature.nativeChannelIncrementalRead.accepts(incremental))
        XCTAssertTrue(BusinessRuntimeFeature.nativeChannelReadReceipt.accepts(receipt))
        XCTAssertFalse(BusinessRuntimeFeature.nativeChannelIncrementalRead.accepts(receipt))
        XCTAssertFalse(BusinessRuntimeFeature.nativeChannelReadReceipt.accepts(incremental))
        XCTAssertFalse(BusinessRuntimeFeature.imRead.accepts(receipt))
        XCTAssertFalse(BusinessRuntimeFeature.imRead.accepts(incremental))
    }
    func testRouteIndependentlyRejectsCookiesAndProxyCredentials() throws {
        let config = try configuration()
        var clean = try AuthRequestBuilder.makeFormRequest(
            url: config.baseURL.appendingPathComponent("api/native/channels/read-through"),
            fields: ["conversation_id": "9", "read_to": "4"], token: "synthetic-token")
        clean.httpShouldHandleCookies = false
        XCTAssertEqual(NativeChannelRuntimeRoute(request: clean, baseURL: config.baseURL), .readThrough(conversationID: 9, target: 4))
        for header in ["Cookie", "Cookie2", "Proxy-Authorization"] {
            var changed = clean
            changed.setValue("synthetic-unapproved-header", forHTTPHeaderField: header)
            XCTAssertNil(NativeChannelRuntimeRoute(request: changed, baseURL: config.baseURL))
        }
        var cookieHandling = clean
        cookieHandling.httpShouldHandleCookies = true
        XCTAssertNil(NativeChannelRuntimeRoute(request: cookieHandling, baseURL: config.baseURL))
    }
    func testRouteRejectsExtraIdentityZeroTargetAndQuery() throws {
        let config = try configuration()
        for fields in [["conversation_id":"9","read_to":"0"], ["conversation_id":"9","read_to":"4","member_id":"1"]] {
            var request = try AuthRequestBuilder.makeFormRequest(url: config.baseURL.appendingPathComponent("api/native/channels/read-through"), fields: fields, token: "synthetic-token")
            request.httpShouldHandleCookies = false
            XCTAssertNil(NativeChannelRuntimeRoute(request: request, baseURL: config.baseURL))
        }
    }
    @MainActor func testRetiredScreenCannotMarkReadOrRetainVisibleMessages() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([100, 40], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let client = NativeChannelSessionClient(history: reader, currentSession: { session }, isAvailable: { true })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load()
        owner.observed(100); owner.observed(40)
        XCTAssertEqual(owner.seenThrough, 40)
        owner.stop()
        XCTAssertTrue(owner.visibleMessages.isEmpty)
        XCTAssertEqual(owner.detailMessage(40)?.id, 40) // a pushed detail is still exact-session gated
        await owner.load()
        XCTAssertEqual(reader.pageCalls, 1)
    }
    @MainActor func testUnknownReceiptRetriesExactCutoffWithoutOptimisticUnreadReset() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([100, 40], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let transport = MessagingTestTransport([
            .json(#"{"code":500,"msg":"unknown"}"#),
            .json(#"{"code":200,"data":{"conversationId":1,"readTo":40,"lastReadMessageId":40,"unread":3}}"#)
        ])
        let service = NativeChannelService(configuration: try configuration(), transport: transport, allowsReadReceipt: true)
        let client = NativeChannelSessionClient(history: reader, service: service, currentSession: { session }, isAvailable: { true })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load()
        XCTAssertTrue(transport.requests.isEmpty) // opening never ACKs
        owner.observed(40); await owner.markSeen()
        XCTAssertNil(owner.receipt)
        XCTAssertEqual(owner.failedOperation, .read(40))
        await owner.load() // cannot replace the uncertain intent
        XCTAssertEqual(reader.pageCalls, 1)
        await owner.retry()
        XCTAssertEqual(owner.receipt?.unread, 3)
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests {
            XCTAssertEqual(NativeChannelRuntimeRoute(request: request, baseURL: try configuration().baseURL), .readThrough(conversationID: 1, target: 40))
        }
    }
    @MainActor func testAccountOrGrantChangeHidesHistoryAndStopsFurtherReads() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([100], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        var allowed = true
        let client = NativeChannelSessionClient(history: reader, currentSession: { session }, isAvailable: { allowed })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load()
        XCTAssertEqual(owner.visibleMessages.count, 1)
        allowed = false
        XCTAssertNil(owner.detailMessage(100))
        XCTAssertTrue(owner.visibleMessages.isEmpty)
        await owner.load()
        XCTAssertEqual(reader.pageCalls, 1)
    }
    @MainActor func testLeavingDuringReceiptKeepsTheExactUnknownIntentForExplicitRetry() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([100, 40], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let transport = NativeChannelRetireTransport()
        let service = NativeChannelService(configuration: try configuration(), transport: transport, allowsReadReceipt: true)
        let client = NativeChannelSessionClient(history: reader, service: service, currentSession: { session }, isAvailable: { true })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load(); owner.observed(40)
        transport.onSend = { owner.stop() }
        await owner.markSeen()
        XCTAssertNil(owner.receipt)
        XCTAssertEqual(owner.failedOperation, .read(40))
        owner.activate(); await owner.load()
        XCTAssertEqual(reader.pageCalls, 1)
        transport.onSend = nil
        await owner.retry()
        XCTAssertEqual(owner.receipt?.readTo, 40)
    }
    @MainActor func testTaskCancelledAfterAckDispatchRetainsSnapshotAndRequiresExplicitExactRetry() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([100, 40], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let transport = NativeChannelPausedTransport()
        let dispatched = expectation(description: "synthetic ACK dispatched")
        transport.onSend = { dispatched.fulfill() }
        let service = NativeChannelService(configuration: try configuration(), transport: transport, allowsReadReceipt: true)
        let client = NativeChannelSessionClient(history: reader, service: service, currentSession: { session }, isAvailable: { true })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load(); owner.observed(40)
        let pending = Task { await owner.markSeen() }
        await fulfillment(of: [dispatched], timeout: 1)
        pending.cancel(); transport.finish()
        await pending.value
        XCTAssertEqual(owner.failedOperation, .read(40))
        XCTAssertEqual(owner.visibleMessages.map(\.id), [100, 40])
        XCTAssertNil(owner.receipt)
        owner.stop(); owner.activate(); await owner.load()
        XCTAssertEqual(reader.pageCalls, 1)
        XCTAssertEqual(transport.requests.count, 1) // returning never repeats the ACK
        transport.pause = false
        await owner.retry()
        XCTAssertEqual(owner.receipt?.readTo, 40)
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests {
            XCTAssertEqual(NativeChannelRuntimeRoute(request: request, baseURL: try configuration().baseURL), .readThrough(conversationID: 1, target: 40))
        }
    }
    @MainActor func testRetiredAuthorityDuringCancelledAckCannotExposeOrRetrySnapshot() async throws {
        let reader = NativeChannelTestReader(rows: try conversations(), page: try page([40], conversation: 1))
        let session = try NativeChannelSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let transport = NativeChannelPausedTransport()
        let dispatched = expectation(description: "synthetic ACK dispatched")
        transport.onSend = { dispatched.fulfill() }
        var allowed = true
        let service = NativeChannelService(configuration: try configuration(), transport: transport, allowsReadReceipt: true)
        let client = NativeChannelSessionClient(history: reader, service: service, currentSession: { session }, isAvailable: { allowed })
        let owner = NativeChannelHistoryModel(conversation: try conversations()[0], client: client)
        owner.activate(); await owner.load(); owner.observed(40)
        let pending = Task { await owner.markSeen() }
        await fulfillment(of: [dispatched], timeout: 1)
        allowed = false; pending.cancel(); transport.finish()
        await pending.value
        XCTAssertTrue(owner.visibleMessages.isEmpty)
        XCTAssertNil(owner.detailMessage(40))
        transport.pause = false
        await owner.retry()
        XCTAssertEqual(transport.requests.count, 1)
    }
    private func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com/fixture/")!) }
}

@MainActor private final class NativeChannelTestReader: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 1, epoch: 1)
    let rows: [MessagingConversation]
    let page: MessagingPage
    var pageCalls = 0
    init(rows: [MessagingConversation], page: MessagingPage) { self.rows = rows; self.page = page }
    func messagingConversations() async throws -> [MessagingConversation] { rows }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { pageCalls += 1; return page }
}

private final class NativeChannelRetireTransport: HTTPTransport {
    var onSend: (@MainActor () -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if let onSend { await onSend() }
        return (Data(#"{"code":200,"data":{"conversationId":1,"readTo":40,"lastReadMessageId":40,"unread":0}}"#.utf8), 200)
    }
}

@MainActor private final class NativeChannelPausedTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var onSend: (() -> Void)?
    var pause = true
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var reply: (Data, Int) {
        (Data(#"{"code":200,"data":{"conversationId":1,"readTo":40,"lastReadMessageId":40,"unread":0}}"#.utf8), 200)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard pause else { return reply }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation; onSend?()
        }
    }
    func finish() { continuation?.resume(returning: reply); continuation = nil }
}
