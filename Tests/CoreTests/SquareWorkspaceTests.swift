import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class SquareWorkspaceFakeHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String] = []
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return (Data(responses.removeFirst().utf8), 200)
    }
}
@MainActor final class SquareWorkspaceTests: XCTestCase {
    private let token = "synthetic-token"
    private func api(_ t: SquareWorkspaceFakeHTTP) throws -> SquareWorkspaceService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: t)
    }
    private func text(_ r: URLRequest) -> String { String(data: r.httpBody ?? Data(), encoding: .utf8) ?? "" }
    private func json(_ r: URLRequest) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: r.httpBody!) as? [String: Any]) }
    private func session(_ account: Int = 81, namespace: String = "fixture", epoch: UInt64 = 1) throws -> SquareWorkspaceSession { try .init(accountID: account, namespace: namespace, epoch: epoch) }
    func testLegacyCreatePreservesPicturesReferenceAndRequestID() throws {
        var draft = SquareWorkspaceFixtures.draft(); draft.media = [.init(objectKey: "one.jpg"), .init(objectKey: "two.jpg")]
        let r = try api(.init()).legacyRequest(draft: draft, token: token)
        XCTAssertEqual(r.url?.path, "/fixture/api/creativesquare/action")
        XCTAssertTrue(text(r).contains("one.jpg;two.jpg")); XCTAssertTrue(text(r).contains("request_id")); XCTAssertTrue(text(r).contains("data_id"))
        XCTAssertFalse(text(r).contains("latitude")); XCTAssertFalse(text(r).contains("longitude")); XCTAssertFalse(text(r).contains("communityId"))
    }
    func testLegacyEditOmitsMediaLocationAndRequestID() throws {
        var draft = SquareWorkspaceFixtures.draft(); draft.postID = 701; draft.media = [.init(objectKey: "one.jpg")]
        let body = text(try api(.init()).legacyRequest(draft: draft, token: token))
        for omitted in ["pics", "address", "request_id", "longitude", "latitude"] { XCTAssertFalse(body.contains("name=\"\(omitted)\"")) }
        XCTAssertTrue(body.contains("name=\"id\"")); XCTAssertTrue(body.contains("data_type"))
    }
    func testLegacyCannotSilentlyDropPrivateAudience() throws {
        var d = SquareWorkspaceFixtures.draft(); d.audience = "PRIVATE"
        XCTAssertThrowsError(try api(.init()).legacyRequest(draft: d, token: token))
    }
    func testUploadLanesUseSameEndpointButProofBizTypeOnlyForV1() throws {
        let service = try api(.init())
        let legacy = try service.uploadRequest(bytes: Data([1, 2, 3]), mimeType: "image/jpeg", communityProof: false, token: token)
        let v1 = try service.uploadRequest(bytes: Data([1, 2, 3]), mimeType: "image/jpeg", communityProof: true, token: token)
        XCTAssertEqual(v1.url?.path, "/fixture/api/common/uploadOSS"); XCTAssertTrue(text(v1).contains("COMMUNITY_POST")); XCTAssertFalse(text(legacy).contains("bizType"))
        XCTAssertTrue(text(v1).contains("name=\"file\"")); XCTAssertNil(v1.value(forHTTPHeaderField: "X-Idempotency-Key"))
    }
    func testMissingUploadProofNeverFabricated() async throws {
        let t = SquareWorkspaceFakeHTTP(); t.responses = [#"{"code":200,"url":"image.jpg"}"#]
        do { _ = try await api(t).upload(bytes: Data([1]), mimeType: "image/jpeg", communityProof: true, token: token); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .missingMediaProof) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testV1MediaRegistrationAndUpsertExactKeys() async throws {
        let t = SquareWorkspaceFakeHTTP(); t.responses = [#"{"code":200,"data":{"id":12}}"#, #"{"code":200,"data":{"id":701,"authorId":81,"version":3,"lifecycle":"DRAFT"}}"#]
        var d = SquareWorkspaceFixtures.draft(); d.media = [.init(objectKey: "image.jpg", byteSize: 33, mimeType: "image/jpeg", uploadReceipt: "synthetic-proof")]
        _ = try await api(t).upsert(draft: d, guidelineID: 4, publishing: false, token: token)
        XCTAssertEqual(t.requests.map { $0.url!.lastPathComponent }, ["register", "posts"])
        let media = try json(t.requests[0]); XCTAssertEqual(media["uploadRequestId"] as? String, "media-0-synthetic-square-001"); XCTAssertEqual(media["mediaType"] as? String, "IMAGE")
        let post = try json(t.requests[1]); XCTAssertEqual(post["mediaIds"] as? [Int], [12]); XCTAssertEqual(post["locationPrecision"] as? String, "CITY")
        XCTAssertNil(post["latitude"]); XCTAssertNil(post["longitude"]); XCTAssertEqual(post["clientRequestId"] as? String, "post-synthetic-square-001")
        XCTAssertFalse(t.requests.contains { $0.url!.path.contains("ack") || $0.url!.path.contains("publish") })
    }
    func testMissingMediaProofMakesNoRequest() async throws {
        let t = SquareWorkspaceFakeHTTP(); var d = SquareWorkspaceFixtures.draft(); d.media = [.init(objectKey: "image.jpg")]
        do { _ = try await api(t).upsert(draft: d, guidelineID: 4, publishing: true, token: token); XCTFail() } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testUnknownMediaRegistrationStopsBeforePost() async throws {
        let t = SquareWorkspaceFakeHTTP(); var d = SquareWorkspaceFixtures.draft(); d.media = [.init(objectKey: "image.jpg", byteSize: 4, mimeType: "image/jpeg", uploadReceipt: "fixture")]
        do { _ = try await api(t).upsert(draft: d, guidelineID: 4, publishing: true, token: token); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .unknown) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testReadContractsAndPagination() async throws {
        let t = SquareWorkspaceFakeHTTP(); t.responses = [#"{"code":200,"data":{"items":[],"nextCursor":null}}"#, #"{"code":200,"data":[]}"#, #"{"code":200,"data":[{"id":9,"name":"Example","city_code":"X"}]}"#]
        let service = try api(t); let page = try await service.drafts(cursor: 7, token: token)
        XCTAssertFalse(page.hasMore); _ = try await service.revisions(postID: 701, token: token)
        let options = try await service.options(type: "POI", token: token); XCTAssertEqual(options.first?.cityCode, "X")
        XCTAssertTrue(t.requests[0].url!.absoluteString.contains("cursor=7")); XCTAssertTrue(t.requests[0].url!.absoluteString.contains("limit=30"))
        XCTAssertEqual(t.requests[1].url?.path, "/fixture/api/v1/community/posts/701/revisions")
    }
    func testPrivateStorageAccountNamespaceIsolationAndSameAccountRestore() throws {
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage()); let a = try session()
        try store.save(.init(draft: SquareWorkspaceFixtures.draft(), lane: .legacy, pending: false, receipt: nil, updatedAt: Date()), session: a)
        XCTAssertEqual(try store.entries(session: session(epoch: 2)).count, 1)
        XCTAssertTrue(try store.entries(session: session(82)).isEmpty); XCTAssertTrue(try store.entries(session: session(namespace: "other")).isEmpty)
    }
    func testPendingDraftCannotBeDiscarded() throws {
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage()); let s = try session(); let draft = SquareWorkspaceFixtures.draft()
        try store.save(.init(draft: draft, lane: .legacy, pending: true, receipt: nil, updatedAt: Date()), session: s)
        XCTAssertThrowsError(try store.discard(workflowID: draft.id, session: s))
    }
    func testDefaultGatesPreventNetwork() async throws {
        let t = SquareWorkspaceFakeHTTP(); let s = try session()
        let c = SquareWorkspaceCoordinator(session: s, store: .init(storage: SquareWorkspaceMemoryStorage()), service: try api(t), currentSession: { s }, token: { "synthetic-token" })
        do { _ = try await c.prepare(SquareWorkspaceFixtures.draft(), lane: .legacy); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .disabled) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testEpochChangeBetweenStagesStopsNetwork() async throws {
        let t = SquareWorkspaceFakeHTTP(); var valid = true
        t.onSend = { valid = false }; t.responses = [#"{"code":200,"data":{"id":12}}"#]
        let service = try api(t).scoped { if !valid { throw SquareWorkspaceFailure.sessionChanged } }
        var d = SquareWorkspaceFixtures.draft(); d.media = [.init(objectKey: "image.jpg", byteSize: 4, mimeType: "image/jpeg", uploadReceipt: "fixture")]
        do { _ = try await service.upsert(draft: d, guidelineID: 4, publishing: true, token: token); XCTFail() } catch {}
        XCTAssertEqual(t.requests.count, 1)
    }
    func testUnknownLegacyPublishPersistsLockAcrossCoordinatorRecreation() async throws {
        let t = SquareWorkspaceFakeHTTP(); let s = try session(); let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        var grants = SquareWorkspaceGrants(); grants.live = true
        let c = SquareWorkspaceCoordinator(session: s, store: store, service: try api(t), grants: grants, currentSession: { s }, token: { "synthetic-token" })
        let draft = SquareWorkspaceFixtures.draft(); let review = try await c.prepare(draft, lane: .legacy)
        do { try await c.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: false); XCTFail() } catch {}
        let restored = SquareWorkspaceCoordinator(session: s, store: store, service: try api(t), grants: grants, currentSession: { s }, token: { "synthetic-token" })
        do { _ = try await restored.prepare(draft, lane: .legacy); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .pending) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testReferenceRemovalResetsCommunityPolicyButNotClubIDs() {
        var d = SquareWorkspaceFixtures.draft(); d.reference = .init(type: "CLUB", id: 99); XCTAssertNil(d.communityID)
        d.communityID = 12; d.audience = "COMMUNITY"; d.commentPolicy = "MEMBERS"; d.removeReference()
        XCTAssertNil(d.reference); XCTAssertNil(d.communityID); XCTAssertEqual(d.audience, "PUBLIC"); XCTAssertEqual(d.commentPolicy, "EVERYONE")
    }
    func testStaleGuidelineCancelsBeforeAnyMutation() async throws {
        let t = SquareWorkspaceFakeHTTP()
        t.responses = [#"{"code":200,"data":{"id":4,"body":"before"}}"#, #"{"code":200,"data":{"id":5,"body":"after"}}"#]
        let session = try session(); var grants = SquareWorkspaceGrants(); grants.live = true; grants.legal = true
        let c = SquareWorkspaceCoordinator(session: session, store: .init(storage: SquareWorkspaceMemoryStorage()), service: try api(t), grants: grants, currentSession: { session }, token: { "synthetic-token" })
        let draft = SquareWorkspaceFixtures.draft(); let review = try await c.prepare(draft, lane: .communityV1)
        do { try await c.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: true); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .staleReview) }
        XCTAssertEqual(t.requests.count, 2); XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testV1PublishUsesAckUpsertPublishThenFreshReadback() async throws {
        let t = SquareWorkspaceFakeHTTP()
        let guideline = #"{"code":200,"data":{"id":4,"body":"fixture"}}"#
        let draftPost = #"{"code":200,"data":{"id":701,"authorId":81,"version":3,"lifecycle":"DRAFT"}}"#
        let pendingPost = #"{"code":200,"data":{"id":701,"authorId":81,"version":4,"lifecycle":"PENDING"}}"#
        t.responses = [guideline, guideline, #"{"code":200}"#, draftPost, pendingPost, pendingPost]
        let session = try session(); var grants = SquareWorkspaceGrants(); grants.live = true; grants.legal = true
        let c = SquareWorkspaceCoordinator(session: session, store: .init(storage: SquareWorkspaceMemoryStorage()), service: try api(t), grants: grants, currentSession: { session }, token: { "synthetic-token" })
        let draft = SquareWorkspaceFixtures.draft(); let review = try await c.prepare(draft, lane: .communityV1)
        try await c.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: true)
        XCTAssertEqual(t.requests.map { $0.url!.lastPathComponent }, ["active", "active", "ack", "posts", "publish", "info"])
        XCTAssertEqual(c.lastPost?.lifecycle, "PENDING")
        XCTAssertEqual(try json(t.requests[2])["scene"] as? String, "PUBLISH")
        XCTAssertEqual(try json(t.requests[4])["expectedVersion"] as? Int, 3)
        do { try await c.confirm(review, unchangedDraft: draft, acceptCurrentGuideline: true); XCTFail() } catch {}
        XCTAssertEqual(t.requests.count, 6)
    }
    func testPublishedRevisionOnlySavesLocallyEvenWithNoLiveGrant() async throws {
        let s = try session(); let t = SquareWorkspaceFakeHTTP()
        let c = SquareWorkspaceCoordinator(session: s, store: .init(storage: SquareWorkspaceMemoryStorage()), service: try api(t), currentSession: { s })
        var draft = SquareWorkspaceFixtures.draft(); draft.postID = 701; draft.sourceLifecycle = "PUBLISHED"
        try await c.saveServer(draft); XCTAssertTrue(t.requests.isEmpty); XCTAssertEqual(c.local.first?.draft, draft)
    }

}
