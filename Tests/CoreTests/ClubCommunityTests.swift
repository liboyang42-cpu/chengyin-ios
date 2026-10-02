import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CommunityFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = Data(#"{"code":200,"data":null}"#.utf8)
    var status = 200
    var fail = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if fail { throw URLError(.timedOut) }
        return (body, status)
    }
}
final class ClubCommunityTests: XCTestCase {
    private let identity = ClubReadIdentity(accountID: 5, epoch: 1)
    private func post(_ changes: [String: Any] = [:]) throws -> ClubCommunityPost {
        var value: [String: Any] = ["id": 20, "clubId": 10, "authorMemberId": 5, "content": "hello", "version": 2]
        value.merge(changes) { _, new in new }; return try .init(json: value)
    }
    private func evidence(post: ClubCommunityPost? = nil, comment: ClubCommunityComment? = nil, admin: Bool = false) -> ClubCommunityEvidence {
        .init(identity: identity, clubID: 10, joined: true, owner: false, administrator: admin, post: post, comment: comment)
    }
    func testWireContracts() throws {
        let item = try post(), e = evidence(post: try post())
        let create = try ClubCommunityReview(operation: .create(content: "", images: ["a", "b"]), evidence: evidence()).fields()
        XCTAssertEqual(create["images"] as? String, "a;b"); XCTAssertNil(create["requestId"])
        XCTAssertEqual(Set(create.keys), ["clubId", "content", "images"])
        let update = try ClubCommunityReview(operation: .update(content: "new", images: [], requestID: "same-key"), evidence: e).fields()
        XCTAssertEqual(update["images"] as? String, ""); XCTAssertEqual(update["version"] as? Int, item.version)
        XCTAssertEqual(Set(update.keys), ["id", "content", "images", "version", "requestId"])
        for operation: ClubCommunityOperation in [.delete, .toggleLike, .comment("hello")] {
            let fields = try ClubCommunityReview(operation: operation, evidence: e).fields()
            XCTAssertNil(fields["requestId"]); XCTAssertNil(fields["version"])
        }
        XCTAssertThrowsError(try ClubCommunityReview(operation: .create(content: "", images: ["a;b"]), evidence: evidence()))
    }
    func testModelsAndAuthority() throws {
        let item = try post(["images": " a ; ; b ", "isPinned": 1, "memberId": 999])
        XCTAssertEqual(item.images, ["a", "b"]); XCTAssertEqual(item.authorMemberID, 5); XCTAssertTrue(item.pinned)
        XCTAssertTrue(evidence(post: item).allows(.delete)); XCTAssertFalse(evidence(post: item).allows(.pin(true, requestID: "p")))
        let announcement = try post(["type": 2])
        XCTAssertFalse(evidence(post: announcement).allows(.update(content: "a", images: [], requestID: "a")))
        XCTAssertTrue(evidence(post: announcement, admin: true).allows(.pin(true, requestID: "a")))
        let comment = try ClubCommunityComment(json: ["id": 30, "postId": 20, "memberId": 6])
        XCTAssertTrue(evidence(post: item, comment: comment, admin: true).allows(.deleteComment))
        XCTAssertTrue(evidence(post: item, comment: comment).allows(.reportComment))
        let wrong = try ClubCommunityComment(json: ["id": 30, "postId": 99, "memberId": 5])
        XCTAssertFalse(evidence(post: item, comment: wrong).allows(.deleteComment))
    }
    func testReadRowsAndScope() async throws {
        let transport = CommunityFakeTransport()
        transport.body = Data(#"{"code":200,"data":{"rows":[{"id":20,"clubId":10,"content":"visible","images":"a;b"}]}}"#.utf8)
        let service = ClubCommunityService(baseURL: URL(string: "https://fixture.invalid")!, transport: transport)
        let guest = try ClubCommunitySession(identity: .init(accountID: nil, epoch: 0), token: nil)
        let result = try await service.read(.posts(clubID: 10, page: 1), session: guest, check: {})
        XCTAssertEqual(result.posts.count, 1); XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(transport.requests[0].url?.path, "/api/club/post/list")
        do { _ = try await service.read(.posts(clubID: 99, page: 1), session: guest, check: {}); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .stale) }
    }
    @MainActor func testDefaultOffAndUnknownNoBlindRetry() async throws {
        let transport = CommunityFakeTransport()
        let session = try ClubCommunitySession(identity: identity, token: "fixture")
        let ordinary = ClubCommunityService(baseURL: URL(string: "https://fixture.invalid")!, transport: transport)
        let review = try ClubCommunityReview(operation: .toggleLike, evidence: evidence(post: try post()))
        do { try await ordinary.submit(review, session: session, check: {}); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .unavailable) }
        XCTAssertTrue(transport.requests.isEmpty)
        let service = ClubCommunityService(dormantBaseURL: URL(string: "https://fixture.invalid")!, transport: transport, grant: .reviewedInjection)
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: { $0 })
        let approved = try await coordinator.prepare(.toggleLike, evidence: review.evidence)
        transport.fail = true
        do { try await coordinator.confirm(approved); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .unknown) }
        XCTAssertEqual(coordinator.outcome, .unknownLocked)
        XCTAssertTrue(coordinator.isLocked(review.evidence))
        do { _ = try await coordinator.prepare(.toggleLike, evidence: review.evidence); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .locked) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    @MainActor func testReportQueueAndDuplicateConfirm() async throws {
        let transport = CommunityFakeTransport()
        let service = ClubCommunityService(dormantBaseURL: URL(string: "https://fixture.invalid")!, transport: transport, grant: .reviewedInjection)
        let session = try ClubCommunitySession(identity: identity, token: "fixture")
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: { $0 })
        let review = try await coordinator.prepare(.report, evidence: evidence(post: try post(["authorMemberId": 6])))
        try await coordinator.confirm(review)
        XCTAssertEqual(coordinator.outcome, .moderationQueued)
        do { try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }
    @MainActor func testEpochChangeBlocksSend() async throws {
        let transport = CommunityFakeTransport()
        let service = ClubCommunityService(dormantBaseURL: URL(string: "https://fixture.invalid")!, transport: transport, grant: .reviewedInjection)
        var session = try ClubCommunitySession(identity: identity, token: "fixture")
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: { $0 })
        let review = try await coordinator.prepare(.delete, evidence: evidence(post: try post()))
        session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 2), token: "replacement")
        do { try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .stale) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    @MainActor func testChangedVersionInvalidatesReview() async throws {
        let transport = CommunityFakeTransport()
        let service = ClubCommunityService(dormantBaseURL: URL(string: "https://fixture.invalid")!, transport: transport, grant: .reviewedInjection)
        let session = try ClubCommunitySession(identity: identity, token: "fixture")
        let original = evidence(post: try post())
        let changed = evidence(post: try post(["version": 3, "content": "changed remotely"]))
        var reads = 0
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: { _ in
            reads += 1; return reads == 1 ? original : changed
        })
        let review = try await coordinator.prepare(.update(content: "my edit", images: [], requestID: "stable"), evidence: original)
        do { try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .stale) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    @MainActor func testMalformedAcknowledgmentLocks() async throws {
        let transport = CommunityFakeTransport()
        transport.body = Data("not-json".utf8)
        let service = ClubCommunityService(dormantBaseURL: URL(string: "https://fixture.invalid")!, transport: transport, grant: .reviewedInjection)
        let session = try ClubCommunitySession(identity: identity, token: "fixture")
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { session }, refreshEvidence: { $0 })
        let review = try await coordinator.prepare(.comment("exact reviewed text"), evidence: evidence(post: try post()))
        do { try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubCommunityFailure, .unknown) }
        XCTAssertTrue(coordinator.isLocked(review.evidence))
        let fields = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(Set(fields.keys), ["postId", "content"])
        XCTAssertEqual(fields["content"] as? String, "exact reviewed text")
        XCTAssertEqual(transport.requests[0].url?.path, "/api/club/post/comment/create")
    }
    func testPinCommentDeleteAndReportBodies() throws {
        let announcement = try post(["type": 2])
        let pin = try ClubCommunityReview(operation: .pin(true, requestID: "stable"), evidence: evidence(post: announcement, admin: true)).fields()
        XCTAssertEqual(Set(pin.keys), ["id", "pinned", "version", "requestId"])
        XCTAssertEqual(pin["pinned"] as? Bool, true)
        let comment = try ClubCommunityComment(json: ["id": 30, "postId": 20, "memberId": 6])
        let deletion = try ClubCommunityReview(operation: .deleteComment, evidence: evidence(post: announcement, comment: comment, admin: true)).fields()
        let report = try ClubCommunityReview(operation: .reportComment, evidence: evidence(post: announcement, comment: comment)).fields()
        XCTAssertEqual(Set(deletion.keys), ["id"]); XCTAssertEqual(deletion["id"] as? Int, 30)
        XCTAssertEqual(Set(report.keys), ["id"]); XCTAssertEqual(report["id"] as? Int, 30)
    }
    func testImageSeamOffAndSynthetic() async throws {
        XCTAssertFalse(ClubCommunityDisabledImages().enabled)
        do { _ = try await ClubCommunityDisabledImages().uploadSynthetic([Data([1])]); XCTFail() } catch {}
        let images = try await ClubCommunitySyntheticImages().uploadSynthetic([Data([1])])
        XCTAssertEqual(images.count, 1)
    }
}
