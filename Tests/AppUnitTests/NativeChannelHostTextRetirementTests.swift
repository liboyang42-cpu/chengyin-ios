import XCTest
import Foundation
@testable import Questify

/// Host teardown regression, not production endpoint acceptance. The harness
/// explicitly supplies synthetic history metadata/grants; legacy found-only
/// receipts deliberately remain UNKNOWN and never settle the original journal.
@MainActor final class NativeChannelHostTextRetirementTests: XCTestCase {
    func testHostRetireAloneReleasesPendingSendForOriginalReceiptRecovery() async throws {
        let h = try RetiringTextHostHarness(), first = try await h.open()
        let text = try XCTUnwrap(first.makeTextCoordinator(history: first.history)); text.activate()
        h.wire.pauseSend = true
        let old = Task { await text.sendNew("original body") }
        try await waitFor { h.wire.sent.count == 1 }
        defer { h.wire.resumeSend(0, .failure(CancellationError())) }
        let original = try XCTUnwrap(h.wire.sent.first), bytes = h.storage.rows
        first.retire() // No manual text.stop(), SwiftUI disappearance, or transport completion.
        XCTAssertFalse(text.isCurrent); XCTAssertNil(text.onChange); XCTAssertEqual(h.storage.rows, bytes)
        let fresh = try await h.open(), recovered = try XCTUnwrap(fresh.makeTextCoordinator(history: fresh.history))
        recovered.activate(); XCTAssertEqual(recovered.pendingClientMessageID, original.clientMessageID)
        let found = await recovered.checkReceipt()
        XCTAssertFalse(found); XCTAssertEqual(recovered.visibleState, .outcomeUnknown)
        XCTAssertEqual(h.wire.lookedUp, [original.clientMessageID]); XCTAssertEqual(h.wire.sent, [original])
        XCTAssertEqual(h.storage.rows, bytes); XCTAssertFalse(recovered.canRetryOriginal)
        h.wire.resumeSend(0, .success(())); let oldResult = await old.value
        XCTAssertFalse(oldResult); XCTAssertEqual(h.storage.rows, bytes)
        fresh.retire()
    }

    func testRetiredCompletionCannotReleaseReplacementReceiptLease() async throws {
        let h = try RetiringTextHostHarness(), first = try await h.open()
        let text = try XCTUnwrap(first.makeTextCoordinator(history: first.history)); text.activate()
        h.wire.pauseSend = true
        let old = Task { await text.sendNew("original body") }
        try await waitFor { h.wire.sent.count == 1 }
        defer { h.wire.resumeSend(0, .failure(CancellationError())); h.wire.resumeReceipt(0, .failure(CancellationError())) }
        let bytes = h.storage.rows
        first.retire()
        let fresh = try await h.open(), recovered = try XCTUnwrap(fresh.makeTextCoordinator(history: fresh.history))
        recovered.activate(); h.wire.pauseReceipt = true
        let reading = Task { await recovered.checkReceipt() }
        try await waitFor { h.wire.lookedUp.count == 1 }
        h.wire.resumeSend(0, .success(())); _ = await old.value
        XCTAssertEqual(recovered.visibleState, .checkingReceipt); XCTAssertEqual(h.storage.rows, bytes)
        let other = try await h.open(), observer = try XCTUnwrap(other.makeTextCoordinator(history: other.history))
        observer.activate(); let competing = await observer.checkReceipt()
        XCTAssertFalse(competing); XCTAssertEqual(h.wire.lookedUp.count, 1)
        h.wire.resumeReceipt(0, .success(())); _ = await reading.value
        XCTAssertEqual(recovered.visibleState, .outcomeUnknown); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertEqual(h.wire.sent.count, 1); other.retire(); fresh.retire()
    }

    func testRepeatedRetireDoesNotReleaseAnotherHostsOriginalLease() async throws {
        let h = try RetiringTextHostHarness(), first = try await h.open()
        let text = try XCTUnwrap(first.makeTextCoordinator(history: first.history)); text.activate()
        h.wire.pauseSend = true
        let old = Task { await text.sendNew("original body") }
        try await waitFor { h.wire.sent.count == 1 }; first.retire()
        defer { h.wire.resumeSend(0, .failure(CancellationError())); h.wire.resumeReceipt(0, .failure(CancellationError())) }
        let fresh = try await h.open(), recovered = try XCTUnwrap(fresh.makeTextCoordinator(history: fresh.history))
        recovered.activate(); h.wire.pauseReceipt = true
        let reading = Task { await recovered.checkReceipt() }
        try await waitFor { h.wire.lookedUp.count == 1 }
        first.retire(); first.retire()
        let scope = try NativeChannelTextScope(context: h.context, conversationID: 9)
        let probe = NativeChannelTextJournal(storage: h.storage, scope: scope)
        let unexpected = probe.beginOperation(); XCTAssertNil(unexpected)
        if let unexpected { probe.endOperation(unexpected) }
        h.wire.resumeReceipt(0, .success(())); _ = await reading.value
        let released = try XCTUnwrap(probe.beginOperation()); probe.endOperation(released)
        h.wire.resumeSend(0, .success(())); _ = await old.value; fresh.retire()
    }

