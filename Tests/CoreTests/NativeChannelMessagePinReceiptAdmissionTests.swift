import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelMessagePinReceiptAdmissionTests: XCTestCase {
    func testPinAndUnpinWithoutReceiptRejectSelectionAndNeverSaveOrSend() async throws {
        for operation in [NativeChannelMessageOperation.pin, .unpin] {
            let h = try PinReceiptAdmissionFixture([.mutations, .pins, .mutate(operation)])
            let (client, journal, _) = try h.stack()
            XCTAssertTrue(client.allows(.mutate(operation)))
            XCTAssertFalse(client.allows(.receipt))
            XCTAssertThrowsError(try NativeChannelMessagePinSelection(
                snapshot: h.snapshot(pinned: operation == .unpin), client: client))
            let flow = try await ready(client, journal)
            XCTAssertTrue(flow.canStart)
            await flow.submit(try h.command(operation))
            XCTAssertEqual(flow.state, .idle)
            XCTAssertNil(flow.original)
            XCTAssertNil(try journal.restore())
            XCTAssertEqual(h.saves, 0)
            XCTAssertTrue(h.stored.isEmpty)
            XCTAssertTrue(h.requests.isEmpty)
        }
    }

    func testPinAndUnpinSelectionBecomesStaleWhenReceiptIsRevoked() throws {
        for operation in [NativeChannelMessageOperation.pin, .unpin] {
            let h = try PinReceiptAdmissionFixture([.receipt, .mutations, .mutate(operation)])
            let (client, _, _) = try h.stack()
            let selection = try NativeChannelMessagePinSelection(
                snapshot: h.snapshot(pinned: operation == .unpin), client: client)
            XCTAssertEqual(selection.command.operation, operation)
            XCTAssertTrue(selection.isCurrent(client))
            h.capabilities.remove(.receipt)
            XCTAssertFalse(selection.isCurrent(client))
            XCTAssertEqual(h.saves, 0)
            XCTAssertTrue(h.requests.isEmpty)
        }
    }

    func testReceiptOnlyRecoveryPreservesPendingAndSettlesOriginalWithoutPost() async throws {
        for operation in [NativeChannelMessageOperation.pin, .unpin, .sort] {
            let h = try PinReceiptAdmissionFixture([.receipt])
            let (client, journal, _) = try h.stack()
            let original = try h.command(operation)
            try journal.saveBeforeDispatch(original)
            let savedBytes = h.stored
            XCTAssertTrue(client.allows(.receipt))
            XCTAssertFalse(client.allows(.mutate(operation)))
            let flow = try NativeChannelMessageCoordinator(client: client, journal: journal,
                invalidateOriginalMessage: { _ in }, refreshOriginalHistory: {})
            h.bytes = try h.receipt(original, state: "NOT_FOUND")
            await flow.activate()
            XCTAssertEqual(flow.state, .unknown)
            XCTAssertEqual(h.stored, savedBytes)
            h.bytes = try h.receipt(original, state: "PENDING")
            await flow.recover()
            XCTAssertEqual(flow.state, .unknown)
            XCTAssertEqual(flow.original, original)
            XCTAssertEqual(h.stored, savedBytes)
            h.bytes = try h.receipt(original, state: "APPLIED")
            await flow.recover()
            XCTAssertEqual(flow.state, .applied(redacted: true))
            XCTAssertNil(flow.original)
            XCTAssertNil(try journal.restore())
            XCTAssertEqual(h.saves, 1)
            XCTAssertEqual(h.requests.count, 3)
            for request in h.requests {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertNil(request.httpBody)
                XCTAssertEqual(request.url?.absoluteString,
                    h.context.baseURL.absoluteString + "/api/im/message/request?request_id=" + original.requestID)
            }
        }
    }

    func testSortStillRequiresReceiptBeforeSaving() async throws {
        let h = try PinReceiptAdmissionFixture([.mutations, .mutate(.sort)])
        let (client, journal, _) = try h.stack()
        let flow = try await ready(client, journal)
        XCTAssertTrue(flow.canStart)
        await flow.submit(try h.command(.sort))
        XCTAssertEqual(flow.state, .idle)
        XCTAssertNil(flow.original)
        XCTAssertNil(try journal.restore())
        XCTAssertEqual(h.saves, 0)
        XCTAssertTrue(h.requests.isEmpty)
    }

    func testSortAckStillReadsOriginalReceiptAndPendingDoesNotSettle() async throws {
        let h = try PinReceiptAdmissionFixture([.receipt, .mutations, .mutate(.sort)])
        let (client, journal, _) = try h.stack()
        let original = try h.command(.sort)
        let pending = try h.receipt(original, state: "PENDING")
        let ack = Data(#"{"code":200,"data":{"updated":2,"sort_nos":{"20":200,"10":100}}}"#.utf8)
        h.response = { $0.httpMethod == "POST" ? ack : pending }
        let flow = try await ready(client, journal)
        XCTAssertTrue(flow.canStart)
        await flow.submit(original)
        XCTAssertEqual(flow.state, .unknown)
        XCTAssertEqual(flow.original, original)
        XCTAssertEqual(try journal.restore(), original)
        XCTAssertEqual(h.saves, 1)
        XCTAssertEqual(h.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(h.requests.first?.url?.path, "/native/api/im/pins/sort")
        XCTAssertEqual(h.requests.first?.httpBody,
            try JSONSerialization.data(withJSONObject: original.body, options: [.sortedKeys]))
        XCTAssertEqual(h.requests.last?.url?.absoluteString,
            h.context.baseURL.absoluteString + "/api/im/message/request?request_id=" + original.requestID)
    }

    func testFinalForwardRejectsRevokedReceiptBeforePinUnpinOrSortWrite() async throws {
        for operation in [NativeChannelMessageOperation.pin, .unpin, .sort] {
            let h = try PinReceiptAdmissionFixture([.receipt, .mutations, .mutate(operation)])
            let (client, journal, forward) = try h.stack()
            let original = try h.command(operation)
            try journal.saveBeforeDispatch(original)
            let savedBytes = h.stored
            let request = try h.writeRequest(original)
            XCTAssertTrue(client.allows(.mutate(operation)))
            XCTAssertTrue(client.allows(.receipt))
            h.capabilities.remove(.receipt)
            do {
                _ = try await forward.send(request, fence: .init { true })
                XCTFail("Revoked receipt must block the final write")
            } catch {
                XCTAssertEqual(error as? APIError, .notConfigured)
            }
            XCTAssertTrue(h.requests.isEmpty)
            XCTAssertEqual(h.stored, savedBytes)
            XCTAssertEqual(try journal.restore(), original)
            XCTAssertEqual(h.saves, 1)
        }
    }

    private func ready(_ client: NativeChannelMessageService,
                       _ journal: NativeChannelMessageMutationJournal) async throws -> NativeChannelMessageCoordinator {
        let flow = try NativeChannelMessageCoordinator(client: client, journal: journal,
            invalidateOriginalMessage: { _ in }, refreshOriginalHistory: {})
        await flow.activate()
        try flow.replacedHistory(cursor: "0", contract: "VISIBLE_ORDER_PLUS_MUTATIONS_V1",
            cacheAction: "RELOAD_ON_RESUME", rows: [])
        return flow
    }
}

@MainActor private final class PinReceiptAdmissionFixture:
    NativeChannelMessageAuthorizing, ProjectEditDataStorage, HTTPTransport {
    let context: RuntimeDependencyContext
    let value: NativeChannelMessageCredentials
    var identity: MessagingReadIdentity? { value.identity }
    var capabilities: Set<NativeChannelMessageCapability>
    var stored: [String: Data] = [:]
    var saves = 0
    var requests: [URLRequest] = []
    var bytes = Data()
    var response: ((URLRequest) -> Data)?
    init(_ capabilities: Set<NativeChannelMessageCapability>) throws {
        self.capabilities = capabilities
        context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.com/native")!,
            role: "player", session: try .init(accountID: 3, epoch: 1, namespace: "pin-receipt-test", token: "test-token"))
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!,
            conversationID: .init(rawValue: "9")!, mappingRevision: "test-mapping")
        value = try .init(identity: .init(accountID: 3, epoch: 1), namespace: context.session.namespace,
            baseURL: context.baseURL, binding: binding, authorityRevision: "test-source", token: context.session.token)
    }
    func credentials(for capability: NativeChannelMessageCapability,
                     binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard capabilities.contains(capability), binding == value.binding else { throw APIError.notConfigured }
        return value
    }
    func read(_ key: String) throws -> Data? { stored[key] }
    func write(_ data: Data, key: String) throws { saves += 1; stored[key] = data }
    func remove(_ key: String) throws { stored[key] = nil }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (response?(request) ?? bytes, 200)
    }
    func stack() throws -> (NativeChannelMessageService, NativeChannelMessageMutationJournal, NativeChannelMessageFinalForward) {
        let authority = try NativeChannelMessageHostAuthority(context: context, viewerRevision: 1,
            binding: value.binding, source: self, current: { self.context }, viewer: { 1 }, selected: { self })
        let journal = NativeChannelMessageMutationJournal(scope: .init(credentials: value), storage: self)
        let forward = try NativeChannelMessageFinalForward(authority: authority, journal: journal,
            underlying: self, current: { true }, onUnauthorized: { _ in })
        return (.init(credentials: value, authority: authority, transport: forward, onUnauthorized: { _ in }), journal, forward)
    }
    func command(_ operation: NativeChannelMessageOperation) throws -> NativeChannelMessageCommand {
        try .init(operation: operation, requestID: "receipt_guard_\(operation.rawValue)_0001", binding: value.binding,
            messageID: operation == .sort ? nil : .init(rawValue: "8")!,
            orderedPinIDs: operation == .sort ? [.init(rawValue: "20")!, .init(rawValue: "10")!] : [])
    }
    func snapshot(pinned: Bool) throws -> NativeChannelMessageSnapshot {
        try JSONDecoder().decode(NativeChannelMessageSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": "8", "conversationId": "9", "version": 1, "status": 0, "msgType": 1, "content": "original", "pinned": pinned]))
    }
    func receipt(_ command: NativeChannelMessageCommand, state: String) throws -> Data {
        var body: [String: Any] = ["request_id": command.requestID, "state": state, "outcome_confirmed": state == "APPLIED"]
        if state == "APPLIED" {
            body["operation"] = command.operation.rawValue; body["conversation_id"] = "9"; body["result_redacted"] = true
        }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
    }
    func writeRequest(_ command: NativeChannelMessageCommand) throws -> URLRequest {
        let path = command.operation == .pin ? "api/im/pin" : command.operation == .unpin ? "api/im/unpin" : "api/im/pins/sort"
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(value.token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: command.body, options: [.sortedKeys])
        return request
    }
}
