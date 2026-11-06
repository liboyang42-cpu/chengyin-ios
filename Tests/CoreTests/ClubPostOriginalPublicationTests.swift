import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OriginalPublicationTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var fact: [String:Any]?
    var loseWriteResponse=false
    var mutateReceipt: ((inout [String:Any]) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        requests.append(request)
        var body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        if request.url?.lastPathComponent != "receipt" {
            body.removeValue(forKey:"content");body.removeValue(forKey:"images")
            body["status"]="ACKNOWLEDGED";body["sourceSHA256"]=String(repeating:"a",count:64)
            body["resultPostId"]=(body["operationKind"] as? String)=="create" ? 20 : body["postId"]
            body["resultVersion"]=(body["version"] as? Int ?? 0)+1
            fact=body
            if loseWriteResponse { throw URLError(.timedOut) }
        }
        var returned=fact ?? body;mutateReceipt?(&returned)
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":returned]),200)
    }
}
@MainActor final class ClubPostOriginalPublicationTests: XCTestCase {
    private func run(_ operation: ClubCommunityOperation, post: ClubCommunityPost?=nil, loseResponse: Bool=false) async throws {
        let transport=OriginalPublicationTransport(),base=URL(string:"https://original-publication.invalid")!
        transport.loseWriteResponse=loseResponse
        let session=try ClubCommunitySession(identity:.init(accountID:5,epoch:1),token:"synthetic-token")
        let evidence=ClubCommunityEvidence(identity:session.identity,clubID:10,joined:true,owner:true,administrator:false,post:post)
        let journal=ClubCommunityInMemoryPendingJournal()
        let original=ClubPostOriginalService(baseURL:base,transport:transport,readsEnabled:true,writesEnabled:true)
        func flow()->ClubCommunityCoordinator {
            .init(service:.init(baseURL:base,transport:transport),currentSession:{session},refreshEvidence:{$0},journal:journal,namespace:{"tests"},originalPublication:original)
        }
        let first=flow(),review=try await first.prepare(operation,evidence:evidence)
        if loseResponse {
            do {try await first.confirm(review);XCTFail()} catch {XCTAssertEqual(error as? ClubCommunityFailure,.unknown)}
            let record=try XCTUnwrap(first.pendingRecord(for:evidence))
            XCTAssertEqual(record.receiptNamespace,"club-post-v1");XCTAssertEqual(record.operationID,review.id)
            let restarted=flow()
            let result=try await restarted.reconcilePendingOperation(for:evidence)
            XCTAssertEqual(result,.acknowledgedRefreshRequired);XCTAssertNil(restarted.pendingRecord(for:evidence))
            XCTAssertEqual(transport.requests.last?.url?.path,"/api/club/post/operation/receipt")
        } else {
            try await first.confirm(review);XCTAssertEqual(first.outcome,.acknowledgedRefreshRequired)
        }
        let request=try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path,post == nil ? "/api/club/post/operation/create" : "/api/club/post/operation/update")
        let body=try XCTUnwrap(JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
        XCTAssertEqual(body["receiptNamespace"] as? String,"club-post-v1")
        XCTAssertEqual(body["operationId"] as? String,review.id.uuidString)
        XCTAssertEqual(body["version"] as? Int,post?.version ?? 0)
        XCTAssertEqual(transport.requests.filter{$0.url?.lastPathComponent != "receipt"}.count,1)
    }
    func testCreateUsesOriginalRouteAndStrictReceipt() async throws {
        try await run(.create(content:"draft",images:[]))
    }
    func testEditPreservesOriginalRequestKeyAndVersion() async throws {
        let post=try ClubCommunityPost(json:["id":20,"clubId":10,"authorMemberId":5,"version":2,"content":"before"])
        try await run(.update(content:"after",images:[],requestID:"edit-original"),post:post)
    }
    func testUnknownCreateRestartsIntoReadOnlyOriginalRecovery() async throws {
        try await run(.create(content:"draft",images:[]),loseResponse:true)
    }
    func testDefaultsAndPinCannotUseOriginalWriter() async throws {
        let t=OriginalPublicationTransport(),base=URL(string:"https://original-publication.invalid")!
        let api=ClubPostOriginalService(baseURL:base,transport:t)
        XCTAssertFalse(api.allowsWrites);XCTAssertFalse(api.allowsAuthoritativeQueries)
        let session=try ClubCommunitySession(identity:.init(accountID:5,epoch:1),token:"synthetic-token")
        let post=try ClubCommunityPost(json:["id":20,"clubId":10,"authorMemberId":5,"version":2,"type":2,"content":"before"])
        let evidence=ClubCommunityEvidence(identity:session.identity,clubID:10,joined:true,owner:true,administrator:false,post:post)
        let flow=ClubCommunityCoordinator(service:.init(baseURL:base,transport:t),currentSession:{session},refreshEvidence:{$0},originalPublication:.init(baseURL:base,transport:t,readsEnabled:true,writesEnabled:true))
        do {_ = try await flow.prepare(.pin(true,requestID:"pin-key"),evidence:evidence);XCTFail()}catch{XCTAssertEqual(error as? ClubCommunityFailure,.unavailable)}
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testMalformedOrWrongIdentityReceiptCannotSettle() throws {
        let evidence=ClubCommunityEvidence(identity:.init(accountID:5,epoch:1),clubID:10,joined:true,owner:true,administrator:false)
        let record=try ClubCommunityPendingRecord(target:.init(evidence:evidence),operationID:UUID(),operationKind:"create",phase:.unknownLocked,requestID:"key",postVersion:0,receiptNamespace:"club-post-v1")
        let identity=try ClubPostOriginalIdentity(record)
        var fact=identity.fields;fact["status"]="ACKNOWLEDGED";fact["sourceSHA256"]=String(repeating:"a",count:64);fact["resultPostId"]=20;fact["resultVersion"]=0
        _ = try identity.result(fact)
        for key in ["receiptNamespace","operationId","requestId","operationKind","clubId","postId","commentId","version","sourceSHA256","resultPostId","resultVersion"] {
            var wrong=fact;wrong[key]="mismatch";XCTAssertThrowsError(try identity.result(wrong),key)
        }
        var privateBody=fact;privateBody["content"]="not permitted";XCTAssertThrowsError(try identity.result(privateBody))
    }
    func testMissingNamespaceCannotBeUpgradedIntoOriginalFact() throws {
        let evidence=ClubCommunityEvidence(identity:.init(accountID:5,epoch:1),clubID:10,joined:true,owner:true,administrator:false)
        let record=try ClubCommunityPendingRecord(target:.init(evidence:evidence),operationID:UUID(),operationKind:"create",phase:.unknownLocked,requestID:"key",postVersion:0)
        XCTAssertThrowsError(try ClubPostOriginalIdentity(record))
    }
}
