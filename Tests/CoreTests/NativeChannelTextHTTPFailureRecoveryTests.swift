import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Actual original text wire, client, coordinator and journal. Responses are synthetic;
/// there is no native receipt proof, production grant, or type-5 mapping in this suite.
@MainActor final class NativeChannelTextHTTPFailureRecoveryTests: XCTestCase {
    private let ambiguousStatuses = [302, 408, 429, 500, 503]
    private let deniedBodies = [
        #"{"code":403}"#,
        #"{"code":404}"#,
        #"{"code":409,"errorCode":"IM_CONVERSATION_CLOSED"}"#,
        #"{"code":409,"errorCode":"HANGOUT_CLOSED"}"#
    ]
    private let missing = #"{"code":200,"data":{"found":false,"message":null}}"#

    func testAmbiguousSendMetadataCannotCloseOriginalRecoveryOrAutomaticallyResend() async throws {
        for status in ambiguousStatuses {
            for body in deniedBodies {
                let r = try HTTPTextRig([.response(body, status), .response(missing, 200)])
                let flow = try await r.makeFlow()
                var protected: [String: Data] = [:]
                r.wire.beforeReply = { if protected.isEmpty { protected = r.storage.rows } }
                let accepted = await flow.sendNew("original body")
                XCTAssertFalse(accepted, "HTTP \(status): \(body)")
                XCTAssertEqual(flow.visibleState, .outcomeUnknown)
                XCTAssertEqual(flow.pendingText, "original body")
                XCTAssertTrue(flow.canCheckReceipt); XCTAssertTrue(flow.canRetryOriginal)
                XCTAssertFalse(flow.canSendNew); XCTAssertNil(flow.authoritativeMessage)
                XCTAssertEqual(r.storage.rows, protected); XCTAssertFalse(protected.isEmpty)
                let original = try XCTUnwrap(r.journal.restore())
                assertOriginal(r, original: original, paths: ["send", "send-receipt"])
                XCTAssertFalse(r.read.isRevoked); XCTAssertFalse(r.write.isRevoked)
                flow.stop()
            }
        }
    }

    func testAmbiguousOriginalReceiptRemainsUnavailableUntilExplicitReadRecovers() async throws {
        for status in ambiguousStatuses {
            for body in deniedBodies {
                let r = try HTTPTextRig([.failure(.timedOut), .response(body, status)])
                let flow = try await r.makeFlow()
                let accepted = await flow.sendNew("original body")
                XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .receiptUnavailable)
                XCTAssertTrue(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
                let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
                assertOriginal(r, original: original, paths: ["send", "send-receipt"])
                r.wire.steps.append(.response(missing, 200))
                let found = await flow.checkReceipt()
                XCTAssertFalse(found); XCTAssertEqual(flow.visibleState, .outcomeUnknown)
                XCTAssertTrue(flow.canRetryOriginal); XCTAssertEqual(r.storage.rows, protected)
                assertOriginal(r, original: original, paths: ["send", "send-receipt", "send-receipt"])
                flow.stop()
            }
        }
    }

    func testExplicitRetryReadsFirstAndReusesOriginalThenSettlesOnlyActualSendSuccess() async throws {
        let r = try HTTPTextRig([.response(deniedBodies[2], 503), .response(missing, 200)])
        let flow = try await r.makeFlow()
        _ = await flow.sendNew("original body")
        let original = try XCTUnwrap(r.journal.restore())
        XCTAssertTrue(flow.canRetryOriginal)
        r.wire.steps += [.response(missing, 200), .originalSendSuccess]
        let accepted = await flow.retryOriginal()
        XCTAssertTrue(accepted); XCTAssertEqual(flow.visibleState, .acknowledged(messageID: 17))
        assertOriginal(r, original: original, paths: ["send", "send-receipt", "send-receipt", "send"])
        // Multipart boundaries may rotate; assertOriginal checks the same key and content bytes.
        XCTAssertNil(try r.journal.restore()); XCTAssertTrue(r.storage.rows.isEmpty)
        XCTAssertNil(flow.pendingClientMessageID); XCTAssertNil(flow.authoritativeMessage)
        XCTAssertTrue(flow.history.visibleMessages.isEmpty) // A send result is not another history source.
        flow.stop()
    }

