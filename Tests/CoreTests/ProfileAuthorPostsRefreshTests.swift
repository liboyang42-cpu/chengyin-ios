import XCTest
@testable import QuestifyCore

@MainActor final class ProfileAuthorPostsRefreshTests: XCTestCase {
    private final class Reader: SocialAccountReading, SquareReading {
        var identity = SocialAccountIdentity(accountID: 7, epoch: 1, role: "player")
        var presentationRevision: UInt64 = 0
        var scope = UUID(), isConfigured = true
        var isSignedIn: Bool { identity.accountID != nil }
        let isOfflineExample = true
        var replies: [Result<SquareFeedPage, Error>] = []
        var calls: [(SquareQuery, SquareCursor?)] = []
        var pending: CheckedContinuation<SquareFeedPage, Error>?
        var suspend = false
        func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage {
            calls.append((query, cursor))
            if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
            return try replies.removeFirst().get()
        }
        func squareDetail(id: Int) async throws -> SquarePost { throw APIError.notConfigured }
        func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage { throw APIError.notConfigured }
        func publicProfile(memberID: Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
        func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    private func page(_ ids: [Int], next: Int? = nil) throws -> SquareFeedPage {
        let rows = try ids.map { id in
            try JSONDecoder().decode(SquarePost.self, from: Data("{\"id\":\(id),\"authorId\":91}".utf8)).qualified(as: .communityV1)
        }
        return .init(items: rows, hasMore: next != nil, nextCursor: next.map { .init(id: $0) })
    }
    private func key(_ r: Reader, memberID: Int = 91) -> ProfileAuthorPostsContext { .init(memberID: memberID, accountReader: r, squareReader: r) }
    private func refresh(_ m: ProfileAuthorPostsRefreshController, _ r: Reader) async { await m.refresh(memberID: 91, accountReader: r, squareReader: r) }
    private func more(_ m: ProfileAuthorPostsRefreshController, _ r: Reader) async { await m.loadMore(memberID: 91, accountReader: r, squareReader: r) }
    private func retry(_ m: ProfileAuthorPostsRefreshController, _ r: Reader) async { await m.retry(memberID: 91, accountReader: r, squareReader: r) }
    private func waitForPending(_ r: Reader) async { for _ in 0..<100 where r.pending == nil { await Task.yield() }; XCTAssertNotNil(r.pending) }
    func testRefreshFailurePreservesAllPagesAndCursorThenRetryReplaces() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController()
        r.replies = [.success(try page([1], next: 1)), .success(try page([2], next: 2)), .failure(APIError.httpStatus(503)), .success(try page([3], next: 3)), .success(try page([4]))]
        await refresh(m, r); await more(m, r); await refresh(m, r)
        XCTAssertEqual(m.pagination.items.map(\.id), [1, 2]); XCTAssertEqual(m.pagination.nextCursor?.id, 2)
        XCTAssertEqual(m.failedOperation, .refresh); XCTAssertTrue(m.retainsPreviousResult)
        await more(m, r); XCTAssertEqual(r.calls.count, 3)
        await retry(m, r); XCTAssertEqual(m.pagination.items.map(\.id), [3]); XCTAssertNil(r.calls[3].1)
        await more(m, r); XCTAssertEqual(r.calls[4].1?.id, 3); XCTAssertEqual(m.pagination.items.map(\.id), [3, 4])
    }
    func testMoreFailureRetryUsesSameCursorWithoutDuplicatingRows() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController()
        r.replies = [.success(try page([1], next: 1)), .failure(APIError.httpStatus(503)), .success(try page([1, 2]))]
        await refresh(m, r); await more(m, r)
        XCTAssertEqual(m.failedOperation, .more); XCTAssertEqual(m.pagination.items.map(\.id), [1])
        await retry(m, r); XCTAssertEqual(r.calls[1].1, r.calls[2].1); XCTAssertEqual(m.pagination.items.map(\.id), [1, 2])
    }
    func testSuccessfulEmptyRefreshRemovesOldTailAndContinuation() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1], next: 1)), .success(try page([]))]
        await refresh(m, r); await refresh(m, r)
        XCTAssertTrue(m.pagination.hasLoadedPage); XCTAssertTrue(m.pagination.items.isEmpty)
        XCTAssertFalse(m.pagination.hasMore); XCTAssertNil(m.pagination.nextCursor); XCTAssertFalse(m.retainsPreviousResult)
    }
    func testFirstLoadFailureRetryIsFirstPageNotMore() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.failure(APIError.malformedResponse), .success(try page([1]))]
        await refresh(m, r); XCTAssertFalse(m.pagination.hasLoadedPage); XCTAssertEqual(m.failedOperation, .refresh)
        await retry(m, r); XCTAssertTrue(r.calls.allSatisfy { $0.1 == nil }); XCTAssertEqual(m.pagination.items.map(\.id), [1])
    }
    func testDenialsClearOldRowsAndDoNotRetainRetryCursor() async throws {
        for denial in [APIError.unauthorized, .httpStatus(403), .businessCode(2)] {
            let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1], next: 1)), .failure(denial)]
            await refresh(m, r); await refresh(m, r)
            XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertNil(m.failedOperation); XCTAssertFalse(m.retainsPreviousResult)
            await retry(m, r); XCTAssertEqual(r.calls.count, 2)
        }
    }
    func testSignedOutDisabledAndInvalidMemberNeverRead() async {
        let r = Reader(), m = ProfileAuthorPostsRefreshController()
        r.identity = .init(accountID: nil, epoch: 2); await refresh(m, r)
        r.identity = .init(accountID: 7, epoch: 3); r.isConfigured = false; await refresh(m, r)
        r.isConfigured = true; await m.refresh(memberID: 0, accountReader: r, squareReader: r)
        XCTAssertTrue(r.calls.isEmpty)
    }
    func testEveryRequestStaysOnSameAuthorQuery() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1], next: 1)), .success(try page([2]))]
        await refresh(m, r); await more(m, r)
        XCTAssertTrue(r.calls.allSatisfy { $0.0 == SquareQuery(authorID: 91) })
    }
    func testDuplicateRefreshAndMoreWhileInFlightDoNotSend() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.suspend = true
        let task = Task { await self.refresh(m, r) }; await waitForPending(r)
        await refresh(m, r); await more(m, r); await retry(m, r)
        XCTAssertEqual(r.calls.count, 1); r.pending?.resume(returning: try page([1])); r.pending = nil
        await task.value; XCTAssertFalse(m.isBusy)
    }
    func testRetireRejectsDelayedCompletion() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.suspend = true
        let task = Task { await self.refresh(m, r) }; await waitForPending(r); m.retire()
        r.pending?.resume(returning: try page([1])); r.pending = nil; await task.value
        XCTAssertNil(m.context); XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertFalse(m.isBusy)
    }
    func testViewerRevisionABARejectsDelayedResult() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.suspend = true
        let task = Task { await self.refresh(m, r) }; await waitForPending(r)
        r.presentationRevision += 2; r.pending?.resume(returning: try page([1])); r.pending = nil; await task.value
        XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertNil(m.context)
    }
    func testScopeChangeHidesRowsBeforeNextLoad() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1]))]
        await refresh(m, r); let row = try XCTUnwrap(m.pagination.items.first); r.scope = UUID()
        XCTAssertTrue(m.visibleRows(for: key(r)).isEmpty); XCTAssertFalse(m.canOpen(row, context: key(r)))
    }
    func testReaderSubjectAndRevisionEachChangeContext() {
        let r = Reader(), other = Reader(), before = key(r)
        XCTAssertNotEqual(before, key(r, memberID: 92))
        XCTAssertNotEqual(before, ProfileAuthorPostsContext(memberID: 91, accountReader: other, squareReader: r))
        XCTAssertNotEqual(before, ProfileAuthorPostsContext(memberID: 91, accountReader: r, squareReader: other))
        r.presentationRevision += 1; XCTAssertNotEqual(before, key(r))
    }
    func testRetiredParentNeverReadsOrOpens() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController()
        await m.refresh(memberID: 91, accountReader: r, squareReader: r, isCurrent: { false })
        XCTAssertTrue(r.calls.isEmpty); XCTAssertFalse(m.canOpen(try XCTUnwrap(try page([1]).items.first), context: key(r), isCurrent: false))
    }
    func testCancelledCompletionDoesNotPublishOrManufactureFailure() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.suspend = true
        let task = Task { await self.refresh(m, r) }; await waitForPending(r); task.cancel()
        r.pending?.resume(returning: try page([1])); r.pending = nil; await task.value
        XCTAssertTrue(m.pagination.items.isEmpty); XCTAssertNil(m.error); XCTAssertNil(m.failedOperation); XCTAssertFalse(m.isBusy)
    }
    func testMalformedContinuationStopsMoreButAllowsFreshRefresh() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController()
        r.replies = [.success(.init(items: try page([1]).items, hasMore: true, nextCursor: nil)), .success(try page([2]))]
        await refresh(m, r); XCTAssertTrue(m.pagination.continuationInvalid)
        await more(m, r); XCTAssertEqual(r.calls.count, 1)
        await refresh(m, r); XCTAssertEqual(m.pagination.items.map(\.id), [2]); XCTAssertFalse(m.pagination.continuationInvalid)
    }
    func testRefreshInFlightRetainsRowsAndSuspendRejectsLateReplacement() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1], next: 1))]
        await refresh(m, r); r.suspend = true
        let task = Task { await self.refresh(m, r) }; await waitForPending(r)
        XCTAssertTrue(m.retainsPreviousResult); XCTAssertEqual(m.visibleRows(for: key(r)).map(\.id), [1])
        m.suspend(); r.pending?.resume(returning: try page([2])); r.pending = nil; await task.value
        XCTAssertEqual(m.pagination.items.map(\.id), [1]); XCTAssertFalse(m.isBusy)
    }
    func testNewScopeCanStartWhileOldRequestFinishesLate() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.suspend = true
        let old = Task { await self.refresh(m, r) }; await waitForPending(r)
        let oldReply = r.pending; r.pending = nil; r.scope = UUID()
        let current = Task { await self.refresh(m, r) }; await waitForPending(r)
        r.pending?.resume(returning: try page([2])); r.pending = nil; await current.value
        oldReply?.resume(returning: try page([1])); await old.value
        XCTAssertEqual(r.calls.count, 2); XCTAssertEqual(m.pagination.items.map(\.id), [2]); XCTAssertEqual(m.context, key(r))
    }
    func testParentRetirementDuringReadClearsPreviousRows() async throws {
        let r = Reader(), m = ProfileAuthorPostsRefreshController(); r.replies = [.success(try page([1]))]
        await refresh(m, r); r.suspend = true; var current = true
        let task = Task { await m.refresh(memberID: 91, accountReader: r, squareReader: r, isCurrent: { current }) }
        await waitForPending(r); current = false
        r.pending?.resume(returning: try page([2])); r.pending = nil; await task.value
        XCTAssertNil(m.context); XCTAssertTrue(m.pagination.items.isEmpty)
    }

}
