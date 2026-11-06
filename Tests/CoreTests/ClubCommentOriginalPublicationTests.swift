import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RootCommentTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var fact: [String:Any]?
    var loseResponse = false
    var onSend: () -> Void = {}
    var alter: ((inout [String:Any]) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        var raw = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
        if request.url?.lastPathComponent == "create" {
            raw.removeValue(forKey: "content"); raw["status"] = "ACKNOWLEDGED"
            raw["sourceSHA256"] = String(repeating: "a", count: 64)
            raw["resultPostId"] = raw["postId"]; raw["resultVersion"] = raw["version"]; raw["resultCommentId"] = 30
            fact = raw; onSend()
            if loseResponse { throw URLError(.timedOut) }
        }
        var result = fact ?? raw
        alter?(&result)
        return (try JSONSerialization.data(withJSONObject: ["code":200, "data":result]), 200)
    }
}
@MainActor final class ClubCommentOriginalPublicationTests: XCTestCase {
    private let base = URL(string: "https://root-comment.invalid")!
    private func session() throws -> ClubCommunitySession { try .init(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token") }
    private func evidence(_ session: ClubCommunitySession) throws -> ClubCommunityEvidence {
        .init(identity: session.identity, clubID: 10, joined: true, owner: false, administrator: false,
              post: try .init(json: ["id":20,"clubId":10,"authorMemberId":7,"version":2,"content":"source"]))
    }
    private func flow(_ transport: RootCommentTransport, _ session: ClubCommunitySession,
                      _ journal: ClubCommunityInMemoryPendingJournal, reads: Bool = true, writes: Bool = true) -> ClubCommunityCoordinator {
        .init(service: .init(baseURL: base, transport: transport), currentSession: {session}, refreshEvidence: {$0},
              journal: journal, namespace: {"root-tests"},
              originalComment: .init(baseURL: base, transport: transport, readsEnabled: reads, writesEnabled: writes))
    }
    func testRootCommentUsesExistingIndependentProtocolAndExactRequest() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        let c = flow(t,s,j), review = try await c.prepare(.comment("root comment"), evidence: e)
        try await c.confirm(review)
        XCTAssertEqual(c.outcome, .acknowledgedRefreshRequired); XCTAssertNil(c.pendingRecord(for:e))
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/api/club/post/operation/comment/create")
        let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        XCTAssertEqual(body["operationKind"] as? String,"comment"); XCTAssertEqual(body["commentId"] as? Int,0)
        XCTAssertEqual(body["requestId"] as? String,review.id.uuidString); XCTAssertEqual(body["version"] as? Int,2)
        XCTAssertEqual(body["receiptNamespace"] as? String,"club-post-v1"); XCTAssertNil(body["images"])
    }
    func testLostResponseRestartsIntoReadOnlyOriginalRecoveryWithoutResend() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        t.loseResponse = true
        let first = flow(t,s,j), review = try await first.prepare(.comment("root comment"), evidence:e)
        do { try await first.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure,.unknown) }
        let restarted = flow(t,s,j,writes:false)
        let outcome = try await restarted.reconcilePendingOperation(for:e)
        XCTAssertEqual(outcome,.acknowledgedRefreshRequired); XCTAssertNil(restarted.pendingRecord(for:e))
        XCTAssertEqual(t.requests.map { $0.url!.lastPathComponent },["create","receipt"])
        XCTAssertEqual(t.requests.last?.url?.path,"/api/club/post/operation/comment/receipt")
    }
    func testMissingOrMismatchedReceiptKeepsOriginalLock() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        t.loseResponse = true
        let first = flow(t,s,j), review = try await first.prepare(.comment("root comment"),evidence:e)
        do { try await first.confirm(review) } catch {}
        t.alter = { $0["resultPostId"] = 99 }
        let restarted = flow(t,s,j,writes:false)
        do { _ = try await restarted.reconcilePendingOperation(for:e); XCTFail() } catch {}
        XCTAssertEqual(restarted.pendingRecord(for:e)?.operationID,review.id)
        XCTAssertEqual(t.requests.filter{$0.url?.lastPathComponent == "create"}.count,1)
    }
    func testRootGrantDoesNotEnablePinOrCreatePublication() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        let c = flow(t,s,j)
        let operations: [ClubCommunityOperation] = [.pin(true,requestID:"pin-key"), .create(content:"post",images:[])]
        for operation in operations {
            do { _ = try await c.prepare(operation,evidence:e); XCTFail() } catch {}
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testInvalidOriginalTextDoesNotClaimJournalOrDispatch() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        let c = flow(t,s,j)
        do { _ = try await c.prepare(.comment(" trimmed differently "),evidence:e); XCTFail() } catch {}
        XCTAssertNil(c.pendingRecord(for:e)); XCTAssertTrue(t.requests.isEmpty)
    }
    func testDispatchedCancellationPreservesUnknownOriginal() async throws {
        let t = RootCommentTransport(), s = try session(), e = try evidence(s), j = ClubCommunityInMemoryPendingJournal()
        t.onSend = { withUnsafeCurrentTask { $0?.cancel() } }
        let c = flow(t,s,j), review = try await c.prepare(.comment("root comment"),evidence:e)
        let task = Task { do { try await c.confirm(review); XCTFail() } catch {} }; await task.value
        XCTAssertEqual(c.outcome,.unknownLocked); XCTAssertEqual(c.pendingRecord(for:e)?.operationID,review.id)
        XCTAssertEqual(t.requests.count,1)
    }
}
