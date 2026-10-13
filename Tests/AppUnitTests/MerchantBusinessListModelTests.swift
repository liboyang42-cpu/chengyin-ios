import XCTest
@testable import Questify

@MainActor final class MerchantBusinessListModelTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://list-tools", accountID: 99001, epoch: 1)
        let isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var authorizationGeneration: UUID?
        var merchantID = 610
        var includeCRM = true
        var failure: MerchantBusinessFailure?
        var calls: [MerchantBusinessQuery] = []
        var suspendQuery: MerchantBusinessQuery?
        var suspended: CheckedContinuation<Void, Never>?
        func access() async throws -> MerchantBusinessAccess {
            if let failure { throw failure }
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            fields["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic workshop")])
            if !includeCRM { fields["permissions"] = .array((fields["permissions"]?.array ?? []).filter { $0.string != "merchant:crm:read" }) }
            return try .init(fields)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls.append(query)
            let grant = try await access()
            if query == suspendQuery { await withCheckedContinuation { suspended = $0 } }
            return try .init(access: grant, document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.listToolsPayload(query)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("Presentation-only tests must not dispatch mutations")
            throw MerchantBusinessFailure.disabled
        }
    }
    func testChangingPresentationDoesNotReadAgainOrChangeBaseline() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        let before = try XCTUnwrap(model.coordinator.snapshot)
        model.listFilters.review = .pending
        model.listFilters.aftercareKeyword = "Synthetic Alice"
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
        XCTAssertEqual(model.coordinator.snapshot, before)
        XCTAssertEqual(model.listFilters.rows(in: before.document.sections[0], query: before.document.query).map(\.id), ["63001"])
        XCTAssertEqual(before.document.summary["pendingReplyCount"], .int(7))
    }
    func testLoadedPageSearchRetainsEarlierMatchesWithoutChangingSnapshot() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        await model.loadMoreAftercare()
        let snapshot = try XCTUnwrap(model.coordinator.snapshot)
        XCTAssertEqual(snapshot.document.query, .aftercare(.pending, page: 2))
        XCTAssertEqual(snapshot.document.rows.map(\.id), ["62021"])
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 21)
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).map(\.id), ["62001"])
        XCTAssertEqual(model.coordinator.snapshot, snapshot)
        model.listFilters.aftercareKeyword = "21"
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).map(\.id), ["62021"])
        model.listFilters.aftercareKeyword = ""
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).count, 21)
        await model.loadMoreAftercare()
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1), .aftercare(.pending, page: 2)])
        XCTAssertEqual(model.coordinator.snapshot, snapshot)
    }
    func testBucketAndRefreshReplaceAllLoadedRowsAndRetainKeyword() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.aftercare(.pending, page: 1)); await model.loadMoreAftercare()
        model.listFilters.aftercareKeyword = "21"
        await model.load(.aftercare(.pending, page: 2)) // Explicit refresh resets to page one.
        XCTAssertEqual(model.coordinator.snapshot?.document.query, .aftercare(.pending, page: 1))
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertFalse(model.aftercareLoadedPages?.rows.contains { $0.id == "62021" } ?? true)
        XCTAssertEqual(model.listFilters.aftercareKeyword, "21")
        await model.loadMoreAftercare()
        await model.load(.aftercare(.processing, page: 1))
        XCTAssertEqual(model.aftercareLoadedPages?.bucket, .processing)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertTrue(model.aftercareLoadedPages?.rows.allSatisfy { $0.fields.mbText("bucket") == "PROCESSING" } ?? false)
        XCTAssertEqual(model.listFilters.aftercareKeyword, "21")
    }
    func testReviewFilterPersistsAcrossPagesButOnlyMatchesNewRows() async throws {
        let model = MerchantBusinessViewModel(reader: Reader(), journal: MerchantBusinessMemoryIntentStore())
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        await model.load(.reviews(page: 2))
        let document = try XCTUnwrap(model.coordinator.snapshot?.document)
        XCTAssertEqual(model.listFilters.review, .photos)
        XCTAssertEqual(document.rows.map(\.id), ["63021"])
        XCTAssertTrue(model.listFilters.rows(in: document.sections[0], query: document.query).isEmpty)
        XCTAssertEqual(document.summary["replyRatePct"], .int(65))
    }
    func testScopeOrMerchantChangeClearsLocalSearch() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1)); tracked.listFilters.aftercareKeyword = "Alice"
        reader.scope = .init(realm: "synthetic://list-tools", accountID: 99002, epoch: 2)
        await tracked.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.listFilters, .init())
        tracked.listFilters.review = .pending; tracked.listFilters.aftercareKeyword = "Weather"
        reader.merchantID = 611
        await tracked.load(.reviews(page: 1))
        XCTAssertEqual(tracked.listFilters, .init())
        XCTAssertEqual(tracked.coordinator.snapshot?.access.merchantID, 611)
    }
    func testInvalidationClearsFiltersAndDataButPreservesUnknownIntent() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610, target: "review:63001", requestID: "synthetic-pending")
        try journal.reserve(intent)
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .pending; model.listFilters.aftercareKeyword = "Alice"
        XCTAssertTrue(model.coordinator.isLocked)
        model.invalidate()
        XCTAssertEqual(model.listFilters, .init()); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertNil(model.aftercareLoadedPages)
        XCTAssertEqual(try journal.intents(), [intent])
        await model.load(.reviews(page: 1)); XCTAssertTrue(model.coordinator.isLocked)
        model.prepare(.review(id: try .init(63001), version: 0, action: .reply, content: "Synthetic reply"))
        XCTAssertNil(model.coordinator.confirmation)
        XCTAssertEqual(try journal.intents(), [intent])
    }
    func testFailedReplacementNeverKeepsOldRowsOrMetrics() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.reviews(page: 1)); tracked.listFilters.review = .photos
        reader.failure = .denied
        await tracked.load(.reviews(page: 2))
        XCTAssertNil(tracked.coordinator.snapshot); XCTAssertFalse(tracked.coordinator.isCurrent)
        XCTAssertEqual(tracked.coordinator.failure, .denied)
    }
    func testMerchantChangeAfterFailedLoadStillClearsPriorMerchantFilter() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.failure = .denied; await model.loadMoreAftercare()
        XCTAssertNil(model.coordinator.snapshot)
        reader.failure = nil; reader.merchantID = 611
        await model.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(model.coordinator.snapshot?.access.merchantID, 611)
    }
    func testOlderLoadCannotRestoreMerchantRowsOrOverwriteNewFilter() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        reader.suspendQuery = .reviews(page: 2)
        let older = Task { await model.load(.reviews(page: 2)) }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic load did not suspend") }
        reader.merchantID = 611
        await model.load(.reviews(page: 1))
        XCTAssertEqual(model.listFilters, .init())
        model.listFilters.review = .low
        continuation.resume(); await older.value
        XCTAssertEqual(model.coordinator.snapshot?.access.merchantID, 611)
        XCTAssertEqual(model.coordinator.snapshot?.document.query, .reviews(page: 1))
        XCTAssertEqual(model.listFilters.review, .low)
        XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testFailedLoadMoreClearsAccumulationAndRefreshCanRecover() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1)); tracked.listFilters.aftercareKeyword = "Alice"
        reader.failure = .denied; await tracked.loadMoreAftercare()
        XCTAssertNil(tracked.aftercareLoadedPages); XCTAssertNil(tracked.coordinator.snapshot)
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
        reader.failure = nil; await tracked.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.aftercareLoadedPages?.rows.count, 20)
    }
    func testMerchantOrPermissionChangeDuringAppendCannotMixRows() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.merchantID = 611
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(model.aftercareLoadFailureKey, "merchant.business.stale")
        await model.load(.aftercare(.pending, page: 1))
        reader.includeCRM = false
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.aftercareLoadFailureKey, "merchant.business.stale")
    }
    func testRefreshDuringSuspendedAppendFencesOlderGeneration() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await tracked.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        await tracked.load(.aftercare(.pending, page: 1))
        tracked.listFilters.aftercareKeyword = "Alice"
        continuation.resume(); await older.value
        XCTAssertEqual(tracked.aftercareLoadedPages?.rows.count, 20)
        XCTAssertEqual(tracked.aftercareLoadedPages?.page, 1)
        XCTAssertEqual(tracked.coordinator.snapshot?.document.query, .aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
    }
    func testBucketChangeDuringSuspendedAppendFencesOldRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        await model.load(.aftercare(.processing, page: 1))
        continuation.resume(); await older.value
        XCTAssertEqual(model.aftercareLoadedPages?.bucket, .processing)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertTrue(model.aftercareLoadedPages?.rows.allSatisfy { $0.fields.mbText("bucket") == "PROCESSING" } ?? false)
    }
    func testCancelledAppendCannotRestoreAccumulation() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        pending.cancel(); continuation.resume(); await pending.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }
    func testAuthorizationChangeBeforeLoadMoreClearsWithoutReading() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.authorizationGeneration = UUID()
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1)])
    }
    func testAuthorizationChangeDuringAppendDiscardsAllRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.authorizationGeneration = UUID()
        continuation.resume(); await pending.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }
    func testRepeatedLoadMoreWhileBusyDoesNotReadOrAppendTwice() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        await model.loadMoreAftercare()
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1), .aftercare(.pending, page: 2)])
        continuation.resume(); await pending.value
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 21)
    }
    func testScopeChangeDuringAppendClearsOldAccountRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.scope = .init(realm: "synthetic://list-tools", accountID: 99002, epoch: 2)
        await model.load(.aftercare(.pending, page: 1))
        continuation.resume(); await older.value
        XCTAssertEqual(model.aftercareLoadedPages?.scope.accountID, 99002)
        XCTAssertEqual(model.aftercareLoadedPages?.page, 1)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
    }
    func testDismissalDuringAppendCannotRepopulateClosedList() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        model.invalidate()
        continuation.resume(); await older.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
    }
    func testAccumulatedNavigationKeepsExactDetailAndUnknownIntent() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610, target: "refund:62001", requestID: "synthetic-unknown")
        try journal.reserve(intent)
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); await model.loadMoreAftercare()
        let first = try XCTUnwrap(model.aftercareLoadedPages?.rows.first)
        XCTAssertEqual(first.destination, .refund(try .init(62001)))
        XCTAssertEqual(model.coordinator.snapshot?.document.rows.map(\.id), ["62021"])
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertNil(model.coordinator.confirmation)
        model.prepare(.aftercare(refund: try .init(62001), decision: .agree, content: "", evidenceKey: nil))
        XCTAssertNil(model.coordinator.confirmation); XCTAssertEqual(try journal.intents(), [intent])
        model.invalidate()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertEqual(try journal.intents(), [intent])
    }

    func testReviewCancelledAppendCannotRestoreAccumulation() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let pending = Task { await model.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        pending.cancel(); continuation.resume(); await pending.value
        XCTAssertNil(model.reviewLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }

    func testReviewAuthorizationChangeBeforeLoadMoreClearsWithoutReading() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        reader.authorizationGeneration = UUID()
        await model.loadMoreReviews()
        XCTAssertNil(model.reviewLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
    }

    func testReviewAuthorizationChangeDuringAppendDiscardsAllRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let pending = Task { await model.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.authorizationGeneration = UUID()
        continuation.resume(); await pending.value
        XCTAssertNil(model.reviewLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }

    func testReviewRepeatedLoadMoreWhileBusyDoesNotReadOrAppendTwice() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let pending = Task { await model.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        await model.loadMoreReviews()
        XCTAssertEqual(reader.calls, [.reviews(page: 1), .reviews(page: 2)])
        continuation.resume(); await pending.value
        XCTAssertEqual(model.reviewLoadedPages?.rows.count, 21)
    }

    func testReviewScopeChangeDuringAppendClearsOldAccountRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let older = Task { await model.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.scope = .init(realm: "synthetic://list-tools", accountID: 99002, epoch: 2)
        await model.load(.reviews(page: 1))
        continuation.resume(); await older.value
        XCTAssertEqual(model.reviewLoadedPages?.scope.accountID, 99002)
        XCTAssertEqual(model.reviewLoadedPages?.page, 1)
        XCTAssertEqual(model.reviewLoadedPages?.rows.count, 20)
    }

    func testReviewDismissalDuringAppendCannotRepopulateClosedList() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let older = Task { await model.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        model.invalidate()
        continuation.resume(); await older.value
        XCTAssertNil(model.reviewLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
    }

    func testReviewRefreshDuringSuspendedAppendFencesOlderGeneration() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.reviews(page: 1))
        reader.suspendQuery = .reviews(page: 2)
        let older = Task { await tracked.loadMoreReviews() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        await tracked.load(.reviews(page: 1))
        tracked.listFilters.review = .photos
        continuation.resume(); await older.value
        XCTAssertEqual(tracked.reviewLoadedPages?.rows.count, 20)
        XCTAssertEqual(tracked.reviewLoadedPages?.page, 1)
        XCTAssertEqual(tracked.coordinator.snapshot?.document.query, .reviews(page: 1))
        XCTAssertEqual(tracked.listFilters.review, .photos)
    }

    func testReviewFailedLoadMoreClearsAccumulationAndRefreshCanRecover() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.reviews(page: 1)); tracked.listFilters.review = .photos
        reader.failure = .denied; await tracked.loadMoreReviews()
        XCTAssertNil(tracked.reviewLoadedPages); XCTAssertNil(tracked.coordinator.snapshot)
        XCTAssertEqual(tracked.listFilters.review, .photos)
        reader.failure = nil; await tracked.load(.reviews(page: 1))
        XCTAssertEqual(tracked.reviewLoadedPages?.rows.count, 20)
    }

    func testReviewLoadMoreRetainsFilteredRowsWithoutChangingMutationAuthority() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        await model.loadMoreReviews()
        let snapshot = try XCTUnwrap(model.coordinator.snapshot)
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).map(\.id), ["63003"])
        XCTAssertEqual(snapshot.document.rows.map(\.id), ["63021"])
        let row = try XCTUnwrap(model.reviewLoadedPages?.rows.first)
        XCTAssertEqual(model.reviewSourcePage(for: row)?.query, .reviews(page: 1))
        model.prepare(.review(id: try .init(63001), version: try row.fields.mbInt("version"), action: .reply, content: "Synthetic reply"))
        XCTAssertNil(model.coordinator.confirmation)
        XCTAssertTrue(try journal.intents().isEmpty)
        await model.load(.reviews(page: 1))
        XCTAssertEqual(model.reviewLoadedPages?.rows.count, 20)
        XCTAssertEqual(model.listFilters.review, .photos)
    }
    func testReviewMerchantAndPermissionChangesRejectAppend() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.reviews(page: 1)); reader.merchantID = 611
        await tracked.loadMoreReviews()
        XCTAssertNil(tracked.reviewLoadedPages); XCTAssertNil(tracked.coordinator.snapshot)
        XCTAssertEqual(tracked.aftercareLoadFailureKey, "merchant.business.stale")
        await tracked.load(.reviews(page: 1)); reader.includeCRM = false
        await tracked.loadMoreReviews()
        XCTAssertNil(tracked.reviewLoadedPages); XCTAssertNil(tracked.coordinator.snapshot)
    }
    func testReviewOriginalPageUsesSeparateFreshCoordinatorAndKeepsUnknownJournal() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610, target: "review:63001", requestID: "synthetic-unknown")
        try journal.reserve(intent)
        let list = MerchantBusinessViewModel(reader: reader, journal: journal)
        await list.load(.reviews(page: 1)); await list.loadMoreReviews()
        let destination = try XCTUnwrap(list.reviewSourcePage(for: try XCTUnwrap(list.reviewLoadedPages?.rows.first)))
        let original = MerchantBusinessViewModel(reader: reader, journal: journal)
        await original.load(destination.query)
        let snapshot = try XCTUnwrap(original.coordinator.snapshot)
        XCTAssertTrue(destination.matches(scope: reader.scope, authorizationGeneration: reader.authorizationGeneration, snapshot: snapshot))
        XCTAssertEqual(list.coordinator.snapshot?.document.query, .reviews(page: 2))
        original.prepare(.review(id: try .init(63001), version: try snapshot.document.rows[0].fields.mbInt("version"), action: .reply, content: "Synthetic reply"))
        XCTAssertNil(original.coordinator.confirmation)
        list.invalidate(); original.invalidate()
        XCTAssertEqual(try journal.intents(), [intent])
    }
}

