import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Actual original text service/client/coordinator over synthetic HTTP responses.
/// No native original-send proof, type-5 mapping, or production grant is supplied.
@MainActor final class NativeChannelTextClosedResponseTests: XCTestCase {
    private let closed = #"{"code":409,"msg":"群聊已结束","errorCode":"IM_CONVERSATION_CLOSED"}"#

    func testClosedSendStopsRecoveryReadsAndKeepsExactProtectedOriginal() async throws {
        let r = try ClosedTextRig([.response(closed, 200)]), flow = try await r.makeFlow()
        var beforeResponse: [String: Data] = [:]
        r.wire.beforeReply = { beforeResponse = r.storage.rows }
        let accepted = await flow.sendNew("original body")
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .accessClosed)
        XCTAssertFalse(flow.canSendNew); XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertNil(flow.pendingText); XCTAssertNil(flow.authoritativeMessage)
        XCTAssertFalse(beforeResponse.isEmpty); XCTAssertEqual(r.storage.rows, beforeResponse)
        let original = try XCTUnwrap(r.journal.restore())
        XCTAssertEqual(original.content, "original body")
        XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send"])
        flow.stop(); flow.activate()
        let attempted = await flow.checkReceipt(); XCTAssertFalse(attempted)
        XCTAssertEqual(r.wire.requests.count, 1); XCTAssertEqual(r.storage.rows, beforeResponse)
        XCTAssertFalse(r.write.isRevoked); XCTAssertFalse(r.read.isRevoked)
    }

    func testTimeoutThenClosedOriginalReceiptTerminatesOldFlowWithoutResending() async throws {
        let r = try ClosedTextRig([.failure(.timedOut), .response(closed, 200)]), flow = try await r.makeFlow()
        let accepted = await flow.sendNew("original body")
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .accessClosed)
        let original = try XCTUnwrap(r.journal.restore())
        XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send", "send-receipt"])
        assertOriginal(r.wire.requests, original: original, baseURL: r.context.baseURL)
        XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertTrue(flow.history.visibleMessages.isEmpty); XCTAssertNil(flow.authoritativeMessage)
        flow.stop()
    }

    func testFreshAuthorizedOwnerMayReadButLegacyFoundBodyStillCannotSettle() async throws {
        let r = try ClosedTextRig([.response(closed, 200)]), old = try await r.makeFlow()
        _ = await old.sendNew("original body")
        let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
        old.stop()
        // A new host lifetime with separately injected test grants, not reopening the old closed flow.
        let fresh = try await r.makeFlow()
        let body: [String: Any] = ["code": 200, "data": ["found": true, "message": [
            "id": 17, "conversationId": 9, "senderId": 7, "msgType": 1, "status": 0,
            "clientMessageId": original.clientMessageID, "content": original.content
        ]]]
        r.wire.steps.append(.response(String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self), 200))
        let settled = await fresh.checkReceipt()
        XCTAssertFalse(settled); XCTAssertEqual(fresh.visibleState, .outcomeUnknown)
        XCTAssertEqual(r.storage.rows, protected); XCTAssertFalse(fresh.canRetryOriginal)
        XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send", "send-receipt"])
        assertOriginal(r.wire.requests, original: original, baseURL: r.context.baseURL)
        fresh.stop()
    }

    func testOrdinaryConflictRemainsUnknownAndNeverAutomaticallyResends() async throws {
        let conflict = #"{"code":409,"msg":"message key conflict"}"#
        let missing = #"{"code":200,"data":{"found":false,"message":null}}"#
        let r = try ClosedTextRig([.response(conflict, 200), .response(missing, 200)]), flow = try await r.makeFlow()
        let accepted = await flow.sendNew("original body")
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .outcomeUnknown)
        XCTAssertTrue(flow.canCheckReceipt); XCTAssertTrue(flow.canRetryOriginal)
        XCTAssertNotNil(try r.journal.restore()); XCTAssertFalse(flow.canSendNew)
        XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send", "send-receipt"])
        flow.stop()
    }

    func testOrdinaryServerFailureAndFailedReceiptRemainUncertain() async throws {
        let r = try ClosedTextRig([.response(#"{"code":503,"msg":"temporary failure"}"#, 503), .failure(.notConnectedToInternet)])
        let flow = try await r.makeFlow(), accepted = await flow.sendNew("original body")
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .receiptUnavailable)
        XCTAssertTrue(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal); XCTAssertFalse(flow.canSendNew)
        XCTAssertNotNil(try r.journal.restore())
        XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send", "send-receipt"])
        flow.stop()
    }

    func testUnissuedTextAndHistoryReadReceiptCapabilitiesStayClosed() async throws {
        let r = try ClosedTextRig([]), flow = try await r.makeFlow(granted: false)
        let accepted = await flow.sendNew("must not send")
        XCTAssertFalse(accepted); XCTAssertFalse(flow.canSendNew); XCTAssertFalse(flow.canCheckReceipt)
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertTrue(r.storage.rows.isEmpty)
        XCTAssertFalse(flow.history.client.canReadThrough); XCTAssertFalse(flow.history.client.canLoadNewer)
        flow.stop()
    }

    private func assertOriginal(_ requests: [URLRequest], original: MessageTextIntent, baseURL: URL,
                                file: StaticString = #filePath, line: UInt = #line) {
        for request in requests {
            guard let route = NativeChannelTextRoute(request: request, baseURL: baseURL) else {
                XCTFail("Malformed original text route", file: file, line: line); continue
            }
            switch route {
            case .send(let intent): XCTAssertTrue(NativeChannelTextJournal.same(intent, original), file: file, line: line)
            case .receipt(let conversation, let key):
                XCTAssertEqual(conversation, original.conversationID, file: file, line: line)
                XCTAssertEqual(key, original.clientMessageID, file: file, line: line)
            default: XCTFail("Unexpected original text route", file: file, line: line)
            }
        }
    }
}

@MainActor private final class ClosedTextRig {
    let context: RuntimeDependencyContext
    let wire: ClosedTextWire
    let storage: ClosedTextStorage
    let journal: NativeChannelTextJournal
    let read: NativeChannelTextApproval
    let write: NativeChannelTextApproval
    init(_ steps: [ClosedTextWire.Step]) throws {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "closed-text-response-tests", token: "synthetic-token"))
        context = c; wire = ClosedTextWire(steps)
        let memory = ClosedTextStorage(); storage = memory
        journal = NativeChannelTextJournal(storage: memory, scope: try .init(context: c, conversationID: 9))
        read = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        write = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
    }
    func makeFlow(granted: Bool = true) async throws -> NativeChannelTextCoordinator {
        let c = context
        let transport = NativeChannelTextTransport(context: c, transport: wire, current: { c },
            read: { granted ? self.read : nil }, write: { granted ? self.write : nil }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: c, conversationID: 9, transport: transport)
        let reader = ClosedTextHistory()
        let historyClient = NativeChannelSessionClient(history: reader,
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_42"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: historyClient)
        history.activate(); await history.load()
        let flow = try NativeChannelTextCoordinator(history: history, client: client, journal: journal)
        flow.activate(); return flow
    }
}
@MainActor private final class ClosedTextStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class ClosedTextHistory: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
@MainActor private final class ClosedTextWire: HTTPTransport {
    enum Step { case response(String, Int), failure(URLError.Code) }
    var steps: [Step]
    var requests: [URLRequest] = []
    var beforeReply: (() -> Void)?
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?()
        guard !steps.isEmpty else { throw APIError.malformedResponse }
        switch steps.removeFirst() {
        case .response(let body, let status): return (Data(body.utf8), status)
        case .failure(let code): throw URLError(code)
        }
    }
}
