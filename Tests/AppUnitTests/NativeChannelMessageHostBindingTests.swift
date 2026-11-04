import XCTest
import Foundation
@testable import Questify

@MainActor private final class MessageHostStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class MessageHostSource: NativeChannelMessageAuthorizing {
    let value: NativeChannelMessageCredentials
    var identity: MessagingReadIdentity? { value.identity }
    init(_ value: NativeChannelMessageCredentials) { self.value = value }
    func credentials(for capability: NativeChannelMessageCapability, binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard binding == value.binding, capability == .mutations || capability == .receipt else { throw APIError.notConfigured }; return value
    }
}
@MainActor private final class MessageHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var sent: [String] = []
    var lookedUp: [String] = []
    var lastOriginal: String?
    var timeOutSend = false
    var status = 200
    var responseBytes: Data?
    var beforeReply: (() -> Void)?
    private func fields(_ request: URLRequest) -> [String: String] {
        guard let type = request.value(forHTTPHeaderField: "Content-Type"),
              let raw = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) else { return [:] }
        let boundary = type.replacingOccurrences(of: "multipart/form-data; boundary=", with: "")
        var result: [String: String] = [:]
        for piece in raw.components(separatedBy: "--" + boundary + "\r\n") {
            let prefix = "Content-Disposition: form-data; name=\""
            guard piece.hasPrefix(prefix), let mid = piece.range(of: "\"\r\n\r\n") else { continue }
            let key = String(piece[piece.index(piece.startIndex, offsetBy: prefix.count)..<mid.lowerBound])
            var value = String(piece[mid.upperBound...]); if let end = value.range(of: "\r\n") { value = String(value[..<end.lowerBound]) }
            result[key] = value
        }
        return result
    }
    private func message(_ key: String) -> [String: Any] {
        ["id":"8", "conversationId":"9", "senderId":"3", "msgType":1, "status":0, "version":1,
         "content":"original body", "clientMessageId":key, "mentions":[], "mention_everyone":false]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let f = fields(request); beforeReply?()
        if let responseBytes { return (responseBytes, status) }
        if status == 401 { return (Data(), 401) }
        let data: [String: Any]
        switch request.url?.lastPathComponent {
        case "messages":
            data = ["list": lastOriginal.map { [message($0)] } ?? [], "nextCursor":NSNull(), "hasMore":false,
                "mutation_cursor":"0", "sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1", "legacy_cache_action":"RELOAD_ON_RESUME"]
        case "send":
            let key = try XCTUnwrap(f["client_message_id"]); sent.append(key); lastOriginal = key
            if timeOutSend { throw URLError(.timedOut) }
            data = message(key)
        case "send-receipt":
            let key = try XCTUnwrap(f["client_message_id"]); lookedUp.append(key)
            data = key == lastOriginal ? ["found":true, "message":message(key)] : ["found":false]
        default: throw APIError.invalidRequest
        }
        return (try JSONSerialization.data(withJSONObject: ["code":200,"data":data]), 200)
    }
}
@MainActor private final class MessageHostHarness {
    let context: RuntimeDependencyContext
    let binding: NativeChannelMessageBinding
    let source: MessageHostSource
    let host: NativeChannelMessageHostAuthority
    let outer: CompositionHTTPTransport
    let wire: MessageHostWire
    let storage = MessageHostStorage()
    let conversation: MessagingConversation
    let historyGrant: MessagingHistoryReadApproval
    let receiptGrant: NativeChannelTextApproval
    let sendGrant: NativeChannelTextApproval
    var unauthorized = 0
    init() throws {
        let wire = MessageHostWire(); self.wire = wire
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://chengyin-synthetic-fixture.example.test/native",
            approvedBaseURLs: [.china:["https://chengyin-synthetic-fixture.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.message.host", realm: "fixture")
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://chengyin-synthetic-fixture.example.test/native")!, role: "player",
            session: try .init(accountID: 3, epoch: 1, namespace: deployment.storageScope.service, token: "fixture-token"))
        context = c
        let b = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "real-fixture-context-v1")
        binding = b
        let original = MessageHostSource(try .init(identity: .init(accountID: 3, epoch: 1), namespace: c.session.namespace,
            baseURL: c.baseURL, binding: b, authorityRevision: "explicit-source-v1", token: c.session.token))
        source = original
        host = try .init(context: c, viewerRevision: 1, binding: b, source: original, current: { c }, viewer: { 1 }, selected: { original })
        let hg = try MessagingHistoryReadApproval(context: c, expiresAt: Date().addingTimeInterval(300)); historyGrant = hg
        receiptGrant = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        sendGrant = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        outer = CompositionHTTPTransport(deployment: deployment, underlying: wire, messagingHistoryReadApproval: { _ in hg })
        conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_7"}}"#.utf8))
        outer.current = { .init(epoch: 1, accountID: 3, role: "player", token: "fixture-token", viewerRevision: 1) }
    }
    func make() throws -> NativeChannelMessageHostFlow {
        try NativeChannelMessageHostBinding.make(context: context, conversation: conversation, authority: host, storage: storage,
            current: { self.host.identity != nil }, onUnauthorized: { self.unauthorized += 1 },
            makeOriginal: { current, unauthorized in
                try self.outer.makeNativeChannelMessageOriginalAdapters(context: self.context, binding: self.binding,
                    currentRuntime: { self.context }, stillCurrent: current,
                    read: { self.receiptGrant }, write: { self.sendGrant }, received401: unauthorized)
            }, makeMutations: { journal, current, unauthorized in
                try self.outer.makeNativeChannelMessageDispatcher(authority: self.host, journal: journal,
                    currentRuntime: { self.context }, stillCurrent: current, onUnauthorized: unauthorized)
            })
    }
}
@MainActor final class NativeChannelMessageHostBindingTests: XCTestCase {
    func testNormalBindingReadsSameOriginalHistoryAndSendsPlainTextThroughSameWire() async throws {
        let h = try MessageHostHarness(), flow = try h.make()
        XCTAssertTrue(h.wire.requests.isEmpty)
        await flow.coordinator.activate()
        XCTAssertTrue(flow.history.loaded); XCTAssertTrue(flow.coordinator.historyReady)
        let text = try XCTUnwrap(flow.makeTextCoordinator(history: flow.history)); text.activate()
        let sent = await text.sendNew("original body")
        XCTAssertTrue(sent); XCTAssertEqual(h.wire.sent.count, 1)
        XCTAssertEqual(flow.history.history.messages.first?.content, "original body")
        XCTAssertEqual(flow.wire.snapshot(for: try XCTUnwrap(flow.history.history.messages.first))?.version, 1)
    }
    func testTimeoutThenNormalRemountUsesSameOriginalJournalAndReceiptNotSecondSend() async throws {
        let h = try MessageHostHarness(); h.wire.timeOutSend = true
        let first = try h.make(); await first.coordinator.activate()
        let text = try XCTUnwrap(first.makeTextCoordinator(history: first.history)); text.activate()
        let unknown = await text.sendNew("original body"); XCTAssertFalse(unknown)
        let key = try XCTUnwrap(h.wire.sent.first); let originalBytes = h.storage.rows
        text.stop(); first.retire()
        let fresh = try h.make(); await fresh.coordinator.activate()
        let recovered = try XCTUnwrap(fresh.makeTextCoordinator(history: fresh.history)); recovered.activate()
        XCTAssertEqual(h.storage.rows, originalBytes)
        let found = await recovered.checkReceipt(); XCTAssertTrue(found)
        XCTAssertEqual(h.wire.sent, [key]); XCTAssertEqual(h.wire.lookedUp, [key])
    }
    func testRecognizedHistory401RetiresHostBeforeCancelledDeliveryAndBlocksNormalRemount() async throws {
        let h = try MessageHostHarness(), first = try h.make(); h.wire.status = 401
        var task: Task<Void, Never>?
        h.wire.beforeReply = { task?.cancel() }
        task = Task { await first.coordinator.activate() }; await task?.value
        XCTAssertNil(h.host.identity); XCTAssertEqual(h.unauthorized, 0)
        XCTAssertThrowsError(try h.make()); XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testOriginalText401AlsoRetiresOriginalTextGrantsInsteadOfHidingStatusInBridge() async throws {
        let h = try MessageHostHarness(), flow = try h.make(); await flow.coordinator.activate()
        let text = try XCTUnwrap(flow.makeTextCoordinator(history: flow.history)); text.activate()
        h.wire.status = 401; _ = await text.sendNew("original body")
        XCTAssertNil(h.host.identity); XCTAssertTrue(h.sendGrant.isRevoked); XCTAssertTrue(h.receiptGrant.isRevoked)
        XCTAssertEqual(h.unauthorized, 1); XCTAssertFalse(h.storage.rows.isEmpty)
        XCTAssertThrowsError(try h.make())
    }
    func testRecognizedHistoryCode401RetiresHostBeforeCancellationWithoutChangingHTTPStatus() async throws {
        let h = try MessageHostHarness(), first = try h.make()
        h.wire.responseBytes = Data(#"{"code":401}"#.utf8)
        var task: Task<Void, Never>?; h.wire.beforeReply = { task?.cancel() }
        task = Task { await first.coordinator.activate() }; await task?.value
        XCTAssertNil(h.host.identity); XCTAssertEqual(h.unauthorized, 0); XCTAssertEqual(h.wire.status, 200)
        XCTAssertThrowsError(try h.make()); XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testActualCode401RetiresBothOriginalTextGrantsAndHostForCurrentAndCancelledDelivery() async throws {
        for cancelled in [false, true] {
            let h = try MessageHostHarness(), flow = try h.make(); await flow.coordinator.activate()
            let text = try XCTUnwrap(flow.makeTextCoordinator(history: flow.history)); text.activate()
            h.wire.responseBytes = Data(#"{"code":401}"#.utf8)
            var storedBeforeResponse: [String: Data] = [:]
            var task: Task<Void, Never>?
            h.wire.beforeReply = { storedBeforeResponse = h.storage.rows; if cancelled { task?.cancel() } }
            task = Task { _ = await text.sendNew("original body") }; await task?.value
            XCTAssertNil(h.host.identity); XCTAssertTrue(h.sendGrant.isRevoked); XCTAssertTrue(h.receiptGrant.isRevoked)
            XCTAssertEqual(h.unauthorized, cancelled ? 0 : 1); XCTAssertEqual(h.wire.status, 200)
            XCTAssertFalse(storedBeforeResponse.isEmpty); XCTAssertEqual(h.storage.rows, storedBeforeResponse)
            XCTAssertThrowsError(try h.make())
            let remountedText = NativeChannelTextTransport(context: h.context, transport: h.wire,
                current: { h.context }, read: { h.receiptGrant }, write: { h.sendGrant }, stillCurrent: { true })
            XCTAssertFalse(remountedText.allows(.send, conversationID: 9))
            XCTAssertFalse(remountedText.allows(.receipt, conversationID: 9))
        }
    }
    func testCancelledSuccessfulTextResponseKeepsBothOriginalGrantsAndJournal() async throws {
        let h = try MessageHostHarness(), flow = try h.make(); await flow.coordinator.activate()
        let text = try XCTUnwrap(flow.makeTextCoordinator(history: flow.history)); text.activate()
        var storedBeforeResponse: [String: Data] = [:]; var task: Task<Void, Never>?
        h.wire.beforeReply = { storedBeforeResponse = h.storage.rows; task?.cancel() }
        task = Task { _ = await text.sendNew("original body") }; await task?.value
        XCTAssertNotNil(h.host.identity); XCTAssertFalse(h.sendGrant.isRevoked); XCTAssertFalse(h.receiptGrant.isRevoked)
        XCTAssertEqual(h.unauthorized, 0); XCTAssertFalse(storedBeforeResponse.isEmpty)
        XCTAssertEqual(h.storage.rows, storedBeforeResponse)
    }
    func testOrdinaryCompositionDoesNotIssueMessageAuthority() throws {
        let h = try MessageHostHarness(); XCTAssertNil(AppCompositionRoot().nativeChannelMessageAuthorization(h.context, 1, h.binding))
    }
}