extension MerchantBusinessListModelTests {
    func testCustomerFilterDisclosurePreservesInputsSnapshotAndReadCount() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.customers(.init()))
        let before = try XCTUnwrap(model.coordinator.snapshot), calls = reader.calls
        let revision = model.revision, authorization = reader.authorizationGeneration
        var unapplied = MerchantCustomerQuery()
        unapplied.keyword = "Unapplied search"; unapplied.sourceType = 2
        unapplied.sourceStart = "2026-10-01"; unapplied.sourceEnd = "2026-10-12"
        let originalInput = unapplied
        let presentation = MerchantCustomerFilterDisclosure()
        presentation.viewAppeared(sceneIsActive: true)
        let binding = presentation.binding { true }
        XCTAssertTrue(binding.wrappedValue)
        binding.wrappedValue = false; XCTAssertFalse(presentation.isExpanded)
        binding.wrappedValue = true; XCTAssertTrue(presentation.isExpanded)
        XCTAssertEqual(unapplied, originalInput)
        XCTAssertEqual(model.coordinator.snapshot, before); XCTAssertEqual(reader.calls, calls)
        XCTAssertEqual(model.revision, revision); XCTAssertEqual(reader.authorizationGeneration, authorization)
        XCTAssertNil(model.coordinator.confirmation)
    }
    func testOldCustomerFilterBindingCannotCloseReappearedPanel() {
        let presentation = MerchantCustomerFilterDisclosure()
        presentation.viewAppeared(sceneIsActive: true)
        let old = presentation.binding { true }
        presentation.viewDisappeared()
        presentation.sceneChanged(isActive: false); presentation.sceneChanged(isActive: true)
        XCTAssertFalse(old.wrappedValue)
        old.wrappedValue = false; XCTAssertTrue(presentation.isExpanded)
        presentation.viewAppeared(sceneIsActive: true)
        old.wrappedValue = false; XCTAssertTrue(presentation.isExpanded)
        let current = presentation.binding { true }
        current.wrappedValue = false; XCTAssertFalse(presentation.isExpanded)
        presentation.viewAppeared(sceneIsActive: true)
        XCTAssertFalse(current.wrappedValue)
        current.wrappedValue = true; XCTAssertTrue(presentation.isExpanded)
    }
    func testCustomerFilterAuthorizationBeforeOwnerCallbackRejectsOldBinding() {
        let presentation = MerchantCustomerFilterDisclosure()
        presentation.viewAppeared(sceneIsActive: true)
        var currentOwner = UUID(); let capturedOwner = currentOwner
        let old = presentation.binding { currentOwner == capturedOwner }
        currentOwner = UUID()
        old.wrappedValue = false; XCTAssertTrue(presentation.isExpanded)
        XCTAssertFalse(old.wrappedValue)
        presentation.ownerChanged()
        let current = presentation.binding { true }
        current.wrappedValue = false; XCTAssertFalse(presentation.isExpanded)
        old.wrappedValue = true; XCTAssertFalse(presentation.isExpanded)
    }
    func testCustomerFilterInactiveAndHiddenCallbacksStayLocalAndRetired() {
        let presentation = MerchantCustomerFilterDisclosure()
        presentation.viewAppeared(sceneIsActive: false)
        let inactive = presentation.binding { true }
        inactive.wrappedValue = false; XCTAssertTrue(presentation.isExpanded)
        presentation.sceneChanged(isActive: true)
        let active = presentation.binding { true }
        active.wrappedValue = false; XCTAssertFalse(presentation.isExpanded)
        presentation.sceneChanged(isActive: false); presentation.sceneChanged(isActive: true)
        active.wrappedValue = true; XCTAssertFalse(presentation.isExpanded)
        let refreshed = presentation.binding { true }
        refreshed.wrappedValue = true; XCTAssertTrue(presentation.isExpanded)
        presentation.viewDisappeared(); presentation.ownerChanged()
        let hidden = presentation.binding { true }
        hidden.wrappedValue = false; XCTAssertTrue(presentation.isExpanded)
    }
}

@MainActor final class MerchantTeamResultRefreshTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://team-result", accountID: 99001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        let isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
        var reads = 0, sends = 0, merchantID = 610
        var readFailure: MerchantBusinessFailure?, sendFailure: MerchantBusinessFailure?
        var mutation: MerchantBusinessMutation?
        var holdSend = false, holdResultRead = false
        var sendContinuation: CheckedContinuation<Void, Never>?
        var readContinuation: CheckedContinuation<Void, Never>?
        var entered: XCTestExpectation?
        func access() async throws -> MerchantBusinessAccess {
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            fields["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic team")])
            return try .init(fields)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            if sends > 0 {
                if holdResultRead { await withCheckedContinuation { readContinuation = $0; entered?.fulfill() } }
                if let readFailure { throw readFailure }
            }
            let grant = try await access(); try grant.require(query.permissions)
            var payload = try MerchantBusinessSyntheticFixtures.payload(query)
            if query == .operators, let mutation {
                var fields = try XCTUnwrap(payload.object)
                let key: String
                switch mutation { case .revokeInvite: key = "invites"; default: key = "operators" }
                var rows = try XCTUnwrap(fields[key]?.array)
                var row = try XCTUnwrap(rows.first?.object)
                switch mutation {
                case .operatorRole(_, _, let role): row["roleCode"] = .string(role); row["version"] = .int(3)
                case .removeOperator: row["status"] = .string("REVOKED"); row["version"] = .int(3)
                case .revokeInvite: row["status"] = .string("REVOKED"); row["version"] = .int(1)
                default: XCTFail("Unexpected team mutation")
                }
                rows[0] = .object(row); fields[key] = .array(rows); payload = .object(fields)
            }
            let roles = try MerchantBusinessDocument(query: .roles, payload: MerchantBusinessSyntheticFixtures.payload(.roles))
            return try .init(access: grant, document: .init(query: query, payload: payload), roles: query == .operators ? roles : nil)
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            sends += 1
            if holdSend { await withCheckedContinuation { sendContinuation = $0; entered?.fulfill() } }
            if let sendFailure { throw sendFailure }
            self.mutation = mutation
            var fields: MerchantBusinessObject
            switch mutation {
            case .operatorRole(let id, let version, let role):
                fields = ["id": .int(id.rawValue), "version": .int(version + 1), "roleCode": .string(role), "status": .string("ACTIVE")]
            case .removeOperator(let id, let version, _):
                fields = ["id": .int(id.rawValue), "version": .int(version + 1), "roleCode": .string("MERCHANT_CHECKIN"), "status": .string("REVOKED")]
            case .revokeInvite(let id, let version, _):
                fields = ["id": .int(id.rawValue), "version": .int(version + 1), "roleCode": .string("MERCHANT_MARKETING"), "status": .string("REVOKED")]
            default: throw MerchantBusinessFailure.invalid
            }
            switch mutation {
            case .revokeInvite: fields["expiresAt"] = .string("2026-10-08 09:00:00")
            default: fields["acceptedAt"] = .string("2026-09-01 09:00:00")
            }
            fields["mutationState"] = .string("EXACT_RESULT")
            return try .init(mutation: mutation, message: "Synthetic acknowledged", data: .object(fields))
        }
    }
    private func setup(_ mutation: MerchantBusinessMutation) async throws -> (Reader, MerchantBusinessViewModel, MerchantBusinessConfirmation) {
        let reader = Reader(), model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        model.teamPageAppeared(active: true); await model.load(.operators); model.prepare(mutation)
        return (reader, model, try XCTUnwrap(model.coordinator.confirmation))
    }
    private func removal() throws -> MerchantBusinessMutation { .removeOperator(id: try .init(67001), version: 2, reason: "Synthetic removal") }
    func testThreeAcknowledgedMutationsReadCurrentTeamOnceAndRetainReceipt() async throws {
        for mutation in [try removal(), .operatorRole(id: try .init(67001), version: 2, role: "MERCHANT_FINANCE"), .revokeInvite(id: try .init(68001), version: 0, reason: "Synthetic revoke")] {
            let (reader, model, review) = try await setup(mutation)
            await model.confirm(review)
            XCTAssertEqual(reader.sends, 1); XCTAssertEqual(reader.reads, 3)
            XCTAssertEqual(model.coordinator.snapshot?.document.query, .operators)
            XCTAssertNotNil(model.teamReturnReceipt); XCTAssertNil(model.coordinator.receipt)
            XCTAssertFalse(model.coordinator.isLocked); XCTAssertNil(model.coordinator.failureKey)
            XCTAssertEqual(model.teamReturnReceipt?.message, "Synthetic acknowledged")
        }
    }
    func testFreshReadFailureKeepsReceiptAndRetryNeverRepeatsMutation() async throws {
        let (reader, model, review) = try await setup(removal()); reader.readFailure = .malformed
        await model.confirm(review)
        let receipt = try XCTUnwrap(model.teamReturnReceipt)
        XCTAssertNil(model.coordinator.snapshot); XCTAssertNotNil(model.coordinator.failureKey)
        reader.readFailure = nil; await model.load(.operators)
        XCTAssertEqual(model.teamReturnReceipt, receipt); XCTAssertNotNil(model.coordinator.snapshot)
        XCTAssertEqual(reader.sends, 1); XCTAssertEqual(reader.reads, 4)
    }
    func testUnknownDoesNotReadReturnOrUnlock() async throws {
        let (reader, model, review) = try await setup(removal()); reader.sendFailure = .unknown
        await model.confirm(review)
        XCTAssertEqual(reader.sends, 1); XCTAssertEqual(reader.reads, 2)
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertNil(model.teamReturnReceipt)
    }
    func testCancelledReviewCannotTriggerReturnReadOrWrite() async throws {
        let (reader, model, review) = try await setup(removal()); model.cancel()
        await model.confirm(review)
        XCTAssertEqual(reader.sends, 0); XCTAssertEqual(reader.reads, 1); XCTAssertNil(model.teamReturnReceipt)
    }
    func testDepartureDuringSendRejectsLateReceiptAndAutoRead() async throws {
        let (reader, model, review) = try await setup(removal())
        reader.holdSend = true; let entered = expectation(description: "send"); reader.entered = entered
        let task = Task { await model.confirm(review) }; await fulfillment(of: [entered], timeout: 1)
        model.teamPageDisappeared(); model.invalidate()
        reader.sendContinuation?.resume(); reader.sendContinuation = nil; await task.value
        XCTAssertNil(model.teamReturnReceipt); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(reader.sends, 1)
    }
    func testBackgroundDuringReturnReadCannotPublishLateTeam() async throws {
        let (reader, model, review) = try await setup(removal())
        reader.holdResultRead = true; let entered = expectation(description: "return read"); reader.entered = entered
        let task = Task { await model.confirm(review) }; await fulfillment(of: [entered], timeout: 1)
        model.teamPageSceneChanged(active: false)
        reader.readContinuation?.resume(); reader.readContinuation = nil; await task.value
        XCTAssertNil(model.teamReturnReceipt); XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(reader.sends, 1)
        model.teamPageDisappeared(); model.teamPageSceneChanged(active: true)
        XCTAssertNil(model.teamReturnReceipt)
    }
    func testSameScopeDifferentMerchantReturnDoesNotPublishOtherTeam() async throws {
        let (reader, model, review) = try await setup(removal())
        reader.holdResultRead = true; let entered = expectation(description: "return read"); reader.entered = entered
        let task = Task { await model.confirm(review) }; await fulfillment(of: [entered], timeout: 1)
        reader.merchantID = 611
        reader.readContinuation?.resume(); reader.readContinuation = nil; await task.value
        XCTAssertNil(model.teamReturnReceipt); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.aftercareLoadFailureKey, "merchant.business.stale"); XCTAssertEqual(reader.sends, 1)
    }
    func testAuthorizationSwitchDuringReturnReadRejectsReceiptAndRows() async throws {
        let (reader, model, review) = try await setup(removal())
        reader.holdResultRead = true; let entered = expectation(description: "return read"); reader.entered = entered
        let task = Task { await model.confirm(review) }; await fulfillment(of: [entered], timeout: 1)
        reader.authorizationGeneration = UUID()
        reader.readContinuation?.resume(); reader.readContinuation = nil; await task.value
        XCTAssertNil(model.teamReturnReceipt); XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(reader.sends, 1)
    }
}