    func testRetirementClearsTextCallbackBeforeStopPublishesAndBreaksCycle() async throws {
        let h = try RetiringTextHostHarness()
        var flow: NativeChannelMessageHostFlow? = try await h.open()
        var text: NativeChannelTextCoordinator? = try XCTUnwrap(flow?.makeTextCoordinator(history: try XCTUnwrap(flow?.history)))
        text?.activate(); var callbacks = 0
        installCallback(try XCTUnwrap(flow), text: try XCTUnwrap(text)) { callbacks += 1 }
        weak var heldFlow = flow
        weak var heldText = text
        flow?.retire()
        XCTAssertEqual(callbacks, 0); XCTAssertNil(text?.onChange)
        flow = nil; text = nil
        XCTAssertNil(heldFlow); XCTAssertNil(heldText)
    }

    func testSettledSendStaysSettledAndRetirementDoesNotRecreateJournalOrRevokeGrants() async throws {
        let h = try RetiringTextHostHarness(), first = try await h.open()
        let text = try XCTUnwrap(first.makeTextCoordinator(history: first.history)); text.activate()
        let accepted = await text.sendNew("original body"); XCTAssertTrue(accepted)
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertTrue(first.history.visibleMessages.isEmpty)
        first.retire()
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertFalse(h.sendGrant.isRevoked); XCTAssertFalse(h.receiptGrant.isRevoked)
        let fresh = try await h.open(), next = try XCTUnwrap(fresh.makeTextCoordinator(history: fresh.history))
        next.activate(); XCTAssertTrue(next.canSendNew); XCTAssertFalse(next.canCheckReceipt)
        XCTAssertEqual(h.wire.sent.count, 1); XCTAssertTrue(h.wire.lookedUp.isEmpty)
        fresh.retire()
    }

