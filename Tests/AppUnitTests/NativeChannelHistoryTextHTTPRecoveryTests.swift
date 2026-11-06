import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Actual history view, reader, services and text coordinator over synthetic HTTP.
/// No native current-authority producer or typed send/read proof is fabricated.
@MainActor final class NativeChannelHistoryTextHTTPRecoveryTests: XCTestCase {
    private let rejectionBodies = [
        #"{"code":403}"#,
        #"{"code":404}"#,
        #"{"code":409,"errorCode":"IM_CONVERSATION_CLOSED"}"#,
        #"{"code":409,"errorCode":"HANGOUT_CLOSED"}"#
    ]

    func testTransientHistoryEnvelopeCannotPermanentlyRetireOriginalTextRecovery() async throws {
        for status in [302, 408, 429, 500, 503] {
            for body in rejectionBodies {
                let r = try HistoryTextHTTPRig(), window = mount(r)
                defer { unmount(window, rig: r) }
                try await ready(r)
                let text = try XCTUnwrap(r.text), protected = r.storage.rows
                r.wire.historyFailures.append((body, status))
                await r.history.older()
                try await renderTurn(window)
                XCTAssertNotNil(r.history.issue); XCTAssertEqual(r.history.failedOperation, .older(11))
                XCTAssertEqual(r.history.visibleMessages.map(\.id), [17])
                XCTAssertFalse(text.canCheckReceipt); XCTAssertNil(text.pendingText)
                XCTAssertEqual(r.storage.rows, protected)
                await r.history.retry()
                try await waitFor { r.wire.receiptKeys.count == 2 && text.canCheckReceipt }
                XCTAssertEqual(r.history.visibleMessages.map(\.id), [8, 17])
                XCTAssertEqual(r.wire.historyCursors, [0, 11, 11])
                XCTAssertEqual(r.wire.receiptKeys, [r.original.clientMessageID, r.original.clientMessageID])
                XCTAssertEqual(text.visibleState, .outcomeUnknown); XCTAssertEqual(text.pendingText, r.original.content)
                XCTAssertEqual(r.storage.rows, protected); XCTAssertEqual(r.wire.sends, 0)
                XCTAssertEqual(r.textFactoryCalls, 1) // The same original owner recovered; no new authority was supplied.
            }
        }
    }

