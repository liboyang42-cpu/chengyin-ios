import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored XCTest source only. Synthetic local wire, not live arrival or an App execution claim.
@available(macOS 14.0, *) @MainActor final class CityArrivalEvidencePortJourneyTests: XCTestCase {
    let base = URL(string: "https://example.test/native")!
    let team = "11111111-1111-1111-1111-111111111111", session = "22222222-2222-2222-2222-222222222222", challengeID = "33333333-3333-3333-3333-333333333333"
    var board: CityReadBoard { .init(gameId: "game-1", boardId: "board-1", regionId: "city-1", seasonId: "season-1", rulesReleaseId: "release-1", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "Synthetic CITY", revision: 1) }
    func grant(_ audience: CityArrivalAudience = .player(regionID: "city-1"), writes: Bool = true) throws -> CityArrivalEvidenceApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-arrival", token: "synthetic-token")), audience: audience, allowsWrite: writes, expiresAt: Date().addingTimeInterval(600))
    }
    func service(_ approval: CityArrivalEvidenceApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityArrivalEvidenceService {
        .init(approval: approval, transport: .init(approval: approval, underlying: wire, current: current ?? { approval.context }, selected: { _, _ in approval }), board: board)
    }
    func response(_ data: [String: Any], status: Int = 200) throws -> (Data, Int) { (try JSONSerialization.data(withJSONObject: ["code": status, "data": data]), status) }
    func challenge(_ request: String, subject: Int = 7) -> [String: Any] {
        ["challengeId": challengeID, "requestId": request, "pointId": "point-1", "teamId": team, "sessionId": session, "contentHash": String(repeating: "a", count: 64), "policyHash": String(repeating: "b", count: 64), "regionId": "city-1", "boardId": "board-1", "seasonId": "season-1", "roundId": "round-a", "rulesReleaseId": "release-1", "state": "ISSUED", "expiresAt": "2099-01-01T00:00:00Z", "memberId": subject, "merchantId": 41, "placeId": 61, "releaseId": 1, "version": 1, "ordinal": 1]
    }
    func command(_ kind: String, extras: [String: Any] = [:]) throws -> URLRequest {
        var body: [String: Any] = ["requestId": UUID().uuidString, "kind": kind, "challengeId": challengeID, "expectedVersion": 1, "displayCode": String(repeating: "A", count: 32)]
        if kind == "CONFIRM" { body["reason"] = "Synthetic personally witnessed presentation" }
        body.merge(extras) { _, new in new }
        var request = URLRequest(url: base.appendingPathComponent("api/city-game/arrival-evidence/command")); request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); return request
    }
    func testDisabledControllerCannotWrite() { let c = CityArrivalEvidenceController(audience: .player(regionID: "city-1"), service: nil, journal: Journal()); XCTAssertFalse(c.canWrite); XCTAssertNil(c.confirmation) }
    func testAudienceRoutesCannotPromotePlayerToStaffOrAcceptClientAuthority() throws {
        let submit = try command("SUBMIT"), confirm = try command("CONFIRM")
        XCTAssertNotNil(CityArrivalEvidenceRoute(request: submit, baseURL: base, audience: .player(regionID: "city-1")))
        XCTAssertNil(CityArrivalEvidenceRoute(request: submit, baseURL: base, audience: .merchant(merchantID: 41)))
        XCTAssertNil(CityArrivalEvidenceRoute(request: confirm, baseURL: base, audience: .player(regionID: "city-1")))
        XCTAssertNotNil(CityArrivalEvidenceRoute(request: confirm, baseURL: base, audience: .merchant(merchantID: 41)))
        for key in ["memberId", "confidence", "latitude", "passed"] { XCTAssertNil(CityArrivalEvidenceRoute(request: try command("CONFIRM", extras: [key: 1]), baseURL: base, audience: .merchant(merchantID: 41))) }
    }
    func testReadOnlyApprovalAndRevocationNeverReachWriteWire() async throws {
        let approval = try grant(writes: false), wire = Wire(), client = service(approval, wire)
        var request = try command("SUBMIT"); request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await client.transport.send(request); XCTFail("read-only") } catch {}
        approval.revoke(); do { _ = try await client.player(); XCTFail("revoked") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginalIssueReceiptCodeCannotBeBorrowedByAnotherMember() async throws {
        let approval = try grant(), wire = Wire(), client = service(approval, wire), id = UUID().uuidString
        wire.respond = { _ in try self.response(["requestId": id, "requestStatus": "COMPLETE", "challenge": self.challenge(id), "displayCode": String(repeating: "A", count: 32)]) }
        let value = try await client.receipt(id); XCTAssertEqual(value.displayCode, String(repeating: "A", count: 32))
        wire.respond = { _ in try self.response(["requestId": id, "requestStatus": "COMPLETE", "challenge": self.challenge(id, subject: 8), "displayCode": String(repeating: "A", count: 32)]) }
        do { _ = try await client.receipt(id); XCTFail("wrong original subject") } catch {}
    }
    func testUnknownRecoveryPersistsOriginalJournalWithoutAnotherPost() async throws {
        let approval = try grant(), wire = Wire(), journal = Journal(), id = UUID()
        journal.record = .init(operationID: id, ownerKey: "city-arrival:city-arrival:\(base.absoluteString):7", targetKey: "player:city-1")
        wire.respond = { request in
            if request.url!.path.hasSuffix("/state") { return try self.response(["contract": "CITY_ARRIVAL_EVIDENCE_V1", "status": "JOIN_REQUIRED", "writeApproved": false, "points": []]) }
            return try self.response(["requestId": id.uuidString, "requestStatus": "UNKNOWN"], status: 202)
        }
        let c = CityArrivalEvidenceController(audience: approval.audience, service: service(approval, wire), journal: journal)
        await c.load(); await c.recover(); XCTAssertNotNil(journal.record); XCTAssertEqual(c.pendingRequestID, id); XCTAssertFalse(c.canWrite); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testContextChangedDuringReadDiscardsResponse() async throws {
        let approval = try grant(), wire = Wire(); var current: RuntimeDependencyContext? = approval.context
        wire.respond = { _ in current = nil; return try self.response(["contract": "CITY_ARRIVAL_EVIDENCE_V1", "status": "JOIN_REQUIRED", "writeApproved": false, "points": []]) }
        let c = CityArrivalEvidenceController(audience: approval.audience, service: service(approval, wire, current: { current }), journal: Journal()); await c.load(); XCTAssertNil(c.player); XCTAssertFalse(c.canWrite)
    }
    func testSameAccountDifferentCredentialCannotReuseApproval() throws {
        let approval = try grant()
        let changed = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "city-arrival", token: "different-token"))
        XCTAssertFalse(approval.matches(changed))
    }
    func testExplicitAndAutomaticCookiesAreRejectedBeforeWire() async throws {
        let approval = try grant(), wire = Wire(), client = service(approval, wire)
        var request = try command("SUBMIT"); request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        request.httpShouldHandleCookies = true
        do { _ = try await client.transport.send(request); XCTFail("automatic cookie") } catch {}
        request.httpShouldHandleCookies = false; request.setValue("synthetic=1", forHTTPHeaderField: "Cookie")
        do { _ = try await client.transport.send(request); XCTFail("explicit cookie") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testMerchantReasonUsesOriginalJavaUTF16LimitWithoutTruncating() throws {
        let exact = String(repeating: "😀", count: 250), over = exact + "x"
        XCTAssertNotNil(CityArrivalEvidenceRoute(request: try command("CONFIRM", extras: ["reason": exact]), baseURL: base, audience: .merchant(merchantID: 41)))
        XCTAssertNil(CityArrivalEvidenceRoute(request: try command("CONFIRM", extras: ["reason": over]), baseURL: base, audience: .merchant(merchantID: 41)))
        XCTAssertEqual(over.utf16.count, 501)
    }
    func testMerchantConfirmJournalsBeforePostAndReadsOnlyOriginalReceipt() async throws {
        let approval = try grant(.merchant(merchantID: 41)), wire = Wire(), journal = Journal()
        var pending = challenge("original-issue", subject: 8); pending["state"] = "SUBMITTED"; pending["version"] = 2
        var sentID: String?
        wire.respond = { request in
            if request.httpMethod == "POST" {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
                let id = try XCTUnwrap(body["requestId"] as? String)
                XCTAssertEqual(journal.record?.operationID.uuidString, id)
                XCTAssertEqual(body["kind"] as? String, "CONFIRM"); XCTAssertNil(body["memberId"])
                sentID = id; return (Data(), 500)
            }
            if request.url!.path.hasSuffix("/merchant") {
                return try self.response(["contract": "CITY_ARRIVAL_EVIDENCE_V1", "merchantId": 41, "ownerMemberId": 7, "role": "MERCHANT_OWNER", "writeApproved": true, "pending": sentID == nil ? [pending] : []])
            }
            let id = try XCTUnwrap(sentID); XCTAssertTrue(request.url!.path.hasSuffix("/request/" + id))
            var confirmed = pending; confirmed["state"] = "CONFIRMED"; confirmed["version"] = 3
            return try self.response(["requestId": id, "requestStatus": "COMPLETE", "challenge": confirmed])
        }
        let controller = CityArrivalEvidenceController(audience: approval.audience, service: service(approval, wire), journal: journal)
        await controller.load(); let claim = try XCTUnwrap(controller.merchant?.pending.first)
        controller.prepareReview(claim, confirms: true, code: String(repeating: "A", count: 32), reason: "Synthetic explicit review")
        let confirmation = try XCTUnwrap(controller.confirmation); await controller.confirm(confirmation)
        XCTAssertNil(journal.record); XCTAssertTrue(try XCTUnwrap(controller.receipt).succeeded)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testMissingOriginalReceiptNeverUnlocksJournal() async throws {
        let approval = try grant(), wire = Wire(), journal = Journal(), id = UUID()
        journal.record = .init(operationID: id, ownerKey: "city-arrival:city-arrival:\(base.absoluteString):7", targetKey: "player:city-1")
        wire.respond = { request in
            if request.url!.path.hasSuffix("/state") { return try self.response(["contract": "CITY_ARRIVAL_EVIDENCE_V1", "status": "JOIN_REQUIRED", "writeApproved": false, "points": []]) }
            return try self.response([:], status: 404)
        }
        let controller = CityArrivalEvidenceController(audience: approval.audience, service: service(approval, wire), journal: journal)
        await controller.load(); await controller.recover(); await controller.recover()
        XCTAssertEqual(journal.record?.operationID, id); XCTAssertFalse(controller.canWrite)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    @MainActor final class Wire: HTTPTransport { var requests: [URLRequest] = []; var respond: ((URLRequest) throws -> (Data, Int))?; func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try respond?(request) ?? (Data(), 500) } }
    @MainActor final class Journal: OperationPendingJournal { var record: OperationPendingRecord?; func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record }; func write(_ value: OperationPendingRecord) throws { guard record == nil || record == value else { throw APIError.invalidRequest }; record = value }; func clear(_ value: OperationPendingRecord) throws { guard record == value else { throw APIError.invalidRequest }; record = nil } }
}
