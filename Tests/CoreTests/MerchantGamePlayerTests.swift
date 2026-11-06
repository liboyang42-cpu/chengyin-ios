import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class GamePlayerWire: HTTPTransport {
    var requests: [URLRequest] = []
    var reply: (URLRequest) throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try reply(request) }
    static func ok(_ row: [String: Any]) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
    }
}
@MainActor final class MerchantGamePlayerTests: XCTestCase {
    private final class Scope { var current: MerchantGamePlayerSession? }
    private struct Fixture {
        let service: MerchantGamePlayerService, journal: OperationDefaultsJournal, record: OperationPendingRecord
        let wire: GamePlayerWire, scope: Scope
    }
    private func fixture(approved: Bool = true) throws -> Fixture {
        let api = try APIConfiguration(baseURL: URL(string: "https://player.example.test/native")!)
        let captured = try MerchantGamePlayerSession(namespace: "fixture", accountID: 10, epoch: 1, credential: "synthetic-token")
        let scope = Scope(); scope.current = captured
        let wire = GamePlayerWire(), journal = OperationDefaultsJournal(defaults: UserDefaults(suiteName: "player-"+UUID().uuidString)!)
        let record = OperationPendingRecord(ownerKey: "merchant-public-chat:\(api.baseURL.absoluteString):7:fixture:10", targetKey: "merchant-row:20")
        try journal.write(record)
        let grant = approved ? MerchantGamePlayerReadGrant(market: .china, endpoints: try OperationEndpointApproval(
            baseURL: api.baseURL, namespace: "fixture", accountID: 10, paths: MerchantGamePlayerReadGrant.playerPaths)) : nil
        let service = try MerchantGamePlayerService(configuration: api, merchantID: 20, session: captured,
            grant: grant, transport: wire, journal: journal, current: { scope.current })
        return .init(service: service, journal: journal, record: record, wire: wire, scope: scope)
    }
    private func row(_ record: OperationPendingRecord, status: String = "REJECTED", safety: String = "NOT_RUN") -> [String: Any] {
        ["merchantId": 20, "requestId": record.operationID.uuidString, "outcomeStatus": status, "safetyDecision": safety,
         "safeText": "Original fixed exit", "errorCode": "MERCHANT_ENVIRONMENT_EXIT", "retryable": false, "ai": false]
    }
    func testRestartReadsOriginalExitWithoutPromptOrResendAndOnlyExplicitAckClosesIt() async throws {
        let f = try fixture(); let original = row(f.record)
        f.wire.reply = { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertFalse(request.httpShouldHandleCookies)
            if request.url!.path.hasSuffix("/game") { return try GamePlayerWire.ok(["merchantId":20,"outcome":"PUBLISHED","releaseId":99,"revisionVersion":2,"facts":["canonical_plot":"Current version"]]) }
            XCTAssertTrue(request.url!.path.hasSuffix(f.record.operationID.uuidString)); return try GamePlayerWire.ok(original)
        }
        let flow = MerchantGamePlayerCoordinator(service: f.service)
        await flow.load(); XCTAssertEqual(flow.pending, f.record); XCTAssertFalse(flow.canOpenChat)
        XCTAssertNil(flow.original); XCTAssertEqual(f.wire.requests.count, 1)
        await flow.readOriginal(); XCTAssertEqual(flow.original?.safeText, "Original fixed exit")
        XCTAssertEqual(try f.service.pending(), f.record); XCTAssertTrue(flow.canAcknowledge)
        flow.acknowledgeOriginal(); XCTAssertNil(try f.service.pending()); XCTAssertTrue(flow.canOpenChat)
        XCTAssertEqual(f.wire.requests.count, 2) // no POST, provider, location or fresh game evaluation
    }
    func testUnknownMissingMalformedAndProcessingNeverReleaseOriginalMarker() async throws {
        for mode in 0..<5 {
            let f = try fixture(); var payload = row(f.record, status: "PROCESSING", safety: "UNKNOWN")
            if mode == 2 { payload["requestId"] = UUID().uuidString }
            if mode == 3 { payload["merchantId"] = 21 }
            if mode == 4 { payload["outcomeStatus"] = "UNKNOWN" }
            let response = payload
            f.wire.reply = { _ in
                if mode == 1 { return (Data(#"{"code":404}"#.utf8),200) }
                return try GamePlayerWire.ok(response)
            }
            let flow = MerchantGamePlayerCoordinator(service: f.service)
            // Restore pending without requiring publication availability first.
            await flow.load(); await flow.readOriginal(); flow.acknowledgeOriginal()
            XCTAssertEqual(try f.service.pending(),f.record); XCTAssertFalse(flow.canAcknowledge)
        }
    }
    func testForgedUnverifiedOrNewerPendingCannotBeCleared() async throws {
        let f = try fixture(); let payload = row(f.record)
        f.wire.reply = { _ in try GamePlayerWire.ok(payload) }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let forged = try MerchantGamePlayerOriginal(row: JSONDecoder().decode([String: ProjectEditJSON].self,from:data),merchantID:20,requestID:f.record.operationID)
        XCTAssertThrowsError(try f.service.acknowledge(forged,record:f.record))
        let verified = try await f.service.original(f.record)
        try f.journal.clear(f.record)
        let newer = OperationPendingRecord(ownerKey:f.record.ownerKey,targetKey:f.record.targetKey); try f.journal.write(newer)
        XCTAssertThrowsError(try f.service.acknowledge(verified,record:f.record)); XCTAssertEqual(try f.service.pending(),newer)
    }
    func testNoApprovalNoDispatchAndLateScopeChangeNeverAcceptsReply() async throws {
        let disabled = try fixture(approved:false)
        do { _ = try await disabled.service.original(disabled.record); XCTFail("No approval dispatched") } catch {}
        XCTAssertTrue(disabled.wire.requests.isEmpty); XCTAssertEqual(try disabled.service.pending(),disabled.record)
        let f = try fixture(); let response = row(f.record)
        f.wire.reply = { _ in f.scope.current = nil; return try GamePlayerWire.ok(response) }
        do { _ = try await f.service.original(f.record); XCTFail("Late scope accepted") } catch {}
        XCTAssertEqual(try f.journal.pending(ownerKey:f.record.ownerKey,targetKey:f.record.targetKey),f.record)
    }
    func testUnauthorizedClearsViewNotJournalAndPublishedVersionIsNotOriginalIdentity() async throws {
        let f = try fixture(); f.wire.reply = { _ in (Data(#"{"code":403}"#.utf8),200) }
        let flow = MerchantGamePlayerCoordinator(service:f.service); await flow.load()
        XCTAssertFalse(flow.active); XCTAssertNil(flow.original); XCTAssertNil(flow.publication)
        XCTAssertEqual(try f.service.pending(),f.record)
    }
    func testUnloadedAndRevokedPlayerNeverPermitFreshChatBeforeJournalRead() throws {
        let f = try fixture()
        let flow = MerchantGamePlayerCoordinator(service: f.service)
        XCTAssertFalse(flow.canOpenChat)
        flow.revoke(); flow.activate()
        XCTAssertFalse(flow.canOpenChat)
        XCTAssertEqual(try f.service.pending(), f.record)
    }

}
