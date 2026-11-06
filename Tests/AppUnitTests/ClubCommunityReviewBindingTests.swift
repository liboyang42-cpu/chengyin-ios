import Foundation
import XCTest
@testable import Questify

@MainActor private final class ReviewBoundClubTransport: ClubCommunityOfflineTransport {
    var requests: [URLRequest] = []
    var afterWrite: (() throws -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "create" { try afterWrite?() }
        return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
    }
}
@MainActor private final class ReviewBoundClubHarness {
    var session: ClubCommunitySession
    let transport = ReviewBoundClubTransport()
    let journal = ClubCommunityInMemoryPendingJournal()
    var model: ClubCommunityViewModel!
    init() throws {
        session = try .init(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token")
        let service = ClubCommunityService(offlineBaseURL: URL(string: "https://review-bound.invalid")!, transport: transport)
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { [unowned self] in self.session }, refreshEvidence: { $0 }, journal: journal)
        model = ClubCommunityViewModel(context: .init(service: service, currentSession: { [unowned self] in self.session }, coordinator: coordinator, evidence: { [unowned self] club, post, comment in
            .init(identity: self.session.identity, clubID: club, joined: true, owner: false, administrator: false, post: post, comment: comment)
        }))
    }
    func prepare(_ text: String) async throws -> ClubCommunityReview {
        await model.prepare(.create(content: text, images: []), clubID: 10)
        return try XCTUnwrap(model.review)
    }
}
@MainActor final class ClubCommunityReviewBindingTests: XCTestCase {
    func testOldVisibleReviewCannotConfirmReplacementTextOrDismissItsReview() async throws {
        let h = try ReviewBoundClubHarness()
        let old = try await h.prepare("Original reviewed text")
        let fresh = try await h.prepare("Replacement text")
        let shouldDismiss = await h.model.confirm(expected: old, refresh: .posts(clubID: 10, page: 1))
        XCTAssertFalse(shouldDismiss); XCTAssertEqual(h.model.review, fresh)
        XCTAssertTrue(h.transport.requests.isEmpty)
        let accepted = await h.model.confirm(expected: fresh, refresh: .posts(clubID: 10, page: 1))
        XCTAssertTrue(accepted)
        let write = try XCTUnwrap(h.transport.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(write.httpBody)) as? [String: Any])
        XCTAssertEqual(body["content"] as? String, "Replacement text")
        XCTAssertEqual(h.transport.requests.count, 2)
    }
    func testInvalidatedReviewCannotSendOrDismissNewVisit() async throws {
        let h = try ReviewBoundClubHarness(), review = try await h.prepare("Reviewed")
        h.model.invalidate(); h.model.notice = "new-visit"
        let accepted = await h.model.confirm(expected: review, refresh: .posts(clubID: 10, page: 1))
        XCTAssertFalse(accepted); XCTAssertTrue(h.transport.requests.isEmpty)
        XCTAssertEqual(h.model.notice, "new-visit")
    }
    func testChangedAccountCannotConfirmEvenIfOldReviewRemainsInMemory() async throws {
        let h = try ReviewBoundClubHarness(), review = try await h.prepare("Reviewed")
        h.session = try .init(identity: .init(accountID: 8, epoch: 2), token: "other-token")
        let accepted = await h.model.confirm(expected: review, refresh: .posts(clubID: 10, page: 1))
        XCTAssertFalse(accepted); XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testRetiredVisitAfterDispatchCannotRefreshOrDismissNewPresentation() async throws {
        let h = try ReviewBoundClubHarness(), review = try await h.prepare("Reviewed")
        h.transport.afterWrite = { [unowned h] in h.model.invalidate(); h.model.notice = "new-visit" }
        let accepted = await h.model.confirm(expected: review, refresh: .posts(clubID: 10, page: 1))
        XCTAssertFalse(accepted); XCTAssertEqual(h.model.notice, "new-visit")
        XCTAssertEqual(h.transport.requests.count, 1); XCTAssertFalse(h.model.busy)
        // The core still owns the exact acknowledged/unknown original; UI does not rewrite it.
    }
}
