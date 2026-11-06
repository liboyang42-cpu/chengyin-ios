import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OriginalClubKeyTransport: ClubCommunityOfflineTransport {
    var requests: [URLRequest] = []
    var echoWrongKey = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.url?.lastPathComponent == "receipt" else { throw URLError(.timedOut) }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        var result = body; result["status"] = "ACKNOWLEDGED"
        if echoWrongKey { result["requestId"] = body["operationId"] }
        return (try JSONSerialization.data(withJSONObject: ["code":200,"data":result]), 200)
    }
}
@MainActor final class ClubCommunityOriginalRequestKeyTests: XCTestCase {
    private func exercise(_ operation: ClubCommunityOperation, expected: String, wrongEcho: Bool = false) async throws {
        let transport = OriginalClubKeyTransport()
        let base = URL(string: "https://original-key.invalid")!
        let service = ClubCommunityService(offlineBaseURL: base, transport: transport)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token")
        let post = try ClubCommunityPost(json: ["id":20,"clubId":10,"authorMemberId":5,"type":2,"content":"before","version":3])
        let evidence = ClubCommunityEvidence(identity: session.identity, clubID: 10, joined: true, owner: true, administrator: false, post: post)
        var storage: [String:Data] = [:]
        func journal() -> ClubCommunityStoredPendingJournal { .init(read: { storage[$0] }, write: { storage[$1]=$0 }) }
        func flow(_ store: ClubCommunityStoredPendingJournal) -> ClubCommunityCoordinator {
            .init(service: service, currentSession: { session }, refreshEvidence: { $0 }, journal: store, namespace: { "key-tests" }, outcomeQuery: ClubCommunityHTTPPendingOutcomeQuery(offlineBaseURL: base, transport: transport))
        }
        let original = flow(journal())
        let review = try await original.prepare(operation, evidence: evidence)
        do { try await original.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .unknown) }
        let record = try XCTUnwrap(original.pendingRecord(for: evidence))
        XCTAssertEqual(record.operationID, review.id)
        XCTAssertEqual(record.requestID, expected)
        XCTAssertNotEqual(record.requestID, review.id.uuidString)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual((sent["requestId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), expected)
        transport.echoWrongKey = wrongEcho
        let restarted = flow(journal())
        if wrongEcho {
            do { _ = try await restarted.reconcilePendingOperation(for: evidence); XCTFail() } catch { }
            XCTAssertNotNil(restarted.pendingRecord(for: evidence))
        } else {
            let result = try await restarted.reconcilePendingOperation(for: evidence)
            XCTAssertEqual(result, .acknowledgedRefreshRequired)
            XCTAssertNil(restarted.pendingRecord(for: evidence))
        }
        let read = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as? [String:Any])
        XCTAssertEqual(read["requestId"] as? String, expected)
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testEditPersistsActualKeyAndRestartQueriesThatKey() async throws {
        try await exercise(.update(content: "after", images: [], requestID: "edit-original-001"), expected: "edit-original-001")
    }
    func testPinPersistsActualKeyWithoutChangingWire() async throws {
        try await exercise(.pin(true, requestID: "pin-original-002"), expected: "pin-original-002")
    }
    func testOriginalServerNormalizationIsPreserved() async throws {
        try await exercise(.update(content: "after", images: [], requestID: "  edit-trimmed-003  "), expected: "edit-trimmed-003")
    }
    func testReceiptEchoingReviewUUIDCannotReleaseRealRequest() async throws {
        try await exercise(.update(content: "after", images: [], requestID: "edit-original-004"), expected: "edit-original-004", wrongEcho: true)
    }
    func testHistoricalNilEditAndPinKeysRemainUnknownWithoutQueryOrBackfill() async throws {
        for kind in ["edit", "pin"] {
            let transport = OriginalClubKeyTransport(), base = URL(string: "https://original-key.invalid")!
            let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token")
            let evidence = ClubCommunityEvidence(identity: session.identity, clubID: 10, joined: true, owner: true, administrator: false)
            let target = try ClubCommunityPendingTarget(evidence: evidence, namespace: "key-tests")
            let record = try ClubCommunityPendingRecord(target: target, operationID: UUID(), operationKind: kind, phase: .unknownLocked)
            let journal = ClubCommunityInMemoryPendingJournal()
            let sending = try ClubCommunityPendingRecord(target: target, operationID: record.operationID, operationKind: kind, phase: .sending)
            try journal.recordBeforeSend(sending); try journal.markUnknown(target: target, operationID: record.operationID)
            let flow = ClubCommunityCoordinator(service: .init(offlineBaseURL: base, transport: transport), currentSession: { session }, refreshEvidence: { $0 }, journal: journal, namespace: { "key-tests" }, outcomeQuery: ClubCommunityHTTPPendingOutcomeQuery(offlineBaseURL: base, transport: transport))
            do { _ = try await flow.reconcilePendingOperation(for: evidence); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .locked) }
            XCTAssertEqual(try journal.record(for: target), record)
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertEqual(flow.outcome, .unknownLocked)
        }
    }
}