    func testConfirmedHistoryDenialStillRetiresTextEvenAfterHistoryReacquiresLatest() async throws {
        let responses = [(#"{"code":500}"#, 403), (rejectionBodies[0], 200),
            (rejectionBodies[2], 200), (rejectionBodies[2], 409), (rejectionBodies[3], 200)]
        for response in responses {
            let r = try HistoryTextHTTPRig(), window = mount(r)
            defer { unmount(window, rig: r) }
            try await ready(r)
            let text = try XCTUnwrap(r.text), protected = r.storage.rows
            r.wire.historyFailures.append(response)
            await r.history.older()
            try await renderTurn(window)
            XCTAssertTrue(r.history.visibleMessages.isEmpty); XCTAssertEqual(r.history.failedOperation, .latest)
            XCTAssertFalse(text.canCheckReceipt); XCTAssertNil(text.pendingText)
            await r.history.retry()
            try await renderTurn(window)
            XCTAssertTrue(r.history.loaded); XCTAssertNil(r.history.issue)
            XCTAssertFalse(text.canCheckReceipt); XCTAssertFalse(text.canRetryOriginal); XCTAssertFalse(text.canSendNew)
            XCTAssertNil(text.pendingText); XCTAssertEqual(r.wire.receiptKeys.count, 1)
            XCTAssertEqual(r.wire.historyCursors, [0, 11, 0]); XCTAssertEqual(r.wire.sends, 0)
            XCTAssertEqual(r.storage.rows, protected)
        }
    }

    func testRealReaderActualAndHeader401RemainTerminalForOldTextOwner() async throws {
        for response in [(#"{"code":500}"#, 401), (#"{"code":401}"#, 200), (#"{"code":401}"#, 503)] {
            let r = try HistoryTextHTTPRig(), window = mount(r)
            defer { unmount(window, rig: r) }
            try await ready(r)
            let text = try XCTUnwrap(r.text), protected = r.storage.rows
            r.wire.historyFailures.append(response)
            await r.history.older()
            try await renderTurn(window)
            XCTAssertEqual(r.unauthorizedCalls, 1)
            XCTAssertEqual(r.history.issue as? APIError, .unauthorized)
            XCTAssertFalse(text.canCheckReceipt); XCTAssertNil(text.pendingText)
            await r.history.retry()
            try await renderTurn(window)
            XCTAssertFalse(text.canCheckReceipt); XCTAssertEqual(r.wire.receiptKeys.count, 1)
            XCTAssertEqual(r.storage.rows, protected); XCTAssertEqual(r.wire.sends, 0)
        }
    }

    func testOrdinaryServerAndConflictFailuresDoNotBecomeAccessClosure() async throws {
        for response in [(#"{"code":500}"#, 500), (#"{"code":409}"#, 200)] {
            let r = try HistoryTextHTTPRig(), window = mount(r)
            defer { unmount(window, rig: r) }
            try await ready(r)
            let text = try XCTUnwrap(r.text), protected = r.storage.rows
            r.wire.historyFailures.append(response)
            await r.history.older()
            try await renderTurn(window)
            await r.history.retry()
            try await waitFor { r.wire.receiptKeys.count == 2 && text.canCheckReceipt }
            XCTAssertEqual(r.storage.rows, protected); XCTAssertEqual(r.wire.sends, 0)
            XCTAssertEqual(r.wire.historyCursors, [0, 11, 11])
        }
    }

    func testHistoryRecoveryDoesNotReissueRevokedOriginalReceiptGrant() async throws {
        let r = try HistoryTextHTTPRig(), window = mount(r)
        defer { unmount(window, rig: r) }
        try await ready(r)
        let text = try XCTUnwrap(r.text), protected = r.storage.rows
        r.wire.historyFailures.append((rejectionBodies[2], 503))
        await r.history.older()
        try await renderTurn(window)
        r.read.revoke()
        await r.history.retry()
        try await renderTurn(window)
        XCTAssertTrue(r.history.loaded); XCTAssertNil(r.history.issue)
        XCTAssertFalse(text.canCheckReceipt); XCTAssertFalse(text.canSendNew); XCTAssertNil(text.pendingText)
        XCTAssertEqual(r.wire.receiptKeys.count, 1); XCTAssertEqual(r.wire.sends, 0)
        XCTAssertEqual(r.storage.rows, protected); XCTAssertTrue(r.read.isRevoked)
    }

    func testConfirmedClosedReceiptAfterHistoryRecoveryStillClosesOriginalText() async throws {
        let r = try HistoryTextHTTPRig(), window = mount(r)
        defer { unmount(window, rig: r) }
        try await ready(r)
        let text = try XCTUnwrap(r.text), protected = r.storage.rows
        r.wire.historyFailures.append((rejectionBodies[0], 503))
        await r.history.older()
        try await renderTurn(window)
        r.wire.receiptBody = rejectionBodies[2]
        await r.history.retry()
        try await waitFor { r.wire.receiptKeys.count == 2 && text.visibleState == .accessClosed }
        XCTAssertFalse(text.canCheckReceipt); XCTAssertFalse(text.canRetryOriginal); XCTAssertNil(text.pendingText)
        XCTAssertEqual(r.storage.rows, protected); XCTAssertEqual(r.wire.sends, 0)
    }

    func testTypeFiveAndDefaultNativeReceiptCapabilitiesStayClosed() async throws {
        let r = try HistoryTextHTTPRig(type: 5), window = mount(r)
        defer { unmount(window, rig: r) }
        try await renderTurn(window)
        XCTAssertEqual(r.history.conversation.kind, .unknown)
        XCTAssertTrue(r.wire.historyCursors.isEmpty); XCTAssertTrue(r.wire.receiptKeys.isEmpty)
        XCTAssertNil(r.text); XCTAssertEqual(r.textFactoryCalls, 0); XCTAssertEqual(r.wire.sends, 0)
        XCTAssertFalse(r.history.client.canReadThrough); XCTAssertFalse(r.history.client.canLoadNewer)
        XCTAssertTrue(NativeChannelTextJournal.same(try r.journal.restore(), r.original))
    }

    private func mount(_ r: HistoryTextHTTPRig) -> UIWindow {
        let view = NativeChannelHistoryView(model: r.history, makeTextCoordinator: { r.makeText($0) })
        let controller = UIHostingController(rootView: NavigationStack { view }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); controller.view.layoutIfNeeded()
        return window
    }
    private func unmount(_ window: UIWindow, rig: HistoryTextHTTPRig) {
        window.isHidden = true; window.rootViewController = nil
        rig.text?.stop(); rig.text?.onChange = nil; rig.text = nil
        rig.history.stop(); rig.history.onChange = nil
    }
    private func ready(_ r: HistoryTextHTTPRig) async throws {
        try await waitFor { r.history.loaded && r.wire.receiptKeys.count == 1 && r.text?.canCheckReceipt == true }
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The hosted history/text transition did not occur")
        throw APIError.notConfigured
    }
    private func renderTurn(_ window: UIWindow) async throws {
        for _ in 0..<10 {
            window.rootViewController?.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor private final class HistoryTextHTTPRig {
    let context: RuntimeDependencyContext
    let storage = HistoryTextHTTPStorage()
    let wire: HistoryTextHTTPWire
    let read: NativeChannelTextApproval
    let write: NativeChannelTextApproval
    let journal: NativeChannelTextJournal
    let original: MessageTextIntent
    private(set) var history: NativeChannelHistoryModel!
    var text: NativeChannelTextCoordinator?
    var textFactoryCalls = 0, unauthorizedCalls = 0
    init(type: Int = 4) throws {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "history-text-http-" + UUID().uuidString, token: "synthetic-token"))
        context = c; wire = HistoryTextHTTPWire(baseURL: c.baseURL)
        read = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        write = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        journal = NativeChannelTextJournal(storage: storage, scope: try .init(context: c, conversationID: 9))
        original = try MessageTextIntent(conversationID: 9, content: "original body", clientMessageID: "history-text-http-0001")
        try journal.saveBeforeDispatch(original)
        let reader = MessagingSessionReader(service: MessagingService(configuration: try .init(baseURL: c.baseURL), transport: wire),
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") },
            onUnauthorized: { [weak self] _ in self?.unauthorizedCalls += 1 })
        let client = NativeChannelSessionClient(history: reader,
            currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-token") }, isAvailable: { true })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data("{\"conversationId\":9,\"type\":\(type),\"counterparty\":{\"bizKey\":\"club_42\"}}".utf8))
        history = NativeChannelHistoryModel(conversation: conversation, client: client)
    }
    func makeText(_ selected: NativeChannelHistoryModel) -> NativeChannelTextCoordinator? {
        guard selected === history else { return nil }
        if let text { return text }
        textFactoryCalls += 1
        let c = context
        let transport = NativeChannelTextTransport(context: c, transport: wire, current: { c },
            read: { [weak self] in self?.read }, write: { [weak self] in self?.write }, stillCurrent: { true })
        guard let client = try? NativeChannelTextClient(context: c, conversationID: 9, transport: transport),
              let created = try? NativeChannelTextCoordinator(history: history, client: client, journal: journal) else { return nil }
        text = created; return created
    }
}
@MainActor private final class HistoryTextHTTPStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class HistoryTextHTTPWire: HTTPTransport {
    let baseURL: URL
    var historyFailures: [(String, Int)] = []
    var historyCursors: [Int] = [], receiptKeys: [String] = []
    var sends = 0
    var receiptBody = #"{"code":200,"data":{"found":false,"message":null}}"#
    init(baseURL: URL) { self.baseURL = baseURL }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if let route = MessagingHistoryReadRoute(request: request, baseURL: baseURL),
           case .messages(let conversation, let cursor, _) = route {
            guard conversation == 9 else { throw APIError.invalidRequest }
            historyCursors.append(cursor)
            if !historyFailures.isEmpty {
                let response = historyFailures.removeFirst(); return (Data(response.0.utf8), response.1)
            }
            let page: [String: Any] = ["list": [["id": cursor == 0 ? 17 : 8, "conversationId": 9,
                "senderId": 7, "msgType": 1, "status": 0, "content": "visible history"]],
                "hasMore": cursor == 0, "nextCursor": cursor == 0 ? 11 : 0]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": page]), 200)
        }
        guard let route = NativeChannelTextRoute(request: request, baseURL: baseURL) else { throw APIError.invalidRequest }
        switch route {
        case .receipt(_, let key): receiptKeys.append(key); return (Data(receiptBody.utf8), 200)
        case .send: sends += 1; throw APIError.invalidRequest
        default: throw APIError.invalidRequest
        }
    }
}