    func testAmbiguousRetryPreflightNeverDispatchesOriginalAgain() async throws {
        let r = try HTTPTextRig([.failure(.timedOut), .response(missing, 200)])
        let flow = try await r.makeFlow()
        _ = await flow.sendNew("original body")
        let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
        r.wire.steps.append(.response(deniedBodies[0], 429))
        let retried = await flow.retryOriginal()
        XCTAssertFalse(retried); XCTAssertEqual(flow.visibleState, .receiptUnavailable)
        XCTAssertFalse(flow.canRetryOriginal); XCTAssertTrue(flow.canCheckReceipt)
        XCTAssertEqual(r.storage.rows, protected)
        assertOriginal(r, original: original, paths: ["send", "send-receipt", "send-receipt"])
        r.wire.steps.append(.response(missing, 200))
        _ = await flow.checkReceipt()
        XCTAssertTrue(flow.canRetryOriginal); XCTAssertEqual(r.storage.rows, protected)
        XCTAssertEqual(r.wire.requests.filter { $0.url?.lastPathComponent == "send" }.count, 1)
        flow.stop()
    }

    func testSuccessfulHTTPEnvelopeStillClosesOnOriginalAccessDenial() async throws {
        for body in deniedBodies {
            let r = try HTTPTextRig([.response(body, 200)]), flow = try await r.makeFlow()
            let accepted = await flow.sendNew("original body")
            XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .accessClosed)
            XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
            XCTAssertNil(flow.pendingText); XCTAssertNotNil(try r.journal.restore())
            XCTAssertEqual(r.wire.requests.map { $0.url?.lastPathComponent }, ["send"])
            XCTAssertFalse(r.read.isRevoked); XCTAssertFalse(r.write.isRevoked)
            flow.stop()
        }
    }

    func testActualHTTPForbiddenStillClosesDespiteConflictingEnvelopeMetadata() async throws {
        let r = try HTTPTextRig([.response(#"{"code":503}"#, 403)]), flow = try await r.makeFlow()
        let accepted = await flow.sendNew("original body")
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .accessClosed)
        XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertNotNil(try r.journal.restore()); XCTAssertNil(flow.pendingText)
        XCTAssertEqual(r.wire.requests.count, 1)
        XCTAssertFalse(r.read.isRevoked); XCTAssertFalse(r.write.isRevoked)
        flow.stop()
    }

    func testActualAndHeaderUnauthorizedStillRetireCapturedApprovalsBeforeCoordinator() async throws {
        // Header-401 semantics are an existing transport contract, including HTTP 503.
        // This recovery change must not weaken that separate authentication boundary.
        for (body, status) in [(#"{"code":503}"#, 401), (#"{"code":401}"#, 503), (#"{"code":401}"#, 200)] {
            let r = try HTTPTextRig([.response(body, status)]), flow = try await r.makeFlow()
            let accepted = await flow.sendNew("original body")
            XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .accessClosed)
            XCTAssertTrue(r.read.isRevoked); XCTAssertTrue(r.write.isRevoked)
            XCTAssertEqual(r.unauthorizedCalls, 1)
            XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
            XCTAssertNotNil(try r.journal.restore()); XCTAssertNil(flow.pendingText)
            XCTAssertEqual(r.wire.requests.count, 1)
            flow.stop()
        }
    }

    func testConfirmedClosedReceiptAfterAmbiguousSendStillRetiresOldRecovery() async throws {
        let r = try HTTPTextRig([.response(deniedBodies[0], 500), .response(deniedBodies[2], 200)])
        let flow = try await r.makeFlow()
        _ = await flow.sendNew("original body")
        let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
        XCTAssertEqual(flow.visibleState, .accessClosed); XCTAssertNil(flow.pendingText)
        assertOriginal(r, original: original, paths: ["send", "send-receipt"])
        flow.stop(); flow.activate()
        let attempted = await flow.checkReceipt()
        XCTAssertFalse(attempted); XCTAssertEqual(r.wire.requests.count, 2)
        XCTAssertEqual(r.storage.rows, protected)
        flow.stop()
    }

    func testNewAuthorizedLifetimeRestoresUnknownAndWaitsForExplicitRead() async throws {
        let r = try HTTPTextRig([.failure(.timedOut), .response(deniedBodies[2], 503)])
        let old = try await r.makeFlow()
        _ = await old.sendNew("original body")
        let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
        old.stop()
        let fresh = try await r.makeFlow()
        XCTAssertEqual(fresh.visibleState, .outcomeUnknown)
        XCTAssertTrue(fresh.canCheckReceipt); XCTAssertFalse(fresh.canRetryOriginal)
        XCTAssertEqual(r.wire.requests.count, 2); XCTAssertEqual(r.storage.rows, protected)
        r.wire.steps.append(.response(missing, 200))
        _ = await fresh.checkReceipt()
        XCTAssertTrue(fresh.canRetryOriginal); XCTAssertEqual(r.storage.rows, protected)
        assertOriginal(r, original: original, paths: ["send", "send-receipt", "send-receipt"])
        fresh.stop()
    }

    func testUnissuedReplacementCannotUseUnknownJournalToDispatchOrRead() async throws {
        let r = try HTTPTextRig([.failure(.timedOut), .response(deniedBodies[2], 503)])
        let old = try await r.makeFlow()
        _ = await old.sendNew("original body")
        let protected = r.storage.rows
        old.stop()
        let fresh = try await r.makeFlow(granted: false)
        let read = await fresh.checkReceipt(), retry = await fresh.retryOriginal(), send = await fresh.sendNew("replacement")
        XCTAssertFalse(read); XCTAssertFalse(retry); XCTAssertFalse(send)
        XCTAssertEqual(fresh.visibleState, .accessClosed); XCTAssertNil(fresh.pendingText)
        XCTAssertEqual(r.wire.requests.count, 2); XCTAssertEqual(r.storage.rows, protected)
        XCTAssertFalse(fresh.history.client.canReadThrough); XCTAssertFalse(fresh.history.client.canLoadNewer)
        fresh.stop()
    }

    private func assertOriginal(_ r: HTTPTextRig, original: MessageTextIntent, paths: [String],
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.wire.requests.compactMap { $0.url?.lastPathComponent }, paths, file: file, line: line)
        for request in r.wire.requests {
            guard let route = NativeChannelTextRoute(request: request, baseURL: r.context.baseURL) else {
                XCTFail("Malformed original route", file: file, line: line); continue
            }
            switch route {
            case .send(let intent): XCTAssertTrue(NativeChannelTextJournal.same(intent, original), file: file, line: line)
            case .receipt(let conversation, let key):
                XCTAssertEqual(conversation, original.conversationID, file: file, line: line)
                XCTAssertEqual(key, original.clientMessageID, file: file, line: line)
            default: XCTFail("Unexpected route", file: file, line: line)
            }
        }
    }
}

