import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelChainReceiptPresentationTests: XCTestCase {
    func testConfirmedReceiptSurvivesFailedIndependentCurrentRead() async throws {
        let h = try ChainReceiptHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        let command = try XCTUnwrap(flow.review); await flow.confirm()
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(flow.phase, .applied); XCTAssertNil(flow.pending)
        await flow.refresh()
        XCTAssertTrue(flow.readFailed); XCTAssertEqual(flow.phase, .failed)
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(flow.lastConfirmedRequest?.operation, .create)
        XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
        XCTAssertEqual(h.wire.posts, 1); XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testUnknownWriteDoesNotInventConfirmedReceiptOrClearOriginalJournal() async throws {
        let h = try ChainReceiptHarness(); h.wire.failWrite = true; let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        await flow.confirm()
        XCTAssertEqual(flow.phase, .unknown); XCTAssertNotNil(flow.pending)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        XCTAssertEqual(h.wire.posts, 1)
    }
    func testRedactedReceiptRetainsOnlyConfirmedRequestIdentity() async throws {
        let h = try ChainReceiptHarness(); h.wire.redacted = true; let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        await flow.confirm()
        XCTAssertEqual(flow.phase, .appliedRedacted)
        XCTAssertEqual(flow.lastConfirmedRequest?.resultRedacted, true)
        XCTAssertNil(flow.reference); XCTAssertNil(flow.page); XCTAssertTrue(flow.entries.isEmpty)
        XCTAssertTrue(h.storage.rows.isEmpty)
    }
    func testReceiptGrantRevocationHidesRetainedReceiptWithoutWriting() async throws {
        let h = try ChainReceiptHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        await flow.confirm(); XCTAssertNotNil(flow.lastConfirmedRequest)
        let count = h.wire.calls; h.receiptGranted = false
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertEqual(h.wire.calls, count)
    }
    func testAccountChangeAndDeactivationClearPresentationNotForgeNewReceipt() async throws {
        let h = try ChainReceiptHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        await flow.confirm(); XCTAssertNotNil(flow.lastConfirmedRequest)
        h.live = false; XCTAssertNil(flow.lastConfirmedRequest)
        flow.deactivate(); XCTAssertNil(flow.lastConfirmedRequest)
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertEqual(h.wire.posts, 1)
    }
    func testReentryDoesNotRestoreReceiptFromCurrentState() async throws {
        let h = try ChainReceiptHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepareCreate(title: "Original", maxSlots: 0, deadline: nil)
        await flow.confirm(); XCTAssertNotNil(flow.lastConfirmedRequest)
        flow.deactivate(); await flow.activate(current: { h.live })
        XCTAssertNil(flow.lastConfirmedRequest)
        XCTAssertEqual(h.wire.posts, 1)
    }
}
@MainActor private final class ChainReceiptStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class ChainReceiptWire: HTTPTransport {
    var calls = 0, posts = 0
    var failWrite = false, redacted = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        guard request.httpMethod == "POST" else { throw APIError.malformedResponse }
        posts += 1
        if failWrite { throw APIError.malformedResponse }
        let command = try JSONDecoder().decode(NativeChannelChainCommand.self, from: XCTUnwrap(request.httpBody))
        var receipt: [String: Any] = ["source": "original-channel-chain-request-v1", "actorId": "11", "conversationId": "42",
            "requestId": command.requestId, "state": "APPLIED", "operation": command.operation.rawValue,
            "requestHash": command.digest, "resultRedacted": redacted]
        if !redacted { receipt["result"] = ["chainId": "7", "messageId": "8", "creatorMemberId": "11",
            "chainVersion": "1", "status": "OPEN", "activeCount": 0] }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]), 200)
    }
}
@MainActor private final class ChainReceiptHarness {
    let context: RuntimeDependencyContext
    let wire = ChainReceiptWire(), storage = ChainReceiptStorage()
    var live = true, receiptGranted = true
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:chain-fixture", token: "fixture-token"))
    }
    func flow() throws -> NativeChannelChainFlow {
        let service = try NativeChannelChainService(context: context, conversationID: "42", transport: wire,
            permits: { _, path in path != "api/im/interaction/request" || self.receiptGranted },
            current: { self.live }, unauthorized: {})
        return try .init(service: service, context: context, storage: storage, reference: nil)
    }
}
