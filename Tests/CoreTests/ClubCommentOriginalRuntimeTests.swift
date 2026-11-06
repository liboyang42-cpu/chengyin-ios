import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CommentRuntimeSpy: HTTPTransport {
    var calls = 0
    var onSend: () -> Void = {}
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; onSend(); return (Data(), 200)
    }
}
@MainActor final class ClubCommentOriginalRuntimeTests: XCTestCase {
    private func context(_ account: Int = 7) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://runtime.invalid/prefix")!, role: "player",
              session: try .init(accountID: account, epoch: 1, namespace: "test", token: "synthetic-token", role: "player"))
    }
    private func request(_ context: RuntimeDependencyContext, suffix: String = "receipt", club: Int = 3) throws -> URLRequest {
        var fields: [String: Any] = ["receiptNamespace":"club-post-v1", "operationId": UUID().uuidString,
            "requestId":"original-key", "operationKind":"comment", "clubId":club, "postId":20, "commentId":0, "version":0]
        if suffix == "create" { fields["content"] = "draft" }
        var r = URLRequest(url: context.baseURL.appendingPathComponent("api/club/post/operation/comment/" + suffix))
        r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]); return r
    }
    func testExactFamilyRejectsPinWrongOperationAndExtraFields() throws {
        let c = try context(); let good = try request(c)
        XCTAssertNotNil(ClubCommentOriginalRoute(request: good, baseURL: c.baseURL))
        var pin = good; pin.url = c.baseURL.appendingPathComponent("api/club/post/pin")
        XCTAssertNil(ClubCommentOriginalRoute(request: pin, baseURL: c.baseURL))
        var wrong = good; var fields = try JSONSerialization.jsonObject(with: good.httpBody!) as! [String:Any]
        fields["operationKind"] = "pin"; wrong.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        XCTAssertNil(ClubCommentOriginalRoute(request: wrong, baseURL: c.baseURL))
        fields["operationKind"] = "comment"; fields["content"] = "private"
        wrong.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        XCTAssertNil(ClubCommentOriginalRoute(request: wrong, baseURL: c.baseURL))
    }
    func testPublicationAndReplyCannotUseCommentLeaseDespiteSharedNamespace() throws {
        let c = try context(); var root = try request(c, suffix: "create")
        XCTAssertNotNil(ClubCommentOriginalRoute(request: root, baseURL: c.baseURL))
        XCTAssertNil(ClubPostOriginalRoute(request: root, baseURL: c.baseURL))
        root.url = c.baseURL.appendingPathComponent("api/club/post/operation/create")
        XCTAssertNil(ClubCommentOriginalRoute(request: root, baseURL: c.baseURL))
        root = try request(c, suffix: "create")
        var fields = try JSONSerialization.jsonObject(with: root.httpBody!) as! [String:Any]
        fields["operationKind"] = "reply"; fields["commentId"] = 30
        root.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        XCTAssertNil(ClubCommentOriginalRoute(request: root, baseURL: c.baseURL))
    }
    func testReadLeaseCannotWriteOrReadOtherClub() async throws {
        let c = try context(), spy = CommentRuntimeSpy()
        let a = try ClubCommentOriginalApproval(context: c, clubID: 3, expiresAt: Date().addingTimeInterval(60))
        let t = ClubCommentOriginalRuntimeTransport(transport: spy, captured: c, approval: a, current: { c }, select: { _ in a })
        _ = try await t.send(request(c)); XCTAssertEqual(spy.calls, 1)
        for r in [try request(c, suffix: "create"), try request(c, club: 4)] {
            do { _ = try await t.send(r); XCTFail("ungranted route") } catch {}
        }
        XCTAssertEqual(spy.calls, 1)
    }
    func testRevocationAndReplacementRejectBeforeDispatch() async throws {
        let c = try context(), spy = CommentRuntimeSpy()
        let a = try ClubCommentOriginalApproval(context: c, clubID: 3, expiresAt: Date().addingTimeInterval(60))
        var issued: ClubCommentOriginalApproval? = nil
        let t = ClubCommentOriginalRuntimeTransport(transport: spy, captured: c, approval: a, current: { c }, select: { _ in issued })
        do { _ = try await t.send(request(c)); XCTFail() } catch {}
        issued = a; a.revoke()
        do { _ = try await t.send(request(c)); XCTFail() } catch {}
        XCTAssertEqual(spy.calls, 0)
    }
    func testAccountChangeAndRevocationAfterDispatchRejectReturn() async throws {
        let c = try context(), other = try context(8)
        for changeAccount in [false, true] {
            let spy = CommentRuntimeSpy()
            var live = c
            let a = try ClubCommentOriginalApproval(context: c, clubID: 3, expiresAt: Date().addingTimeInterval(60), writes: true)
            spy.onSend = { if changeAccount { live = other } else { a.revoke() } }
            let t = ClubCommentOriginalRuntimeTransport(transport: spy, captured: c, approval: a, current: { live }, select: { _ in a })
            do { _ = try await t.send(request(c, suffix: "create")); XCTFail() } catch {}
            XCTAssertEqual(spy.calls, 1)
        }
    }
    func testExpiryBoundaryIsClosed() throws {
        let c = try context(), expiry = Date().addingTimeInterval(60)
        let a = try ClubCommentOriginalApproval(context: c, clubID: 3, expiresAt: expiry)
        XCTAssertTrue(a.matches(c, now: expiry.addingTimeInterval(-0.001)))
        XCTAssertFalse(a.matches(c, now: expiry))
    }
    func testDynamicProviderRevokedBetweenReviewAndConfirmDoesNotClaimJournal() async throws {
        let c = try context(), spy = CommentRuntimeSpy()
        let session = try ClubCommunitySession(identity: .init(accountID: 7, epoch: 1), token: c.session.token)
        let e = ClubCommunityEvidence(identity: session.identity, clubID: 3, joined: true, owner: true, administrator: false,
            post: try .init(json: ["id":20,"clubId":3,"authorMemberId":7,"version":0,"content":"source"]))
        var provider: ClubCommentOriginalService? = .init(baseURL: c.baseURL, transport: spy, readsEnabled: true, writesEnabled: true)
        let journal = ClubCommunityInMemoryPendingJournal()
        let coordinator = ClubCommunityCoordinator(service: .init(baseURL: c.baseURL, transport: spy), currentSession: { session },
            refreshEvidence: { $0 }, journal: journal, originalCommentResolver: { provider })
        let review = try await coordinator.prepare(.comment("draft"), evidence: e)
        provider = nil
        do { try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertNil(coordinator.pendingRecord(for: e)); XCTAssertEqual(spy.calls, 0)
    }
    func testRevokedDispatchedPublicationPreservesUnknownOriginalJournal() async throws {
        let c = try context(), spy = CommentRuntimeSpy()
        let session = try ClubCommunitySession(identity: .init(accountID: 7, epoch: 1), token: c.session.token)
        let evidence = ClubCommunityEvidence(identity: session.identity, clubID: 3, joined: true, owner: true, administrator: false,
            post: try .init(json: ["id":20,"clubId":3,"authorMemberId":7,"version":0,"content":"source"]))
        let approval = try ClubCommentOriginalApproval(context: c, clubID: 3, expiresAt: Date().addingTimeInterval(60), writes: true)
        spy.onSend = { approval.revoke() }
        let runtime = ClubCommentOriginalRuntimeTransport(transport: spy, captured: c, approval: approval, current: { c }, select: { _ in approval })
        let provider = ClubCommentOriginalService(baseURL: c.baseURL, transport: runtime, readsEnabled: true, writesEnabled: true)
        let journal = ClubCommunityInMemoryPendingJournal()
        let coordinator = ClubCommunityCoordinator(service: .init(baseURL: c.baseURL, transport: spy), currentSession: { session },
            refreshEvidence: { $0 }, journal: journal, originalCommentResolver: { provider })
        let review = try await coordinator.prepare(.comment("draft"), evidence: evidence)
        do { try await coordinator.confirm(review); XCTFail() } catch {
            XCTAssertEqual(error as? ClubCommunityFailure, .unknown)
        }
        let pending = try XCTUnwrap(coordinator.pendingRecord(for: evidence))
        XCTAssertEqual(pending.receiptNamespace, "club-post-v1"); XCTAssertEqual(pending.operationID, review.id)
        XCTAssertEqual(coordinator.outcome, .unknownLocked); XCTAssertEqual(spy.calls, 1)
    }

}
