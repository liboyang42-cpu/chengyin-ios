import XCTest
import Foundation
import SwiftUI
@testable import Questify

@MainActor private final class RouteMessageHostStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class RouteMessageHostSource: NativeChannelMessageAuthorizing {
    let value: NativeChannelMessageCredentials
    var identity: MessagingReadIdentity? { value.identity }
    init(_ value: NativeChannelMessageCredentials) { self.value = value }
    func credentials(for capability: NativeChannelMessageCapability, binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard binding == value.binding, capability == .mutations || capability == .receipt else { throw APIError.notConfigured }; return value
    }
}
@MainActor private final class RouteMessageHostWire: HTTPTransport {
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
@MainActor private final class RouteMessageHostHarness {
    let context: RuntimeDependencyContext
    let binding: NativeChannelMessageBinding
    let source: RouteMessageHostSource
    let host: NativeChannelRouteMessageHostAuthority
    let outer: CompositionHTTPTransport
    let wire: RouteMessageHostWire
    let storage = RouteMessageHostStorage()
    let conversation: MessagingConversation
    let historyGrant: MessagingHistoryReadApproval
    let receiptGrant: NativeChannelTextApproval
    let sendGrant: NativeChannelTextApproval
    var unauthorized = 0
    let sourceCurrent: () -> Bool
    init(sourceCurrent: @escaping () -> Bool) throws {
        self.sourceCurrent = sourceCurrent
        let wire = RouteMessageHostWire(); self.wire = wire
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://chengyin-synthetic-fixture.example.test/native",
            approvedBaseURLs: [.china:["https://chengyin-synthetic-fixture.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.message.host", realm: "fixture")
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://chengyin-synthetic-fixture.example.test/native")!, role: "player",
            session: try .init(accountID: 3, epoch: 1, namespace: deployment.storageScope.service, token: "fixture-token"))
        context = c
        let b = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "real-fixture-context-v1")
        binding = b
        let original = RouteMessageHostSource(try .init(identity: .init(accountID: 3, epoch: 1), namespace: c.session.namespace,
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
    func make() throws -> NativeChannelRouteMessageHostFlow {
        try NativeChannelRouteMessageHostBinding.make(context: context, conversation: conversation, authority: host, storage: storage,
            current: { self.sourceCurrent() && self.host.identity != nil }, onUnauthorized: { self.unauthorized += 1 },
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

/// Actual original host adapter fixtures; no monitor or real network participates.
@MainActor final class NativeChannelHostAncestorFenceTests: XCTestCase {
    func testAncestorPopBlocksOriginalHistoryWithoutWaitingForMonitor() async throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let visit = root.binding
        let fixture = try RouteMessageHostHarness(sourceCurrent: { visit.wrappedValue })
        let flow = try fixture.make()
        flow.history.activate()
        await flow.history.load()
        XCTAssertTrue(flow.isCurrent)
        let count = fixture.wire.requests.count
        root.isPresented = false
        XCTAssertFalse(flow.isCurrent)
        await flow.history.load()
        XCTAssertEqual(fixture.wire.requests.count, count)
        XCTAssertNil(flow.makeTextCoordinator(history: flow.history))
    }
    func testRootReopeningCannotReviveOriginalFlowButNewVisitCanOpen() throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let original = root.binding
        let fixture = try RouteMessageHostHarness(sourceCurrent: { original.wrappedValue })
        let old = try fixture.make()
        root.isPresented = false; root.isPresented = true
        XCTAssertFalse(original.wrappedValue); XCTAssertFalse(old.isCurrent)
        let newVisit = root.binding
        let newFixture = try RouteMessageHostHarness(sourceCurrent: { newVisit.wrappedValue })
        XCTAssertTrue(try newFixture.make().isCurrent)
    }
    func testLateOriginalHistory401CannotExpireOwnerAfterAncestorPop() async throws {
        let root = NativeChannelManagementRouteState(); root.isPresented = true
        let visit = root.binding
        let fixture = try RouteMessageHostHarness(sourceCurrent: { visit.wrappedValue })
        let flow = try fixture.make()
        flow.history.activate()
        fixture.wire.status = 401
        fixture.wire.beforeReply = { root.isPresented = false }
        await flow.history.load()
        XCTAssertEqual(fixture.wire.requests.count, 1)
        XCTAssertEqual(fixture.unauthorized, 0)
        XCTAssertFalse(flow.isCurrent); XCTAssertTrue(flow.history.visibleMessages.isEmpty)
    }
    func testRetirementReleasesCoveredHistoryCallbackCycle() throws {
        let fixture = try RouteMessageHostHarness(sourceCurrent: { true })
        var flow: NativeChannelMessageHostFlow? = try fixture.make()
        weak var weakFlow = flow
        weak var weakHistory = flow?.history
        installCoveredCallback(try XCTUnwrap(flow))
        XCTAssertNotNil(flow?.history.onChange)
        flow?.retire()
        XCTAssertNil(flow?.history.onChange)
        flow = nil
        XCTAssertNil(weakFlow); XCTAssertNil(weakHistory)
    }
    private func installCoveredCallback(_ flow: NativeChannelMessageHostFlow) {
        flow.history.onChange = { _ = flow.history.visibleMessages }
    }
}
