import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Hosted actual composer over the original transport/client/journal. Grants and
/// responses are test-only. No native typed proof or type-5 producer is supplied.
@MainActor final class NativeChannelTextReadOnlyPresentationTests: XCTestCase {
    func testLosingSendGrantKeepsOriginalReceiptEntryWithoutForegroundRoundTrip() async throws {
        let r = try ReadOnlyTextRig(), original = try r.seedOriginal()
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 && flow.canRetryOriginal }
        let protected = r.storage.rows
        r.write.revoke()
        try await waitFor { r.wire.lookups.count == 2 && flow.canCheckReceipt }
        XCTAssertEqual(flow.visibleState, .outcomeUnknown); XCTAssertEqual(flow.pendingText, original.content)
        XCTAssertFalse(flow.canSendNew); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertEqual(r.wire.lookups, [original.clientMessageID, original.clientMessageID])
        XCTAssertTrue(r.wire.sent.isEmpty); XCTAssertEqual(r.storage.rows, protected)
        XCTAssertTrue(r.write.isRevoked); XCTAssertFalse(r.read.isRevoked)
    }

    func testDispatchedWriteRetiresBeforeReadOnlyRecoveryAndLateSuccessCannotSettle() async throws {
        let r = try ReadOnlyTextRig(), flow = try await r.makeFlow(), window = mount(flow)
        defer { r.wire.resumeSend(0); unmount(window, flow: flow) }
        try await waitFor { flow.canSendNew }
        r.wire.pauseSend = true
        let sending = Task { await flow.sendNew("original body") }
        try await waitFor { r.wire.sent.count == 1 }
        let original = try XCTUnwrap(r.journal.restore()), protected = r.storage.rows
        r.write.revoke()
        try await waitFor { r.wire.lookups.count == 1 && flow.canCheckReceipt }
        XCTAssertEqual(flow.visibleState, .outcomeUnknown)
        XCTAssertEqual(r.wire.lookups, [original.clientMessageID]); XCTAssertEqual(r.wire.sent, [original])
        XCTAssertEqual(r.storage.rows, protected); XCTAssertFalse(flow.canRetryOriginal)
        r.wire.resumeSend(0)
        let accepted = await sending.value
        XCTAssertFalse(accepted); XCTAssertEqual(flow.visibleState, .outcomeUnknown)
        XCTAssertEqual(r.storage.rows, protected); XCTAssertNil(flow.authoritativeMessage)
        XCTAssertTrue(flow.history.visibleMessages.isEmpty)
    }

    func testSuspendedReceiptIsReplacedWithoutWaitingForCancelledTransport() async throws {
        let r = try ReadOnlyTextRig(), original = try r.seedOriginal()
        r.wire.pauseReceipts = [0]
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { r.wire.resumeReceipt(0); unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 }
        let protected = r.storage.rows
        r.write.revoke()
        try await waitFor { r.wire.lookups.count == 2 && flow.canCheckReceipt }
        XCTAssertEqual(flow.visibleState, .outcomeUnknown)
        XCTAssertEqual(r.wire.lookups, [original.clientMessageID, original.clientMessageID])
        r.wire.resumeReceipt(0)
        try await renderTurn(window)
        XCTAssertEqual(flow.visibleState, .outcomeUnknown); XCTAssertTrue(flow.canCheckReceipt)
        XCTAssertFalse(flow.canRetryOriginal); XCTAssertEqual(r.storage.rows, protected)
        XCTAssertTrue(r.wire.sent.isEmpty)
    }

    func testLosingBothGrantsDoesNotResumeAnyReadOrWrite() async throws {
        let r = try ReadOnlyTextRig(); _ = try r.seedOriginal()
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 && flow.canCheckReceipt }
        let protected = r.storage.rows
        r.read.revoke(); r.write.revoke()
        try await renderTurn(window)
        XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal); XCTAssertFalse(flow.canSendNew)
        XCTAssertEqual(flow.visibleState, .accessClosed); XCTAssertNil(flow.pendingText)
        XCTAssertEqual(r.wire.lookups.count, 1); XCTAssertTrue(r.wire.sent.isEmpty)
        XCTAssertEqual(r.storage.rows, protected)
    }

    func testLostCurrentIdentityCannotUseRemainingReadIssuance() async throws {
        let r = try ReadOnlyTextRig(); _ = try r.seedOriginal()
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 && flow.canCheckReceipt }
        let protected = r.storage.rows
        r.live = false; r.write.revoke()
        try await renderTurn(window)
        XCTAssertFalse(flow.isCurrent); XCTAssertFalse(flow.canCheckReceipt); XCTAssertNil(flow.pendingText)
        XCTAssertEqual(r.wire.lookups.count, 1); XCTAssertTrue(r.wire.sent.isEmpty)
        XCTAssertEqual(r.storage.rows, protected); XCTAssertFalse(r.read.isRevoked)
    }

    func testInactiveSceneOrUnavailableHistoryDoesNotStartRecoveryOnWriteLoss() async throws {
        for historyReady in [false, true] {
            let r = try ReadOnlyTextRig(); _ = try r.seedOriginal()
            let flow = try await r.makeFlow()
            let window = mount(flow, historyReady: historyReady, phase: historyReady ? .inactive : .active)
            defer { unmount(window, flow: flow) }
            try await renderTurn(window)
            let protected = r.storage.rows
            r.write.revoke()
            try await renderTurn(window)
            XCTAssertTrue(r.wire.lookups.isEmpty); XCTAssertTrue(r.wire.sent.isEmpty)
            XCTAssertEqual(r.storage.rows, protected); XCTAssertFalse(flow.canCheckReceipt)
        }
    }

    func testPreviouslyClosedOriginalNeverReopensWhenSendGrantIsLost() async throws {
        let r = try ReadOnlyTextRig(); _ = try r.seedOriginal()
        r.wire.receiptBody = #"{"code":409,"errorCode":"IM_CONVERSATION_CLOSED"}"#
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 && flow.visibleState == .accessClosed }
        let protected = r.storage.rows
        r.write.revoke()
        try await renderTurn(window)
        XCTAssertFalse(flow.canCheckReceipt); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertNil(flow.pendingText); XCTAssertEqual(r.wire.lookups.count, 1)
        XCTAssertTrue(r.wire.sent.isEmpty); XCTAssertEqual(r.storage.rows, protected)
    }

    func testIndependentReadOnlyMountUsesOriginalKeyAndDefaultsStayClosed() async throws {
        let r = try ReadOnlyTextRig(), original = try r.seedOriginal()
        r.write.revoke()
        let flow = try await r.makeFlow(), window = mount(flow)
        defer { unmount(window, flow: flow) }
        try await waitFor { r.wire.lookups.count == 1 && flow.canCheckReceipt }
        XCTAssertEqual(r.wire.lookups, [original.clientMessageID]); XCTAssertTrue(r.wire.sent.isEmpty)
        XCTAssertFalse(flow.canSendNew); XCTAssertFalse(flow.canRetryOriginal)
        XCTAssertNotNil(try r.journal.restore())
        XCTAssertFalse(flow.history.client.canReadThrough); XCTAssertFalse(flow.history.client.canLoadNewer)
        XCTAssertFalse(r.read.isRevoked)
    }

    private func mount(_ flow: NativeChannelTextCoordinator, historyReady: Bool = true, phase: ScenePhase = .active) -> UIWindow {
        let controller = UIHostingController(rootView: NativeChannelTextComposer(coordinator: flow, historyReady: historyReady)
            .environment(\.scenePhase, phase))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); controller.view.layoutIfNeeded()
        return window
    }
    private func unmount(_ window: UIWindow, flow: NativeChannelTextCoordinator) {
        window.isHidden = true; window.rootViewController = nil
        flow.stop(); flow.onChange = nil
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The hosted original receipt transition did not occur")
        throw APIError.notConfigured
    }
    private func renderTurn(_ window: UIWindow) async throws {
        for _ in 0..<10 {
            window.rootViewController?.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor private final class ReadOnlyTextRig {
    let context: RuntimeDependencyContext
    let read: NativeChannelTextApproval
    let write: NativeChannelTextApproval
    let storage = ReadOnlyTextStorage()
    let wire: ReadOnlyTextWire
    let journal: NativeChannelTextJournal
    var live = true
    init() throws {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "readonly-text-" + UUID().uuidString, token: "synthetic-token"))
        context = c; wire = ReadOnlyTextWire(baseURL: c.baseURL)
        read = try .init(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        write = try .init(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        journal = NativeChannelTextJournal(storage: storage, scope: try .init(context: c, conversationID: 9))
    }
    func seedOriginal() throws -> MessageTextIntent {
        let value = try MessageTextIntent(conversationID: 9, content: "original body", clientMessageID: "readonly-original-0001")
        try journal.saveBeforeDispatch(value); return value
    }
    func makeFlow() async throws -> NativeChannelTextCoordinator {
        let c = context
        let transport = NativeChannelTextTransport(context: c, transport: wire, current: { self.live ? c : nil },
            read: { self.read }, write: { self.write }, stillCurrent: { self.live })
        let client = try NativeChannelTextClient(context: c, conversationID: 9, transport: transport)
        let historyClient = NativeChannelSessionClient(history: ReadOnlyTextHistory(),
            currentSession: { self.live ? try? .init(accountID: 7, epoch: 1, token: "synthetic-token") : nil },
            isAvailable: { self.live })
        let conversation = try JSONDecoder().decode(MessagingConversation.self,
            from: Data(#"{"conversationId":9,"type":4,"counterparty":{"bizKey":"club_42"}}"#.utf8))
        let history = NativeChannelHistoryModel(conversation: conversation, client: historyClient)
        history.activate(); await history.load()
        return try NativeChannelTextCoordinator(history: history, client: client, journal: journal)
    }
}
@MainActor private final class ReadOnlyTextStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class ReadOnlyTextHistory: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try JSONDecoder().decode(MessagingPage.self, from: Data(#"{"list":[],"hasMore":false}"#.utf8))
    }
}
@MainActor private final class ReadOnlyTextWire: HTTPTransport {
    let baseURL: URL
    var sent: [MessageTextIntent] = [], lookups: [String] = []
    var pauseSend = false
    var pauseReceipts: Set<Int> = []
    var receiptBody = #"{"code":200,"data":{"found":false,"message":null}}"#
    private var sends: [Int: CheckedContinuation<Void, Error>] = [:]
    private var reads: [Int: CheckedContinuation<Void, Error>] = [:]
    init(baseURL: URL) { self.baseURL = baseURL }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let route = NativeChannelTextRoute(request: request, baseURL: baseURL) else { throw APIError.invalidRequest }
        switch route {
        case .send(let original):
            let index = sent.count; sent.append(original)
            if pauseSend { try await withCheckedThrowingContinuation { sends[index] = $0 } }
            let body: [String: Any] = ["code": 200, "data": ["id": 17, "conversationId": original.conversationID,
                "senderId": 7, "msgType": 1, "status": 0, "clientMessageId": original.clientMessageID, "content": original.content]]
            return (try JSONSerialization.data(withJSONObject: body), 200)
        case .receipt(_, let key):
            let index = lookups.count; lookups.append(key)
            if pauseReceipts.contains(index) { try await withCheckedThrowingContinuation { reads[index] = $0 } }
            return (Data(receiptBody.utf8), 200)
        default: throw APIError.invalidRequest
        }
    }
    func resumeSend(_ index: Int) { sends.removeValue(forKey: index)?.resume() }
    func resumeReceipt(_ index: Int) { reads.removeValue(forKey: index)?.resume() }
}