    func testOldTextReferenceCannotReactivateAfterHostRetirement() async throws {
        let h = try RetiringTextHostHarness(), flow = try await h.open()
        let text = try XCTUnwrap(flow.makeTextCoordinator(history: flow.history)); text.activate()
        flow.retire(); text.activate()
        XCTAssertFalse(text.isCurrent); XCTAssertFalse(text.canSendNew); XCTAssertFalse(text.canCheckReceipt)
        let before = h.wire.requests.count
        let sent = await text.sendNew("must not send"); let read = await text.checkReceipt()
        XCTAssertFalse(sent); XCTAssertFalse(read); XCTAssertEqual(h.wire.requests.count, before)
        XCTAssertNil(flow.makeTextCoordinator(history: flow.history)); XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testRetirementWithoutTextOwnerDoesNotConstructOrDispatchOne() throws {
        let h = try RetiringTextHostHarness(), flow = try h.make()
        flow.retire(); flow.retire()
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
        XCTAssertNil(flow.makeTextCoordinator(history: flow.history))
        XCTAssertFalse(flow.history.client.canReadThrough); XCTAssertFalse(flow.history.client.canLoadNewer)
    }

    func testDefaultCompositionAndTypeFiveRemainClosed() throws {
        let h = try RetiringTextHostHarness()
        XCTAssertNil(AppCompositionRoot().nativeChannelMessageAuthorization(h.context, 1, h.binding))
        let unknown = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":5,"counterparty":{"bizKey":"club_7"}}"#.utf8))
        XCTAssertThrowsError(try h.make(conversation: unknown))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    private func installCallback(_ flow: NativeChannelMessageHostFlow, text: NativeChannelTextCoordinator,
                                 notified: @escaping () -> Void) {
        text.onChange = { _ = flow.isCurrent; notified() }
    }
    private func waitFor(_ ready: () -> Bool) async throws {
        for _ in 0..<10_000 { if ready() { return }; await Task.yield() }
        XCTFail("The expected original operation was not admitted")
        throw APIError.notConfigured
    }
}

@MainActor private final class RetiringTextHostStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class RetiringTextHostSource: NativeChannelMessageAuthorizing {
    let value: NativeChannelMessageCredentials
    var identity: MessagingReadIdentity? { value.identity }
    init(_ value: NativeChannelMessageCredentials) { self.value = value }
    func credentials(for capability: NativeChannelMessageCapability, binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard binding == value.binding, capability == .mutations || capability == .receipt else { throw APIError.notConfigured }
        return value
    }
}
@MainActor private final class RetiringTextHostWire: HTTPTransport {
    let baseURL: URL
    var requests: [URLRequest] = []
    var sent: [MessageTextIntent] = [], lookedUp: [String] = []
    var pauseSend = false, pauseReceipt = false
    private var sendWaiting: [Int: CheckedContinuation<Void, Error>] = [:]
    private var receiptWaiting: [Int: CheckedContinuation<Void, Error>] = [:]
    init(baseURL: URL) { self.baseURL = baseURL }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let data: [String: Any]
        if request.url?.lastPathComponent == "messages" {
            // Synthetic admission metadata isolates teardown. No production producer is inferred.
            data = ["list": [], "hasMore": false, "nextCursor": NSNull(), "mutation_cursor": "0",
                    "sync_contract": "VISIBLE_ORDER_PLUS_MUTATIONS_V1", "legacy_cache_action": "RELOAD_ON_RESUME"]
        } else {
            guard let route = NativeChannelTextRoute(request: request, baseURL: baseURL) else { throw APIError.invalidRequest }
            switch route {
            case .send(let intent):
                let index = sent.count; sent.append(intent)
                if pauseSend { try await withCheckedThrowingContinuation { sendWaiting[index] = $0 } }
                data = message(intent)
            case .receipt(_, let key):
                let index = lookedUp.count; lookedUp.append(key)
                if pauseReceipt { try await withCheckedThrowingContinuation { receiptWaiting[index] = $0 } }
                // Current public original receipt shape, not a fabricated native original_send_proof.
                if let intent = sent.first(where: { $0.clientMessageID == key }) {
                    data = ["found": true, "message": message(intent)]
                } else { data = ["found": false, "message": NSNull()] }
            default: throw APIError.invalidRequest
            }
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
    private func message(_ original: MessageTextIntent) -> [String: Any] {
        ["id": "8", "conversationId": "9", "senderId": "3", "msgType": 1, "status": 0, "version": 1,
         "content": original.content, "clientMessageId": original.clientMessageID, "mentions": [], "mention_everyone": false]
    }
    func resumeSend(_ index: Int, _ result: Result<Void, Error>) { sendWaiting.removeValue(forKey: index)?.resume(with: result) }
    func resumeReceipt(_ index: Int, _ result: Result<Void, Error>) { receiptWaiting.removeValue(forKey: index)?.resume(with: result) }
}
@MainActor private final class RetiringTextHostHarness {
    let context: RuntimeDependencyContext
    let binding: NativeChannelMessageBinding
    let source: RetiringTextHostSource
    let authority: NativeChannelMessageHostAuthority
    let outer: CompositionHTTPTransport
    let wire: RetiringTextHostWire
    let storage = RetiringTextHostStorage()
    let conversation: MessagingConversation
    let historyGrant: MessagingHistoryReadApproval
    let receiptGrant: NativeChannelTextApproval
    let sendGrant: NativeChannelTextApproval
    init() throws {
        let url = URL(string: "https://chengyin-synthetic-fixture.example.test/native")!
        let wire = RetiringTextHostWire(baseURL: url); self.wire = wire
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: url.absoluteString,
            approvedBaseURLs: [.china: [url.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.message.host.retirement", realm: "fixture")
        let c = RuntimeDependencyContext(market: .china, baseURL: url, role: "player",
            session: try .init(accountID: 3, epoch: 1, namespace: deployment.storageScope.service, token: "fixture-token"))
        context = c
        let b = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "synthetic-context-v1")
        binding = b
        let original = RetiringTextHostSource(try .init(identity: .init(accountID: 3, epoch: 1), namespace: c.session.namespace,
            baseURL: c.baseURL, binding: b, authorityRevision: "synthetic-source-v1", token: c.session.token))
        source = original
        authority = try .init(context: c, viewerRevision: 1, binding: b, source: original, current: { c }, viewer: { 1 }, selected: { original })
        let hg = try MessagingHistoryReadApproval(context: c, expiresAt: Date().addingTimeInterval(300)); historyGrant = hg
        receiptGrant = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        sendGrant = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        outer = CompositionHTTPTransport(deployment: deployment, underlying: wire, messagingHistoryReadApproval: { _ in hg })
        conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_7"}}"#.utf8))
        outer.current = { .init(epoch: 1, accountID: 3, role: "player", token: "fixture-token", viewerRevision: 1) }
    }
    func open() async throws -> NativeChannelMessageHostFlow {
        let flow = try make(); await flow.coordinator.activate()
        XCTAssertTrue(flow.history.loaded); XCTAssertTrue(flow.coordinator.historyReady)
        return flow
    }
    func make(conversation selected: MessagingConversation? = nil) throws -> NativeChannelMessageHostFlow {
        try NativeChannelMessageHostBinding.make(context: context, conversation: selected ?? conversation,
            authority: authority, storage: storage, current: { self.authority.identity != nil }, onUnauthorized: {},
            makeOriginal: { current, unauthorized in
                try self.outer.makeNativeChannelMessageOriginalAdapters(context: self.context, binding: self.binding,
                    currentRuntime: { self.context }, stillCurrent: current,
                    read: { self.receiptGrant }, write: { self.sendGrant }, received401: unauthorized)
            }, makeMutations: { journal, current, unauthorized in
                try self.outer.makeNativeChannelMessageDispatcher(authority: self.authority, journal: journal,
                    currentRuntime: { self.context }, stillCurrent: current, onUnauthorized: unauthorized)
            })
    }
}