extension MerchantTeamResultRefreshTests {
    func testForegroundAfterInterruptedReturnOffersExplicitReadRecoveryWithoutResending() async throws {
        let (reader, model, review) = try await setup(removal())
        reader.holdResultRead = true; let entered = expectation(description: "return read"); reader.entered = entered
        let task = Task { await model.confirm(review) }; await fulfillment(of: [entered], timeout: 1)
        model.teamPageSceneChanged(active: false)
        reader.readContinuation?.resume(); reader.readContinuation = nil; await task.value
        XCTAssertNil(model.teamRecoveryID); XCTAssertNil(model.coordinator.snapshot)
        model.teamPageSceneChanged(active: true)
        let ticket = try XCTUnwrap(model.teamRecoveryID)
        XCTAssertEqual(ticket, review.id); XCTAssertEqual(reader.reads, 3); XCTAssertEqual(reader.sends, 1)
        reader.holdResultRead = false; reader.readFailure = .malformed
        await model.retryTeamRead(ticket)
        XCTAssertEqual(model.teamRecoveryID, ticket); XCTAssertNil(model.coordinator.snapshot)
        reader.readFailure = nil; await model.retryTeamRead(ticket)
        XCTAssertNil(model.teamRecoveryID); XCTAssertNotNil(model.coordinator.snapshot)
        XCTAssertEqual(reader.reads, 5); XCTAssertEqual(reader.sends, 1)
        await model.retryTeamRead(ticket); XCTAssertEqual(reader.reads, 5)
    }
    func testHiddenParentCannotUseRecoveryAndAppearanceDoesNotReviveOldTicket() async throws {
        let (reader, model, review) = try await setup(removal()); await model.confirm(review)
        model.teamPageSceneChanged(active: false); model.teamPageSceneChanged(active: true)
        let ticket = try XCTUnwrap(model.teamRecoveryID), reads = reader.reads
        model.teamPageDisappeared(); model.teamPageSceneChanged(active: true)
        await model.retryTeamRead(ticket); XCTAssertEqual(reader.reads, reads)
        model.teamPageAppeared(active: true)
        XCTAssertNil(model.teamRecoveryID); await model.retryTeamRead(ticket)
        XCTAssertEqual(reader.reads, reads); XCTAssertEqual(reader.sends, 1)
    }
    func testOldRecoveryAfterAccountChangeCannotReadOrClearNewSnapshot() async throws {
        let (reader, model, review) = try await setup(removal()); await model.confirm(review)
        model.teamPageSceneChanged(active: false); model.teamPageSceneChanged(active: true)
        let old = try XCTUnwrap(model.teamRecoveryID)
        reader.scope = .init(realm: "synthetic://team-result", accountID: 99002, epoch: 2)
        model.invalidate(); model.teamPageAppeared(active: true); await model.load(.operators)
        let newer = model.coordinator.snapshot, reads = reader.reads
        await model.retryTeamRead(old)
        XCTAssertNil(model.teamRecoveryID); XCTAssertEqual(model.coordinator.snapshot, newer)
        XCTAssertEqual(reader.reads, reads); XCTAssertEqual(reader.sends, 1)
    }
}

extension MerchantTeamResultRefreshTests {
    func testLateRecoveryReadCannotReplaceNewOwnerRows() async throws {
        let (reader, model, review) = try await setup(removal()); await model.confirm(review)
        model.teamPageSceneChanged(active: false); model.teamPageSceneChanged(active: true)
        let ticket = try XCTUnwrap(model.teamRecoveryID)
        reader.holdResultRead = true; let entered = expectation(description: "recovery read"); reader.entered = entered
        let old = Task { await model.retryTeamRead(ticket) }; await fulfillment(of: [entered], timeout: 1)
        let continuation = reader.readContinuation; reader.readContinuation = nil
        reader.scope = .init(realm: "synthetic://team-result", accountID: 99002, epoch: 2)
        reader.merchantID = 611; reader.holdResultRead = false
        model.invalidate(); model.teamPageAppeared(active: true); await model.load(.operators)
        let newer = model.coordinator.snapshot; XCTAssertEqual(newer?.access.merchantID, 611)
        continuation?.resume(); await old.value
        XCTAssertEqual(model.coordinator.snapshot, newer); XCTAssertNil(model.teamRecoveryID)
        XCTAssertEqual(reader.sends, 1)
    }
}
