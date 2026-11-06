import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileAuthorPostsRefreshAppTests: XCTestCase {
    private func refresh(_ m: ProfileAuthorPostsRefreshController, _ r: ProfileAuthorPostsRefreshFixtureReader) async {
        await m.refresh(memberID: 91, accountReader: r, squareReader: r)
    }
    private func more(_ m: ProfileAuthorPostsRefreshController, _ r: ProfileAuthorPostsRefreshFixtureReader) async {
        await m.loadMore(memberID: 91, accountReader: r, squareReader: r)
    }
    func testReconstructedSectionsSharePageOwnedFeedWithoutAnotherRead() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(), model = ProfileAuthorPostsRefreshController()
        _ = ProfileAuthorPostsSection(memberID: 91, accountReader: r, squareReader: r, retainedModel: model)
        await model.activate(memberID: 91, accountReader: r, squareReader: r)
        await more(model, r); model.suspend()
        _ = ProfileAuthorPostsSection(memberID: 91, accountReader: r, squareReader: r, retainedModel: model)
        await model.activate(memberID: 91, accountReader: r, squareReader: r)
        XCTAssertEqual(r.reads, 2); XCTAssertEqual(model.pagination.items.map(\.id), [101, 201])
        let fresh = ProfileAuthorPostsRefreshController()
        await fresh.activate(memberID: 91, accountReader: r, squareReader: r)
        XCTAssertEqual(r.reads, 3); XCTAssertEqual(fresh.pagination.items.map(\.id), [301])
    }
    func testSelectedPostTicketRetainsGenerationButNotChangedReaderAuthority() async throws {
        let r = ProfileAuthorPostsRefreshFixtureReader(), model = ProfileAuthorPostsRefreshController()
        await refresh(model, r)
        let post = try XCTUnwrap(model.pagination.items.first)
        let context = ProfileAuthorPostsContext(memberID: 91, accountReader: r, squareReader: r)
        let ticket = ProfileAuthorPostTicket(postID: post.id, contentGeneration: post.generation, context: context)
        XCTAssertEqual(ticket.contentGeneration, post.generation)
        r.switchAccount()
        XCTAssertNotEqual(ticket.context, ProfileAuthorPostsContext(memberID: 91, accountReader: r, squareReader: r))
    }
    func testDedicatedFixtureBuildsRealSectionWithoutSessionOrImageReader() {
        let r = ProfileAuthorPostsRefreshFixtureReader()
        _ = ProfileAuthorPostsSection(memberID: 91, accountReader: r, squareReader: r)
        _ = ProfileAuthorPostsRefreshFixtureHost(scenario: "refreshFailure")
    }
    func testRefreshFailureRetainsTwoPagesAndRetryReplaces() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(scenario: "refreshFailure"), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); await more(m, r); await refresh(m, r)
        XCTAssertEqual(m.pagination.items.map(\.id), [101, 201]); XCTAssertTrue(m.retainsPreviousResult)
        await m.retry(memberID: 91, accountReader: r, squareReader: r)
        XCTAssertEqual(m.pagination.items.map(\.id), [301]); XCTAssertFalse(m.retainsPreviousResult)
    }
    func testEmptyRefreshIsAuthoritative() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(scenario: "emptyRefresh"), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); await refresh(m, r)
        XCTAssertTrue(m.pagination.hasLoadedPage); XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertNil(m.error)
    }
    func testMoreFailureHasSeparateRetryIntent() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(scenario: "moreFailure"), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); await more(m, r); XCTAssertEqual(m.failedOperation, .more)
        await m.retry(memberID: 91, accountReader: r, squareReader: r)
        XCTAssertEqual(m.pagination.items.map(\.id), [101, 201]); XCTAssertNil(m.error)
    }
    func testSignedOutSnapshotCannotOpenAFormerDetail() async throws {
        let r = ProfileAuthorPostsRefreshFixtureReader(), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); let row = try XCTUnwrap(m.pagination.items.first); r.signOut()
        let key = ProfileAuthorPostsContext(memberID: 91, accountReader: r, squareReader: r)
        XCTAssertFalse(m.canOpen(row, context: key)); await refresh(m, r); XCTAssertEqual(r.reads, 1)
    }
    func testAccountSwitchDoesNotMixOldAndNewPosts() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); r.switchAccount(); await refresh(m, r)
        XCTAssertEqual(m.pagination.items.map(\.id), [821])
    }
    func testOpeningDetailKeepsScopedSourceRowWhileStoppingPendingRead() async throws {
        let r = ProfileAuthorPostsRefreshFixtureReader(), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); let row = try XCTUnwrap(m.pagination.items.first)
        m.suspend(); XCTAssertTrue(m.canOpen(row, context: .init(memberID: 91, accountReader: r, squareReader: r)))
        await refresh(m, r); XCTAssertEqual(m.pagination.items.map(\.id), [301])
    }
    func testExplicitDenialRemovesExistingCards() async {
        let r = ProfileAuthorPostsRefreshFixtureReader(scenario: "denied"), m = ProfileAuthorPostsRefreshController()
        await refresh(m, r); await refresh(m, r)
        XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertNil(m.failedOperation)
        XCTAssertEqual(m.error as? APIError, .unauthorized)
    }
}
