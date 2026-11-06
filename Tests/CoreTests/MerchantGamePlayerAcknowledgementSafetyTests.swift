import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic original-result reads only. No production grant or business request.
@MainActor final class MerchantGamePlayerAcknowledgementSafetyTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var reply: (URLRequest) async throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try await reply(request)
        }
    }
    final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        var clearCount = 0
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }
            return record
        }
        func write(_ value: OperationPendingRecord) throws {
            guard record == nil || record == value else { throw APIError.invalidRequest }
            record = value
        }
        func clear(_ value: OperationPendingRecord) throws {
            guard record == value else { throw APIError.invalidRequest }
            record = nil; clearCount += 1
        }
    }
    final class Scope { var current: MerchantGamePlayerSession? }
    struct Fixture {
        let service: MerchantGamePlayerService
        let journal: Journal
        let wire: Wire
        let record: OperationPendingRecord
        let scope: Scope
    }
    private func fixture() throws -> Fixture {
        let api = try APIConfiguration(baseURL: URL(string: "https://ack.example.test/native/")!)
        let captured = try MerchantGamePlayerSession(namespace: "fixture", accountID: 10, epoch: 1, credential: "synthetic-token")
        let scope = Scope(); scope.current = captured
        let wire = Wire(), journal = Journal()
        let record = OperationPendingRecord(ownerKey: "merchant-public-chat:\(api.baseURL.absoluteString):7:fixture:10", targetKey: "merchant-row:20")
        try journal.write(record)
        let grant = MerchantGamePlayerReadGrant(market: .china, endpoints: try OperationEndpointApproval(
            baseURL: api.baseURL, namespace: "fixture", accountID: 10, paths: MerchantGamePlayerReadGrant.playerPaths))
        let service = try MerchantGamePlayerService(configuration: api, merchantID: 20, session: captured,
            grant: grant, transport: wire, journal: journal, current: { scope.current })
        return .init(service: service, journal: journal, wire: wire, record: record, scope: scope)
    }
    private static func row(_ record: OperationPendingRecord, outcome: String = "FAILED", retryable: Bool = false,
                            text: String = "Original result") -> [String: Any] {
        ["merchantId": 20, "requestId": record.operationID.uuidString, "outcomeStatus": outcome,
         "safetyDecision": outcome == "SUCCEEDED" ? "PASS" : outcome == "PROCESSING" ? "UNKNOWN" : "NOT_RUN",
         "safeText": text, "errorCode": "SYNTHETIC_RESULT", "retryable": retryable, "ai": false]
    }
    private static func ok(_ row: [String: Any]) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
    }
    private static func original(_ row: [String: Any], record: OperationPendingRecord) throws -> MerchantGamePlayerOriginal {
        let data = try JSONSerialization.data(withJSONObject: row)
        return try MerchantGamePlayerOriginal(row: JSONDecoder().decode([String: ProjectEditJSON].self, from: data),
                                              merchantID: 20, requestID: record.operationID)
    }
    private func assertOriginalReadOnly(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        for request in f.wire.requests {
            XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
            XCTAssertNil(request.httpBody, file: file, line: line)
            XCTAssertFalse(request.httpShouldHandleCookies, file: file, line: line)
            XCTAssertTrue(request.url!.path.hasSuffix("/game") || request.url!.path.hasSuffix(f.record.operationID.uuidString), file: file, line: line)
        }
    }
    func testRetryableTerminalResultsCannotAcknowledgeOrUnlockFreshChat() async throws {
        for outcome in ["FAILED", "REJECTED", "SUCCEEDED"] {
            let f = try fixture()
            let response = Self.row(f.record, outcome: outcome, retryable: true)
            f.wire.reply = { request in
                if request.url!.path.hasSuffix("/game") { return try Self.ok(["merchantId": 20, "outcome": "NONE"]) }
                return try Self.ok(response)
            }
            let flow = MerchantGamePlayerCoordinator(service: f.service)
            await flow.load(); await flow.readOriginal()
            let value = try XCTUnwrap(flow.original)
            XCTAssertFalse(value.succeeded)
            XCTAssertFalse(MerchantGamePlayerReceipt.canAcknowledge(value, record: f.record, merchantID: 20))
            XCTAssertFalse(flow.canAcknowledge)
            XCTAssertThrowsError(try f.service.acknowledge(value, record: f.record))
            flow.acknowledgeOriginal()
            XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
            XCTAssertFalse(flow.canOpenChat); XCTAssertFalse(flow.acknowledged)
            assertOriginalReadOnly(f)
        }
    }
    func testNonretryableTerminalResultsStillRequireAndAllowExplicitExactAcknowledgement() async throws {
        for outcome in ["FAILED", "REJECTED", "SUCCEEDED"] {
            let f = try fixture()
            let payload = Self.row(f.record, outcome: outcome)
            f.wire.reply = { request in
                if request.url!.path.hasSuffix("/game") { return try Self.ok(["merchantId": 20, "outcome": "NONE"]) }
                return try Self.ok(payload)
            }
            let flow = MerchantGamePlayerCoordinator(service: f.service)
            await flow.load(); await flow.readOriginal()
            XCTAssertTrue(flow.canAcknowledge); XCTAssertFalse(flow.canOpenChat)
            XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
            flow.acknowledgeOriginal()
            XCTAssertNil(f.journal.record); XCTAssertEqual(f.journal.clearCount, 1)
            XCTAssertTrue(flow.acknowledged); XCTAssertTrue(flow.canOpenChat)
            assertOriginalReadOnly(f)
        }
    }
    func testProcessingRetainsExactOriginalWhetherRetryIsAllowedOrDenied() async throws {
        for retryable in [true, false] {
            let f = try fixture()
            let response = Self.row(f.record, outcome: "PROCESSING", retryable: retryable)
            f.wire.reply = { _ in try Self.ok(response) }
            let value = try await f.service.original(f.record)
            XCTAssertFalse(MerchantGamePlayerReceipt.canAcknowledge(value, record: f.record, merchantID: 20))
            XCTAssertThrowsError(try f.service.acknowledge(value, record: f.record))
            XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
            assertOriginalReadOnly(f)
        }
    }
    func testDiscardDuringSuspendedReadCannotRestoreAcknowledgementAuthority() async throws {
        let f = try fixture()
        let payload = Self.row(f.record)
        f.wire.reply = { _ in
            f.service.discardReadback()
            return try Self.ok(payload)
        }
        do { _ = try await f.service.original(f.record); XCTFail("Retired read accepted") }
        catch { XCTAssertEqual(error as? MerchantGamePlayerFailure, .stale) }
        let decoded = try Self.original(payload, record: f.record)
        XCTAssertThrowsError(try f.service.acknowledge(decoded, record: f.record))
        XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
        assertOriginalReadOnly(f)
    }
    func testNewerReadWinsWithoutOlderReplyReplacingItsVerifiedResult() async throws {
        let f = try fixture()
        let olderPayload = Self.row(f.record, text: "Older result")
        let newerPayload = Self.row(f.record, outcome: "REJECTED", text: "Newer result")
        var newest: MerchantGamePlayerOriginal?
        f.wire.reply = { _ in
            if f.wire.requests.count == 1 {
                newest = try await f.service.original(f.record)
                return try Self.ok(olderPayload)
            }
            return try Self.ok(newerPayload)
        }
        do { _ = try await f.service.original(f.record); XCTFail("Superseded read accepted") }
        catch { XCTAssertEqual(error as? MerchantGamePlayerFailure, .stale) }
        XCTAssertEqual(f.wire.requests.count, 2)
        XCTAssertThrowsError(try f.service.acknowledge(Self.original(olderPayload, record: f.record), record: f.record))
        try f.service.acknowledge(XCTUnwrap(newest), record: f.record)
        XCTAssertEqual(f.journal.clearCount, 1); XCTAssertNil(f.journal.record)
        assertOriginalReadOnly(f)
    }
    func testExplicitNewReadAfterDiscardCanReconcileSameOriginal() async throws {
        let f = try fixture()
        let response = Self.row(f.record)
        f.wire.reply = { _ in try Self.ok(response) }
        let prior = try await f.service.original(f.record)
        f.service.discardReadback()
        XCTAssertThrowsError(try f.service.acknowledge(prior, record: f.record))
        XCTAssertEqual(f.journal.record, f.record)
        let current = try await f.service.original(f.record)
        try f.service.acknowledge(current, record: f.record)
        XCTAssertEqual(f.journal.clearCount, 1); XCTAssertNil(f.journal.record)
        assertOriginalReadOnly(f)
    }
    func testRevokeAndReactivateDoNotAcceptPriorLifetimeResponse() async throws {
        let f = try fixture()
        let payload = Self.row(f.record)
        let flow = MerchantGamePlayerCoordinator(service: f.service)
        f.wire.reply = { _ in try Self.ok(["merchantId": 20, "outcome": "NONE"]) }
        await flow.load()
        f.wire.reply = { _ in
            flow.revoke(); flow.activate()
            return try Self.ok(payload)
        }
        await flow.readOriginal()
        XCTAssertNil(flow.original); XCTAssertFalse(flow.canAcknowledge); XCTAssertFalse(flow.canOpenChat)
        XCTAssertThrowsError(try f.service.acknowledge(Self.original(payload, record: f.record), record: f.record))
        XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
        assertOriginalReadOnly(f)
    }
    func testLateAccountChangeStillKeepsOriginalLocked() async throws {
        let f = try fixture()
        let payload = Self.row(f.record)
        f.wire.reply = { _ in
            f.scope.current = try MerchantGamePlayerSession(namespace: "fixture", accountID: 11, epoch: 2, credential: "other-synthetic-token")
            return try Self.ok(payload)
        }
        do { _ = try await f.service.original(f.record); XCTFail("Old account reply accepted") }
        catch { XCTAssertEqual(error as? MerchantGamePlayerFailure, .stale) }
        XCTAssertThrowsError(try f.service.acknowledge(Self.original(payload, record: f.record), record: f.record))
        XCTAssertEqual(f.journal.record, f.record); XCTAssertEqual(f.journal.clearCount, 0)
        assertOriginalReadOnly(f)
    }
}