@MainActor private final class HTTPTextRig {
    let context: RuntimeDependencyContext
    let wire: HTTPTextWire
    let storage: HTTPTextStorage
    let journal: NativeChannelTextJournal
    let read: NativeChannelTextApproval
    let write: NativeChannelTextApproval
    var unauthorizedCalls = 0
    init(_ steps: [HTTPTextWire.Step]) throws {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "http-text-recovery-tests", token: "synthetic-token"))
        context = c; wire = HTTPTextWire(steps, baseURL: c.baseURL)
        let memory = HTTPTextStorage(); storage = memory
        journal = NativeChannelTextJournal(storage: memory, scope: try .init(context: c, conversationID: 9))
        read = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
        write = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(60))
    }
    func makeFlow(granted: Bool = true) async throws -> NativeChannelTextCoordinator {
        let c = context
        let transport = NativeChannelTextTransport(context: c, transport: wire, current: { c },
            read: { granted ? self.read : nil }, write: { granted ? self.write : nil }, stillCurrent: { true })
        let client = try NativeChannelTextClient(context: c, conversationID: 9, transport: transport,
            onUnauthorized: { _ in self.unauthorizedCalls += 1 })
        let historyClient = NativeChannelSessionClient(history: HTTPTextHistory(),
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_42"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: historyClient)
        history.activate(); await history.load()
        let flow = try NativeChannelTextCoordinator(history: history, client: client, journal: journal)
        flow.activate(); return flow
    }
}
@MainActor private final class HTTPTextStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class HTTPTextHistory: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
@MainActor private final class HTTPTextWire: HTTPTransport {
    enum Step { case response(String, Int), failure(URLError.Code), originalSendSuccess }
    var steps: [Step]
    var requests: [URLRequest] = []
    var beforeReply: (() -> Void)?
    private let baseURL: URL
    init(_ steps: [Step], baseURL: URL) { self.steps = steps; self.baseURL = baseURL }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?()
        guard !steps.isEmpty else { throw APIError.malformedResponse }
        switch steps.removeFirst() {
        case .response(let body, let status): return (Data(body.utf8), status)
        case .failure(let code): throw URLError(code)
        case .originalSendSuccess:
            guard let route = NativeChannelTextRoute(request: request, baseURL: baseURL), case .send(let intent) = route else {
                throw APIError.invalidRequest
            }
            let response: [String: Any] = ["code": 200, "data": ["id": 17, "conversationId": intent.conversationID,
                "senderId": 7, "msgType": 1, "status": 0, "clientMessageId": intent.clientMessageID, "content": intent.content]]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }
    }
}
