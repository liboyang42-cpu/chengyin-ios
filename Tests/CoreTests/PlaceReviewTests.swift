import XCTest
@testable import QuestifyCore

// Fail-closed client contract tests with in-memory fakes. NOT the real W14.5 loop: no backend route exists.
@MainActor private final class FakePlaceReviews: PlaceReviewReading, PlaceReviewWriting {
    var isConfigured = true
    var pages: [Int: PlaceReviewPage] = [:]
    var submitOutcome: Result<PlaceReviewReceipt, PlaceReviewFailure> = .success(.init(reviewID: 5, status: .pending))
    var requestIDs: [String] = []
    func page(_ target: PlaceReviewTarget, page: Int) async throws -> PlaceReviewPage {
        guard let p = pages[page] else { throw PlaceReviewFailure.unknown }
        return p
    }
    func submit(_ draft: PlaceReviewDraft, target: PlaceReviewTarget, requestID: String) async throws -> PlaceReviewReceipt {
        requestIDs.append(requestID); return try submitOutcome.get()
    }
}
@MainActor final class PlaceReviewTests: XCTestCase {
    private let target = PlaceReviewTarget(placeID: 12)!
    private func item(_ id: Int, pub: Bool = true, own: PlaceReviewOwnStatus? = nil) -> PlaceReviewItem {
        .init(id: id, rating: 4, contents: "ok", isPublic: pub, ownStatus: own)
    }
    private func make(_ f: FakePlaceReviews) -> PlaceReviewCoordinator {
        var n = 0
        return PlaceReviewCoordinator(target: target, reader: f, writer: f, makeRequestID: { n += 1; return "req-\(n)" })
    }
    func testTargetAndDraftValidation() {
        XCTAssertNil(PlaceReviewTarget(placeID: 0))
        XCTAssertFalse(PlaceReviewDraft(rating: 0, contents: "x").isValid)
        XCTAssertFalse(PlaceReviewDraft(rating: 3, contents: "  \n").isValid)
        XCTAssertFalse(PlaceReviewDraft(rating: 3, contents: String(repeating: "a", count: 501)).isValid)
        XCTAssertTrue(PlaceReviewDraft(rating: 5, contents: "good").isValid)
    }
    func testDisabledProductionServiceNeverReadsOrWrites() async {
        let s = DisabledPlaceReviewService()
        let c = PlaceReviewCoordinator(target: target, reader: s, writer: s)
        await c.refresh(); XCTAssertTrue(c.items.isEmpty); XCTAssertFalse(c.canSubmit)
        await c.submit(.init(rating: 5, contents: "x")); XCTAssertEqual(c.state, .idle)
        do { _ = try await s.page(target, page: 1); XCTFail() } catch { XCTAssertEqual(error as? PlaceReviewFailure, .disabled) }
    }
    func testPaginationDedupesAndStopsAtEnd() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [item(1), item(2)], hasMore: true, canWrite: true)
        f.pages[2] = .init(page: 2, items: [item(2), item(3)], hasMore: false, canWrite: true)
        let c = make(f); await c.refresh(); await c.loadNext(); await c.loadNext()
        XCTAssertEqual(c.items.map(\.id), [1, 2, 3]); XCTAssertEqual(c.nextPage, 3); XCTAssertFalse(c.hasMore)
    }
    func testFailedPageKeepsPositionForRetry() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [item(1)], hasMore: true, canWrite: true)
        let c = make(f); await c.refresh(); await c.loadNext()
        XCTAssertTrue(c.loadFailed); XCTAssertEqual(c.nextPage, 2)
        f.pages[2] = .init(page: 2, items: [item(2)], hasMore: false, canWrite: true)
        await c.loadNext(); XCTAssertFalse(c.loadFailed); XCTAssertEqual(c.items.count, 2)
    }
    func testIneligibleCannotSubmit() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [], hasMore: false, canWrite: false)
        let c = make(f); await c.refresh()
        await c.submit(.init(rating: 5, contents: "x")); XCTAssertEqual(c.state, .idle); XCTAssertTrue(f.requestIDs.isEmpty)
    }
    func testOwnPendingIsNotPublicAndBlocksDuplicate() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [item(1)], hasMore: false, canWrite: true)
        let c = make(f); await c.refresh()
        await c.submit(.init(rating: 5, contents: " nice "))
        XCTAssertEqual(c.state, .ownPending)
        f.pages[1] = .init(page: 1, items: [item(1), item(5, pub: false, own: .pending)], hasMore: false, canWrite: true)
        await c.returnToList()
        XCTAssertEqual(c.publicItems.map(\.id), [1]); XCTAssertEqual(c.ownItem?.id, 5)
        await c.submit(.init(rating: 5, contents: "again")); XCTAssertEqual(f.requestIDs.count, 1)
    }
    func testUnknownLocksAndRetriesSameRequestIDOnlyForSameDraft() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [], hasMore: false, canWrite: true)
        let c = make(f); await c.refresh()
        let d = PlaceReviewDraft(rating: 4, contents: "meh")
        f.submitOutcome = .failure(.unknown); await c.submit(d)
        XCTAssertEqual(c.state, .unknownLocked); XCTAssertFalse(c.canSubmit)
        await c.submit(.init(rating: 1, contents: "different")); XCTAssertEqual(f.requestIDs.count, 1)
        f.submitOutcome = .success(.init(reviewID: 9, status: .published)); await c.submit(d)
        XCTAssertEqual(f.requestIDs, ["req-1", "req-1"]); XCTAssertEqual(c.state, .ownPublished)
    }
    func testReadbackResolvesUnknownWithoutReposting() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [], hasMore: false, canWrite: true)
        let c = make(f); await c.refresh()
        f.submitOutcome = .failure(.unknown); await c.submit(.init(rating: 4, contents: "x"))
        f.pages[1] = .init(page: 1, items: [item(7, pub: false, own: .pending)], hasMore: false, canWrite: true)
        await c.returnToList()
        XCTAssertEqual(c.state, .ownPending); XCTAssertEqual(f.requestIDs.count, 1)
    }
    func testRejectionAndNotSentAllowFreshAttempt() async {
        let f = FakePlaceReviews()
        f.pages[1] = .init(page: 1, items: [], hasMore: false, canWrite: true)
        let c = make(f); await c.refresh()
        f.submitOutcome = .failure(.rejected); await c.submit(.init(rating: 2, contents: "a"))
        XCTAssertEqual(c.state, .rejected); XCTAssertTrue(c.canSubmit)
        f.submitOutcome = .failure(.notSent); await c.submit(.init(rating: 2, contents: "a"))
        XCTAssertEqual(c.state, .notSent)
        f.submitOutcome = .success(.init(reviewID: 1, status: .pending)); await c.submit(.init(rating: 2, contents: "a"))
        XCTAssertEqual(f.requestIDs, ["req-1", "req-2", "req-3"]); XCTAssertEqual(c.state, .ownPending)
    }
}
