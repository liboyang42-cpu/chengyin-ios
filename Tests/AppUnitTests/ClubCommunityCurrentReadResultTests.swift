import Foundation
import XCTest
@testable import Questify

@MainActor private final class CurrentCommentResultTransport: HTTPTransport {
    enum ReadResult { case success, forbidden, offline }
    var readResult: ReadResult = .success
    var requests: [URLRequest] = []
    var originalPending = false
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        requests.append(request)
        if request.url!.path.contains("/operation/comment/") {
            var fact = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
            fact.removeValue(forKey:"content")
            fact["status"] = originalPending ? "PENDING" : "ACKNOWLEDGED"
            if !originalPending {
                fact["sourceSHA256"] = String(repeating:"b",count:64)
                fact["resultPostId"] = fact["postId"]; fact["resultVersion"] = fact["version"]; fact["resultCommentId"] = 30
            }
            return (try JSONSerialization.data(withJSONObject:["code":200,"data":fact]),200)
        }
        switch readResult {
        case .success: return (Data(#"{"code":200,"data":[{"id":30,"postId":20,"memberId":5,"content":"current comment"}]}"#.utf8),200)
        case .forbidden: return (Data(#"{"code":403,"msg":"current content denied"}"#.utf8),403)
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }
}
@MainActor private final class CurrentCommentResultHarness {
    let transport = CurrentCommentResultTransport()
    let journal = ClubCommunityInMemoryPendingJournal()
    let session: ClubCommunitySession
    let post: ClubCommunityPost
    let target: ClubCommunityPendingTarget
    let original: ClubCommunityPendingRecord
    let coordinator: ClubCommunityCoordinator
    let model: ClubCommunityViewModel
    init(pending: Bool = true) throws {
        let session = try ClubCommunitySession(identity:.init(accountID:5,epoch:1),token:"synthetic-token")
        self.session = session
        post = try .init(json:["id":20,"clubId":10,"authorMemberId":7,"version":2,"content":"post"])
        target = try .init(namespace:"read-result-tests",accountID:5,clubID:10,postID:20)
        original = try .init(target:target,operationID:UUID(),operationKind:"comment",phase:.sending,
                             requestID:"original-root-key",postVersion:2,receiptNamespace:"club-post-v1")
        if pending {
            try journal.recordBeforeSend(original)
            try journal.markUnknown(target:target,operationID:original.operationID)
        }
        let service = ClubCommunityService(baseURL:URL(string:"https://read-result.invalid")!,transport:transport)
        let provider = ClubCommentOriginalService(baseURL:URL(string:"https://read-result.invalid")!,transport:transport,readsEnabled:true,writesEnabled:true)
        coordinator = ClubCommunityCoordinator(service:service,currentSession:{session},refreshEvidence:{$0},journal:journal,
            namespace:{"read-result-tests"},originalComment:provider)
        model = ClubCommunityViewModel(context:.init(service:service,currentSession:{session},coordinator:coordinator,
            evidence:{ club,post,comment in .init(identity:session.identity,clubID:club,joined:true,owner:false,administrator:false,post:post,comment:comment) }))
    }
    func recover() async { await model.reconcilePending(clubID:10,post:post,refresh:.comments(postID:20,page:1)) }
}
@MainActor final class ClubCommunityCurrentReadResultTests: XCTestCase {
    func testOriginalAcknowledgedButCurrent403ClearsContentAndPreservesReadError() async throws {
        let h = try CurrentCommentResultHarness()
        await h.model.load(.comments(postID:20,page:1)); XCTAssertNotNil(h.model.snapshot)
        h.transport.readResult = .forbidden
        await h.recover()
        XCTAssertNil(h.model.snapshot); XCTAssertEqual(h.model.notice,"club.community.loadError")
        XCTAssertNil(try h.journal.record(for:h.target)); XCTAssertEqual(h.coordinator.outcome,.acknowledgedRefreshRequired)
        XCTAssertEqual(h.transport.requests.filter{$0.url?.path.contains("/operation/comment/create") == true}.count,0)
    }
    func testOriginalAcknowledgedButOfflineCurrentReadDoesNotClaimRefreshedContent() async throws {
        let h = try CurrentCommentResultHarness(); h.transport.readResult = .offline
        await h.recover()
        XCTAssertNil(h.model.snapshot); XCTAssertEqual(h.model.notice,"club.community.loadError")
        XCTAssertNil(try h.journal.record(for:h.target)); XCTAssertEqual(h.coordinator.outcome,.acknowledgedRefreshRequired)
    }
    func testSuccessfulCurrentReadStillShowsOriginalReceivedNotice() async throws {
        let h = try CurrentCommentResultHarness(); await h.recover()
        XCTAssertEqual(h.model.snapshot?.comments.first?.id,30)
        XCTAssertEqual(h.model.notice,"club.community.refreshRequired"); XCTAssertNil(try h.journal.record(for:h.target))
    }
    func testPendingOriginalDoesNotReadCurrentContentOrReleaseLock() async throws {
        let h = try CurrentCommentResultHarness(); h.transport.originalPending = true
        await h.recover()
        XCTAssertEqual(h.model.notice,"club.community.unknown"); XCTAssertNotNil(try h.journal.record(for:h.target))
        XCTAssertEqual(h.transport.requests.count,1); XCTAssertNil(h.model.snapshot)
    }
    func testConfirmedRootWriteIsNotTurnedUnknownWhenCurrentReadFails() async throws {
        let h = try CurrentCommentResultHarness(pending:false); h.transport.readResult = .forbidden
        await h.model.prepare(.comment("root comment"),clubID:10,post:h.post)
        let review = try XCTUnwrap(h.model.review)
        let handled = await h.model.confirm(expected:review,refresh:.comments(postID:20,page:1))
        XCTAssertTrue(handled); XCTAssertNil(h.model.snapshot); XCTAssertEqual(h.model.notice,"club.community.loadError")
        XCTAssertEqual(h.coordinator.outcome,.acknowledgedRefreshRequired); XCTAssertNil(try h.journal.record(for:h.target))
        XCTAssertEqual(h.transport.requests.filter{$0.url?.lastPathComponent == "create"}.count,1)
    }
}
